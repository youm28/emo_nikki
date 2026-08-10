/// ブラウザの通知許可の状態を読むための入口。
///
/// Web では実装（`browser_push_web.dart`）が使われ、テストなど Web 以外の
/// 環境では常に 'unsupported' を返すスタブが使われる。
///
/// FirebaseMessaging.getNotificationSettings() を使わないのは、環境によって
/// 例外を投げ、その結果「通知が使えない」と誤判定してボタンを出せなくなる
/// ためである。ブラウザ標準の Notification.permission を直接読む。
library;

export 'browser_push_stub.dart'
    if (dart.library.js_interop) 'browser_push_web.dart';
