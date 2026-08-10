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

  test('登録後にアドレスバーへ反映する相対URL', () {
    expect(personalRoute('p01'), '/?u=p01');
    expect(personalRoute('太郎'), '/?u=%E5%A4%AA%E9%83%8E');
  });

  testWidgets('名前ダイアログは表示専用で、名前を変更できない',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'username': 'taro'});
    await tester.pumpWidget(const EmoNikkiApp());
    await tester.pumpAndSettle();

    expect(find.text('今の気分は？（taro）'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.manage_accounts));
    await tester.pumpAndSettle();

    // 名前は読めるが、編集欄も変更ボタンも無い。
    expect(find.text('taro'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('変更'), findsNothing);
    // 復帰用リンクはコピーできる。
    expect(find.text('リンクをコピー'), findsOneWidget);
  });

  testWidgets('登録画面は「変更できない」ことを伝え、登録するとグリッドへ進む',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const EmoNikkiApp());
    await tester.pumpAndSettle();

    expect(find.text('登録 / ログイン'), findsOneWidget);
    expect(
      find.textContaining('お名前はあとから変更できません'),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField), 'p01');
    await tester.tap(find.text('はじめる'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('このお名前ではじめる'));
    await tester.pumpAndSettle();

    expect(find.text('今の気分は？（p01）'), findsOneWidget);

    // 次回以降そのまま使えるよう保存されている。
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('username'), 'p01');
  });

  testWidgets('確認画面で「入力しなおす」を選ぶと登録されない',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const EmoNikkiApp());
    await tester.pumpAndSettle();

    // オートフィルや打ち間違いに気づけるよう、確認画面に名前を出す。
    await tester.enterText(find.byType(TextField), '山田太郎');
    await tester.tap(find.text('はじめる'));
    await tester.pumpAndSettle();
    expect(find.text('山田太郎'), findsWidgets);

    await tester.tap(find.text('入力しなおす'));
    await tester.pumpAndSettle();

    // 登録画面のまま。保存もされていない。
    expect(find.text('登録 / ログイン'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('username'), isNull);
  });

  testWidgets('同じ名前を入れ直せば元の記録に戻れる（ログインとして機能する）',
      (WidgetTester tester) async {
    // 端末のデータが消えた状態を再現する。
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const EmoNikkiApp());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'p01');
    await tester.tap(find.text('はじめる'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('このお名前ではじめる'));
    await tester.pumpAndSettle();

    // 記録先は名前で決まるので、同じ名前＝同じ記録に戻る。
    expect(find.text('今の気分は？（p01）'), findsOneWidget);
  });
}
