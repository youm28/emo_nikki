"""感情記録のリマインダーを FCM で送るスクリプト。

Web アプリ自身は「毎時0分に鳴らす」予約ができないため、外部から定時に
このスクリプトを実行して通知を送る。

送るのは2種類:
    - 10:00〜19:00 の毎時: 感情の記録（元研究 Emoji_watch に合わせた時間帯）
    - 21:00: その日を振り返る日記（タップでダッシュボードの日記欄が開く）
どちらを送るかは実行時刻で決まるので、呼び出し側は毎時実行するだけでよい。

呼び出し元:
    本番は大学のミニPC上の systemd タイマー (emo-reminder.timer)。
    毎時0分ちょうどに実行する。
    .github/workflows/reminders.yml は手動実行のみ残してあり、
    ミニPCが止まったときの応急手段として使う。
    （GitHub の定時実行は実測で7回中3回が実行されず、動いた回も最大55分
      遅れていたため外した。時刻の正確さが要る用途には向かない）

**1時間に何度呼ばれても、送るのは1回だけ**である点に注意。
複数の呼び出し元を並走させても二重送信にならないようにしてある。

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
    python tools/send_reminders.py --force --kind diary  # 日記の通知を今すぐ試す
"""

import argparse
import json
import os
import socket
import sys
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from urllib.parse import urlencode

import firebase_admin
from firebase_admin import credentials, firestore, messaging
from google.api_core import exceptions as google_exceptions

JST = timezone(timedelta(hours=9))

# 通知をタップしたときに開くURL。?u=<ユーザー名> を付けて本人の画面に入れる。
APP_URL = "https://emo-nikki-eyuma1218-4155e.web.app/"


@dataclass(frozen=True)
class Reminder:
    """1種類の通知。kind は reminders に残す種別名。

    iOSは通知の2行目にアプリ名（from Emo日記）を自動で入れるので、
    タイトルにアプリ名を入れると重複する。タイトルは用件そのものを書く。
    """

    kind: str
    title: str
    body: str
    # タップしたときに開く画面。None なら記録画面（アプリの最初の画面）。
    open: str | None = None


# 10〜19時の毎時：感情の記録（元研究 Emoji_watch に合わせた時間帯）。
RECORD = Reminder(
    kind="record",
    title="記録の時間です",
    body="いまの気分を記録しませんか？",
)
# 21時：その日の振り返り日記。記録の最終回(19時台)のあと、寝る前に書けるように。
# タップするとダッシュボードの日記欄が開く（アプリ側で ?open=diary を見る）。
DIARY = Reminder(
    kind="diary",
    title="日記の時間です",
    body="今日一日をふりかえって、日記を書きませんか？",
    open="diary",
)
REMINDERS = {r.kind: r for r in (RECORD, DIARY)}

RECORD_HOUR_FIRST = 10
RECORD_HOUR_LAST = 19
DIARY_HOUR = 21


def reminder_for_hour(hour: int) -> Reminder | None:
    """その時刻(JST)に送る通知。送らない時間帯なら None。"""
    if RECORD_HOUR_FIRST <= hour <= RECORD_HOUR_LAST:
        return RECORD
    if hour == DIARY_HOUR:
        return DIARY
    return None


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


def build_link(username: str, reminder: Reminder) -> str:
    """タップで開くURL。本人の ?u= に、開く画面の指定(open)を足す。"""
    params = {"u": username}
    if reminder.open:
        params["open"] = reminder.open
    return f"{APP_URL}?{urlencode(params)}"


def build_message(
    username: str, token: str, reminder: Reminder
) -> messaging.Message:
    """1件ぶんの通知を組み立てる。タップで本人のURLを開く。"""
    return messaging.Message(
        token=token,
        webpush=messaging.WebpushConfig(
            notification=messaging.WebpushNotification(
                title=reminder.title,
                body=reminder.body,
                icon="/icons/Icon-192.png",
            ),
            fcm_options=messaging.WebpushFCMOptions(
                link=build_link(username, reminder),
            ),
        ),
    )


def slot_id(now: datetime) -> str:
    """その時間帯を表すID（例 "2026-08-11-14"）。1時間に1個しかない。"""
    return f"{now:%Y-%m-%d-%H}"


def source_name() -> str:
    """どこから送ったかの名前。既定はホスト名。

    複数の呼び出し元を並走させられるので、どれが送ったかを実験ログとして
    残す。本番はミニPC (minipc)、応急手段の手動実行は github-actions。
    """
    return os.environ.get("REMINDER_SOURCE") or socket.gethostname()


def claim_slot(db: firestore.Client, now: datetime, reminder: Reminder) -> bool:
    """この時間帯の送信権を取れたら True。すでに送っていれば False。

    create は同じIDが在ると必ず失敗するので、複数の実行が重なっても
    通るのは1つだけになる（あとから読んで判定すると競合しうる）。
    """
    doc = db.collection("reminders").document(slot_id(now))
    try:
        doc.create(
            {
                "sentAt": firestore.SERVER_TIMESTAMP,
                # 予定時刻ちょうどに送れたのか、遅れて拾われたのかを見るため、
                # サーバー時刻とは別に送信側の時刻も残す。
                "localTime": now.strftime("%Y-%m-%d %H:%M:%S%z"),
                "source": source_name(),
                "kind": reminder.kind,
            }
        )
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
    parser.add_argument(
        "--kind",
        choices=sorted(REMINDERS),
        help="--force で送る通知の種類（省略時はその時刻の種類、無ければ record）",
    )
    args = parser.parse_args()

    now = datetime.now(JST)
    print(f"[INFO] 現在 {now:%Y-%m-%d %H:%M} JST / 送信元 {source_name()}")

    # 何を送るかは時刻で決まる。--force のときだけ --kind で選べる。
    # 送信時間帯の外なら何もしない（遅れて次の時間帯に食い込んだ回もここで落ちる）。
    if args.force:
        reminder = (
            REMINDERS[args.kind] if args.kind else reminder_for_hour(now.hour) or RECORD
        )
    else:
        reminder = reminder_for_hour(now.hour)
        if reminder is None:
            print(
                f"[INFO] 送信時間帯（{RECORD_HOUR_FIRST}〜{RECORD_HOUR_LAST}時台・"
                f"{DIARY_HOUR}時台）の外なので送りません"
            )
            return 0
    print(f"[INFO] 種類 {reminder.kind}「{reminder.title}」")

    db = init_firebase()

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
    if not args.force and not claim_slot(db, now, reminder):
        print(f"[INFO] {now.hour}時台はすでに送信済みなので送りません")
        return 0

    sent = 0
    stale = 0
    for username, token in targets:
        try:
            messaging.send(build_message(username, token, reminder))
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
