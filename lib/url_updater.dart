/// アドレスバーのURLを書き換えるための入口。
///
/// Web では実装（`url_updater_web.dart`）が使われ、テストなど Web 以外の環境では
/// 何もしないスタブ（`url_updater_stub.dart`）が使われる。
///
/// `SystemNavigator.routeInformationUpdated` は Router を使うアプリでないと
/// アドレスバーに反映されないため、History API を直接呼んでいる。
library;

export 'url_updater_stub.dart'
    if (dart.library.js_interop) 'url_updater_web.dart';
