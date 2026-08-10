/// 通知（リマインダー）まわり。
///
/// Web では「アプリ自身が毎時0分に鳴らす」ことができないため、送信は
/// サーバー側（GitHub Actions から動かす tools/send_reminders.py）が行う。
/// アプリ側の役目は、許可をもらって端末のトークンを Firestore に置くことだけ。
///
/// iOS では**ホーム画面に追加した状態でのみ**通知を受け取れる（iOS 16.4 以降）。
/// Safari のタブで開いたままだと許可を求めることもできない。
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'browser_push.dart';

/// 端末トークンの保存先（`users/{username}/tokens/{token}`）。
///
/// トークン自体をドキュメントIDにしているので、同じ端末から何度呼んでも
/// 増えずに1件が更新される。
const String kTokensCollection = 'tokens';

/// Web Push 証明書（VAPID公開鍵）。
///
/// Firebase コンソール → プロジェクトの設定 → Cloud Messaging →
/// 「ウェブプッシュ証明書」で鍵ペアを生成し、その公開鍵をここに貼る。
/// 空のままでも Firebase SDK の既定鍵で動くが、自前の鍵を使うのが推奨。
const String kVapidKey = 'BMkJGT5DY9diLsPfyz2izKLoujpWaVRMO0UiNE6zJiuoqv7aIUqoNUPZak1GptBxawIJc7b3pGzTTqA3R-3gCj8';

/// 通知の許可状態。UIの出し分けに使う。
enum PushPermission {
  /// まだ許可も拒否もしていない（「オンにする」を出す）
  notAsked,

  /// 許可済み（案内は出さない）
  granted,

  /// 拒否された（ブラウザの設定から戻す必要がある）
  denied,

  /// この環境では通知が使えない（iOSのタブ表示など）
  unsupported,
}

/// FirebaseMessaging の状態を、UIが扱いやすい [PushPermission] に変換する。
/// ロジックを純粋関数に切り出してテストできるようにしている。
PushPermission toPushPermission(AuthorizationStatus status) {
  return switch (status) {
    AuthorizationStatus.authorized ||
    AuthorizationStatus.provisional =>
      PushPermission.granted,
    AuthorizationStatus.denied => PushPermission.denied,
    AuthorizationStatus.notDetermined => PushPermission.notAsked,
  };
}

/// Notification API の値（`'default'`/`'granted'`/`'denied'`）を
/// UIが扱う [PushPermission] に変換する。
PushPermission fromBrowserPermission(String permission) {
  return switch (permission) {
    'granted' => PushPermission.granted,
    'denied' => PushPermission.denied,
    'default' => PushPermission.notAsked,
    _ => PushPermission.unsupported,
  };
}

/// いまの許可状態を返す（ダイアログは出さない）。
///
/// FirebaseMessaging ではなくブラウザの Notification API を直接読む。
/// プラグイン側は「非対応環境」と判断すると例外を投げることがあり、
/// それを拾うと通知を使える端末でもボタンを出せなくなるため。
Future<PushPermission> currentPushPermission() async {
  if (!kIsWeb) return PushPermission.unsupported;
  return fromBrowserPermission(browserNotificationPermission());
}

/// 通知を有効にした結果。
///
/// 許可の状態と、宛先(トークン)の登録に失敗した理由を分けて持つ。
/// 「許可はされたがトークンが取れなかった」を unsupported に丸めてしまうと、
/// ホーム画面に追加済みの人に「追加してください」と出て混乱するため。
class PushResult {
  final PushPermission permission;

  /// トークン登録に失敗したときの理由（原因調査のためそのまま表示する）。
  final String? error;

  const PushResult(this.permission, {this.error});

  bool get ok => permission == PushPermission.granted && error == null;
}

/// 許可を求めてトークンを保存する。
///
/// 必ずボタンなどのユーザー操作から呼ぶこと（そうでないとブラウザが
/// 許可ダイアログを出さない）。
Future<PushResult> enablePush(String username) async {
  if (!kIsWeb) return const PushResult(PushPermission.unsupported);

  // 許可ダイアログを出す。ここが失敗しても、実際の状態はブラウザから読めるので
  // 例外は握りつぶして次に進む。
  try {
    await FirebaseMessaging.instance.requestPermission();
  } catch (e) {
    debugPrint('許可要求で例外（状態はブラウザから読み直す）: $e');
  }

  final permission = fromBrowserPermission(browserNotificationPermission());
  if (permission != PushPermission.granted) {
    return PushResult(permission);
  }

  // ここから先は「許可されている」ことが確定している。
  try {
    final token = await FirebaseMessaging.instance.getToken(
      vapidKey: kVapidKey.isEmpty ? null : kVapidKey,
    );
    if (token == null || token.isEmpty) {
      return PushResult(permission, error: '宛先(トークン)が空で返りました');
    }
    await saveToken(username: username, token: token);
    return PushResult(permission);
  } catch (e) {
    debugPrint('トークンの取得・保存に失敗: $e');
    return PushResult(permission, error: '$e');
  }
}

/// すでに許可済みのとき、いまのユーザー名でトークンを登録し直す。
///
/// ブラウザの通知許可は**サイト単位**で、ユーザー名とは無関係に残る。
/// そのため同じ端末で別のIDを開くと「許可済みなので案内を出さない」状態のまま
/// そのIDの宛先が登録されず、通知が届かなくなる。それを防ぐため、
/// 許可済みなら画面を開いたときに黙って登録し直す（ダイアログは出ない）。
Future<void> registerTokenIfGranted(String username) async {
  if (!kIsWeb) return;
  try {
    final token = await FirebaseMessaging.instance.getToken(
      vapidKey: kVapidKey.isEmpty ? null : kVapidKey,
    );
    if (token == null || token.isEmpty) return;
    await saveToken(username: username, token: token);
  } catch (e) {
    debugPrint('トークンの再登録に失敗（通知以外の動作には影響なし）: $e');
  }
}

/// トークンを Firestore に保存する。
/// トークンがそのままドキュメントIDなので、再実行しても重複しない。
Future<void> saveToken({
  required String username,
  required String token,
}) async {
  await FirebaseFirestore.instance
      .collection('users')
      .doc(username)
      .collection(kTokensCollection)
      .doc(token)
      .set({
    'token': token,
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}
