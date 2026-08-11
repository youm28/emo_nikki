"""感情記録のリマインダーを FCM で送るスクリプト。

Web アプリ自身は「毎時0分に鳴らす」予約ができないため、外部から定時に
このスクリプトを実行して通知を送る（.github/workflows/reminders.yml）。

元研究(Emoji_watch)に合わせ、10:00〜19:00 の毎時に1回送る。

**1時間に何度呼ばれても、送るのは1回だけ**である点に注意。
GitHub Actions の cron は「その時刻に必ず動く」保証がなく、実測では
7回中3回が実行されず、動いた回も最大55分遅れていた。そこで呼び出し側は
1時間に4回試し、こちら側で「その時間帯にもう送ったか」を見て重複を防ぐ。

重複防止のやり方:
    reminders/{yyyy-MM-dd-HH} というドキュメントを **create** できた回だけ送る。
    create は既に在ると失敗するので、同時に走っても1回しか通らない。
    （日記の「1日1件」や端末トークンと同じ、IDで一意性を表す書き方）

認証:
    サービスアカウントの秘密鍵JSONを、環境変数 GOOGLE_APPLICATION_CREDENTIALS_JSON
    に中身ごと入れておく（GitHub Actions の Secrets 用）。
    ローカルで試すときは GOOGLE_APPLICATION_CREDENTIALS にファイルパスでもよい。

使い方:
    python tools/send_reminders.py            # その時間帯がまだなら送る
    python tools/send_reminders.py --dry-run  # 送信せず対象だけ表示する
    python tools/send_reminders.py --force    # 時間帯の判定を無視して送る（手動確認用）
"""

import argparse
import json
import os
import sys
from datetime import datetime, timedelta, timezone

import firebase_admin
from firebase_admin import credentials, firestore, messaging
from google.api_core import exceptions as google_exceptions

# 通知を送る時間帯（JST）。両端を含む＝10時台〜19時台の10回。
JST = timezone(timedelta(hours=9))
SEND_HOUR_FIRST = 10
SEND_HOUR_LAST = 19

# 通知をタップしたときに開くURL。?u=<ユーザー名> を付けて本人の画面に入れる。
APP_URL = "https://emo-nikki-eyuma1218-4155e.web.app/"

# iOSは通知の2行目にアプリ名（from Emo日記）を自動で入れるので、
# タイトルにアプリ名を入れると重複する。ここは用件そのものを書く。
TITLE = "記録の時間です"
BODY = "いまの気分を記録しませんか？"


def init_firebase() -> firestore.Client:
    """サービスアカウントで Firebase を初期化する。"""
    if firebase_admin._apps:
        return firestore.client()

    raw = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS_JSON")
    if raw:
        cred = credentials.Certificate(json.loads(raw))
    elif os.environ.get("GOOGLE_APPLICATION_CREDENTIALS"):
        cred = credentials.ApplicationDefault()
    else:
        sys.exit(
            "認証情報がありません。GOOGLE_APPLICATION_CREDENTIALS_JSON に "
            "サービスアカウントの秘密鍵JSONを設定してください。"
        )

    firebase_admin.initialize_app(cred)
    return firestore.client()


def fetch_targets(db: firestore.Client) -> list[tuple[str, str]]:
    """(ユーザー名, トークン) の一覧を返す。

    users/{username}/tokens/{token} をコレクショングループで横断的に読む。
    Admin SDK はセキュリティルールを介さないので、users の一覧が
    取れなくてもトークンだけまとめて取得できる。
    """
    targets: list[tuple[str, str]] = []
    for doc in db.collection_group("tokens").stream():
        # 親の親が users/{username} のドキュメント。
        user_ref = doc.reference.parent.parent
        if user_ref is None:
            continue
        targets.append((user_ref.id, doc.id))
    return targets


def build_message(username: str, token: str) -> messaging.Message:
    """1件ぶんの通知を組み立てる。タップで本人のURLを開く。"""
    return messaging.Message(
        token=token,
        webpush=messaging.WebpushConfig(
            notification=messaging.WebpushNotification(
                title=TITLE,
                body=BODY,
                icon="/icons/Icon-192.png",
            ),
            fcm_options=messaging.WebpushFCMOptions(
                link=f"{APP_URL}?u={username}",
            ),
        ),
    )


def slot_id(now: datetime) -> str:
    """その時間帯を表すID（例 "2026-08-11-14"）。1時間に1個しかない。"""
    return f"{now:%Y-%m-%d-%H}"


def claim_slot(db: firestore.Client, now: datetime) -> bool:
    """この時間帯の送信権を取れたら True。すでに送っていれば False。

    create は同じIDが在ると必ず失敗するので、複数の実行が重なっても
    通るのは1つだけになる（あとから読んで判定すると競合しうる）。
    """
    doc = db.collection("reminders").document(slot_id(now))
    try:
        doc.create({"sentAt": firestore.SERVER_TIMESTAMP})
        return True
    except google_exceptions.AlreadyExists:
        return False


def delete_token(db: firestore.Client, username: str, token: str) -> None:
    """無効になったトークンを消す（端末を替えた・通知を切った場合など）。"""
    db.collection("users").document(username).collection("tokens").document(
        token
    ).delete()


def main() -> int:
    parser = argparse.ArgumentParser(description="感情記録のリマインダーを送る")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="送信せず、対象のユーザーとトークン数だけ表示する",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="時間帯の判定を無視して送る（手動での動作確認用）",
    )
    args = parser.parse_args()

    now = datetime.now(JST)
    print(f"[INFO] 現在 {now:%Y-%m-%d %H:%M} JST")

    db = init_firebase()

    # 送信時間帯の外なら何もしない。
    # cron が大きく遅れて次の時間帯に食い込んだ回を、ここで落とす。
    if not args.force and not (SEND_HOUR_FIRST <= now.hour <= SEND_HOUR_LAST):
        print(
            f"[INFO] {SEND_HOUR_FIRST}時〜{SEND_HOUR_LAST}時台の外なので送りません"
        )
        return 0

    targets = fetch_targets(db)

    if not targets:
        print("[INFO] 送信対象がありません（通知を許可した端末がまだ無い）")
        return 0

    users = sorted({u for u, _ in targets})
    print(f"[INFO] 対象 {len(targets)} 件 / ユーザー {len(users)} 人: {', '.join(users)}")

    if args.dry_run:
        print("[INFO] --dry-run のため送信しません")
        return 0

    # 送信権の確保は実際に送る直前に行う。ここで取ってしまうと、
    # このあと落ちたときにその時間帯が「送信済み」のまま残ってしまう。
    if not args.force and not claim_slot(db, now):
        print(f"[INFO] {now.hour}時台はすでに送信済みなので送りません")
        return 0

    sent = 0
    stale = 0
    for username, token in targets:
        try:
            messaging.send(build_message(username, token))
            sent += 1
        except messaging.UnregisteredError:
            # 端末側で通知を切った・アプリを消した等。残しておくと毎回失敗するので消す。
            delete_token(db, username, token)
            stale += 1
            print(f"[INFO] 無効なトークンを削除: {username}")
        except Exception as e:  # noqa: BLE001 - 1件の失敗で全体を止めない
            print(f"[WARN] 送信に失敗 ({username}): {e}")

    print(f"[OK] 送信 {sent} 件 / 無効削除 {stale} 件")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
