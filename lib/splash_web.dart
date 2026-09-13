/// Web 向けの実装。index.html に置いた起動中の表示を取り除く。
library;

import 'package:web/web.dart' as web;

/// 起動中の表示を消す。アプリの最初の画面が描かれたあとに呼ぶ。
///
/// 先に消すと、アプリが描かれるまでの間に何も無い画面が一瞬出てしまう。
void removeSplash() {
  web.document.getElementById('splash')?.remove();
}
