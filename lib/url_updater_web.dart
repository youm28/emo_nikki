/// Web 向けの実装。History API でアドレスバーだけを差し替える。
library;

import 'package:web/web.dart' as web;

/// 履歴を増やさずに現在のURLを [route] に差し替える。
///
/// `pushState` ではなく `replaceState` を使うのは、戻るボタンを押したときに
/// 登録前のURLへ戻ってしまわないようにするため。ページの再読み込みは起きない。
void replaceUrl(String route) {
  web.window.history.replaceState(null, '', route);
}
