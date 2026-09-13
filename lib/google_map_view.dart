/// Google マップで記録を表示する部品の入口。
///
/// google_maps_flutter パッケージは使わない。あのパッケージはアプリの起動時に
/// 必ず登録される仕組みで、地図を使わない参加者のアプリ本体まで約115KB
/// （圧縮後）大きくしてしまったため。代わりに Google の地図プログラム
/// （Maps JavaScript API）を開発用ダッシュボードの中から直接呼ぶ。
///
/// Web では実装（`google_map_view_web.dart`）、テストなど Web 以外では
/// 説明だけを出すスタブ（`google_map_view_stub.dart`）が使われる。
library;

export 'google_map_view_stub.dart'
    if (dart.library.js_interop) 'google_map_view_web.dart';

/// 地図に置く記録1件。
class GoogleMapPin {
  final double lat;
  final double lng;
  final String time; // マーカーを押したときに出す
  final String iconAsset; // 絵文字の画像（assets/emoji_list/…png）

  const GoogleMapPin({
    required this.lat,
    required this.lng,
    required this.time,
    required this.iconAsset,
  });
}
