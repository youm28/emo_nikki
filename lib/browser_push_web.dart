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
