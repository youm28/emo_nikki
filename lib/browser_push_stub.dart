/// Web 以外（テストなど）向けのスタブ。通知は扱えない。
library;

/// ブラウザの通知許可の状態。Web以外では常に 'unsupported'。
String browserNotificationPermission() => 'unsupported';
