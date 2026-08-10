/// Web 以外（テストなど）向けのスタブ。通知は扱えない。
library;

/// ブラウザの通知許可の状態。Web以外では常に 'unsupported'。
String browserNotificationPermission() => 'unsupported';

/// 許可ダイアログ。Web以外では出せない。
Future<String> requestBrowserNotificationPermission() async => 'unsupported';

/// 通知の宛先。Web以外では取得できない。
Future<String> getPushToken(String vapidKey) async => '';
