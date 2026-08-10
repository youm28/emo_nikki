/// Web 向けの実装。Notification API を直接読む。
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// ブラウザの通知許可の状態を返す。
///
/// 返り値は Notification API の値そのままで `'default'`（まだ聞いていない）/
/// `'granted'` / `'denied'`。API が無い環境では `'unsupported'`。
///
/// iOS で Notification API が無いのは、ホーム画面に追加せずSafariのタブで
/// 開いている場合と、iOS 16.4 より前の端末の場合。
String browserNotificationPermission() {
  try {
    if (!globalContext.has('Notification')) return 'unsupported';
    final notification = globalContext.getProperty('Notification'.toJS);
    if (notification == null) return 'unsupported';
    final permission =
        (notification as JSObject).getProperty('permission'.toJS);
    if (permission == null) return 'unsupported';
    return (permission as JSString).toDart;
  } catch (_) {
    return 'unsupported';
  }
}

/// 通知の宛先(FCMトークン)を取得する。
///
/// index.html で定義した `emoGetPushToken` を呼ぶ。firebase_messaging
/// プラグインを使わないのは、iPhone上のWebでも「ネイティブiOSアプリ」と
/// 判定され、Webに実装の無い getAPNSToken を呼んで必ず失敗するため。
Future<String> getPushToken(String vapidKey) async {
  if (!globalContext.has('emoGetPushToken')) {
    throw StateError('通知用のスクリプトが読み込まれていません');
  }
  final promise = globalContext.callMethod<JSPromise<JSAny?>>(
    'emoGetPushToken'.toJS,
    vapidKey.toJS,
  );
  final token = await promise.toDart;
  if (token == null) return '';
  return (token as JSString).toDart;
}

/// 許可ダイアログを出して、その結果を返す。
///
/// **タップのハンドラから、await を挟まずに呼ぶこと。**
/// iOS Safari は「ユーザー操作から連続した呼び出し」でないと許可ダイアログを
/// 出さない。FirebaseMessaging.requestPermission() は内部で非同期処理を挟むため
/// この連続性が切れてしまい、ダイアログが出ないまま 'default' が返る。
/// そのためブラウザ標準の Notification.requestPermission() を直接呼ぶ。
Future<String> requestBrowserNotificationPermission() async {
  try {
    if (!globalContext.has('Notification')) return 'unsupported';
    final notification =
        globalContext.getProperty('Notification'.toJS) as JSObject?;
    if (notification == null) return 'unsupported';

    final result = notification.callMethod<JSAny?>('requestPermission'.toJS);
    if (result == null) {
      // 古い実装（コールバック形式）はPromiseを返さない。状態を読み直す。
      return browserNotificationPermission();
    }
    final permission = await (result as JSPromise<JSString>).toDart;
    return permission.toDart;
  } catch (_) {
    // 例外時も、実際の状態はプロパティから読める。
    return browserNotificationPermission();
  }
}
