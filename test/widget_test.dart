// Step 1/2 のスモークテスト。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:emo_nikki/main.dart';

void main() {
  test('固定の絵文字データは12件', () {
    expect(kEmojiList.length, 12);
  });

  testWidgets('名前未設定なら名前入力画面が出る', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({}); // 未設定状態
    await tester.pumpWidget(const EmoNikkiApp());
    await tester.pumpAndSettle();

    expect(find.text('登録'), findsOneWidget);
    expect(find.byType(EmojiGridPage), findsNothing);
  });

  testWidgets('名前設定済みならグリッド(12タイル)が出る', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'username': 'taro'});
    await tester.pumpWidget(const EmoNikkiApp());
    await tester.pumpAndSettle();

    expect(find.byType(EmojiTile), findsNWidgets(12));
  });

  testWidgets('名前を入力して登録するとグリッドに進む', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const EmoNikkiApp());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'hanako');
    await tester.tap(find.text('登録'));
    await tester.pumpAndSettle();

    expect(find.byType(EmojiTile), findsNWidgets(12));
  });
}
