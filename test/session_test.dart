// ユーザー名の保持（?u= リンクからの復帰・名前の変更）のテスト。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:emo_nikki/main.dart';

void main() {
  group('URLからの名前の取り出し', () {
    test('?u= があれば取り出し、前後の空白は落とす', () {
      expect(usernameFromUrl(Uri.parse('https://x.app/?u=taro')), 'taro');
      expect(usernameFromUrl(Uri.parse('https://x.app/?u=%20taro%20')), 'taro');
    });

    test('?u= が無い・空なら null', () {
      expect(usernameFromUrl(Uri.parse('https://x.app/')), isNull);
      expect(usernameFromUrl(Uri.parse('https://x.app/?u=')), isNull);
      expect(usernameFromUrl(Uri.parse('https://x.app/?t=abc')), isNull);
    });
  });

  group('使う名前の決定', () {
    test('保存が空でもリンクの名前で始められる（新しい端末・復帰リンク）', () {
      final r = resolveUsername(fromUrl: 'taro', saved: null, lastUrl: null);
      expect(r.username, 'taro');
      expect(r.persistUrlName, isTrue);
    });

    test('前回と同じリンクなら、画面で変更した名前を優先する', () {
      final r =
          resolveUsername(fromUrl: 'taro', saved: 'hanako', lastUrl: 'taro');
      expect(r.username, 'hanako');
      expect(r.persistUrlName, isFalse);
    });

    test('別のリンクで開いたらそちらに切り替わる', () {
      final r =
          resolveUsername(fromUrl: 'jiro', saved: 'hanako', lastUrl: 'taro');
      expect(r.username, 'jiro');
      expect(r.persistUrlName, isTrue);
    });

    test('リンクが無ければ保存済みの名前を使う', () {
      final r = resolveUsername(fromUrl: null, saved: 'hanako', lastUrl: 'taro');
      expect(r.username, 'hanako');
      expect(r.persistUrlName, isFalse);
    });

    test('どこにも無ければ null（名前入力画面に出る）', () {
      final r = resolveUsername(fromUrl: null, saved: null, lastUrl: null);
      expect(r.username, isNull);
    });
  });

  test('個人用リンクは ?u=名前 付きになる（既存のクエリは置き換える）', () {
    expect(
      buildPersonalLink(Uri.parse('https://x.web.app/'), 'taro'),
      'https://x.web.app/?u=taro',
    );
    expect(
      buildPersonalLink(Uri.parse('https://x.web.app/?u=old'), 'hanako'),
      'https://x.web.app/?u=hanako',
    );
    // 日本語名もURLエンコードされる。
    expect(
      buildPersonalLink(Uri.parse('https://x.web.app/'), '太郎'),
      contains('?u=%E5%A4%AA%E9%83%8E'),
    );
  });

  testWidgets('名前ダイアログは現在の名前が入った状態で開き、変更すると切り替わる',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'username': 'taro'});
    await tester.pumpWidget(const EmoNikkiApp());
    await tester.pumpAndSettle();

    expect(find.text('今の気分は？（taro）'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.manage_accounts));
    await tester.pumpAndSettle();

    // 現在の名前が最初から入っている（＝何と入力したか確認できる）。
    expect(find.widgetWithText(TextField, 'taro'), findsOneWidget);
    expect(find.text('リンクをコピー'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'hanako');
    await tester.tap(find.text('変更'));
    await tester.pumpAndSettle();

    expect(find.text('今の気分は？（hanako）'), findsOneWidget);

    // 保存もされている（リロードしても hanako のまま）。
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('username'), 'hanako');
  });

  testWidgets('名前を空にして変更は押せない（そのまま維持される）',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'username': 'taro'});
    await tester.pumpWidget(const EmoNikkiApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.manage_accounts));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('変更'));
    await tester.pumpAndSettle();

    // ダイアログは閉じず、名前も変わらない。
    expect(find.text('名前とリンク'), findsOneWidget);
  });
}
