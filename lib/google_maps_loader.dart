/// Google マップ（Maps JavaScript API）を必要になったときだけ読み込む入口。
///
/// index.html に最初から書くと、地図を使わない参加者も含めて全員が毎回
/// 約300KBを余分にダウンロードすることになる。そこで開発用ダッシュボードで
/// Google の地図を選んだときにだけ読み込む。
///
/// Web では実装（`google_maps_loader_web.dart`）、テストなど Web 以外では
/// 何もできないスタブ（`google_maps_loader_stub.dart`）が使われる。
library;

export 'google_maps_loader_stub.dart'
    if (dart.library.js_interop) 'google_maps_loader_web.dart';
