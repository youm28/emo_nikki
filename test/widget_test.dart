// Step 1 のスモークテスト: 絵文字グリッドが12タイル表示されることを確認する。

import 'package:flutter_test/flutter_test.dart';

import 'package:emo_nikki/main.dart';

void main() {
  testWidgets('12個の絵文字タイルがグリッドに表示される', (WidgetTester tester) async {
    await tester.pumpWidget(const EmoNikkiApp());

    // 固定データが12件あること。
    expect(kEmojiList.length, 12);

    // EmojiTile が12個レンダリングされること。
    expect(find.byType(EmojiTile), findsNWidgets(12));
  });
}
