/// 起動中の表示（web/index.html の #splash）を消すための入口。
///
/// Web では実装（`splash_web.dart`）が使われ、テストなど Web 以外の環境では
/// 何もしないスタブ（`splash_stub.dart`）が使われる。
library;

export 'splash_stub.dart' if (dart.library.js_interop) 'splash_web.dart';
