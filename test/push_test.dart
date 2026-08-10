// 通知（リマインダー）まわりのテスト。
// 許可状態の判定と、案内カードの出し分けを確かめる。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:emo_nikki/main.dart';
import 'package:emo_nikki/push.dart';

void main() {
  group('ブラウザの Notification.permission からの判定', () {
    test('default は「まだ聞いていない」＝ボタンを出す', () {
      expect(fromBrowserPermission('default'), PushPermission.notAsked);
    });

    test('granted / denied はそのまま対応する', () {
      expect(fromBrowserPermission('granted'), PushPermission.granted);
      expect(fromBrowserPermission('denied'), PushPermission.denied);
    });

    test('APIが無い環境や想定外の値は unsupported', () {
      expect(fromBrowserPermission('unsupported'), PushPermission.unsupported);
      expect(fromBrowserPermission(''), PushPermission.unsupported);
    });
  });

  group('有効化の結果', () {
    test('許可済みでエラー無しなら成功', () {
      const r = PushResult(PushPermission.granted);
      expect(r.ok, isTrue);
    });

    test('許可はされたが宛先の登録に失敗した場合は成功にしない', () {
      // ここを unsupported に丸めると「ホーム画面に追加して」と誤案内してしまう。
      const r = PushResult(PushPermission.granted, error: 'AbortError: ...');
      expect(r.ok, isFalse);
      expect(r.permission, PushPermission.granted);
      expect(r.error, isNotNull);
    });

    test('拒否された場合はエラー無しでも成功にしない', () {
      const r = PushResult(PushPermission.denied);
      expect(r.ok, isFalse);
    });
  });

  group('通知の案内カード', () {
    Widget wrap(PushPermission permission,
            {bool busy = false, VoidCallback? onEnable}) =>
        MaterialApp(
          home: Scaffold(
            body: PushPrompt(
              permission: permission,
              busy: busy,
              onEnable: onEnable ?? () {},
            ),
          ),
        );

    testWidgets('未許可なら時間帯を伝え、オンにするボタンが押せる',
        (WidgetTester tester) async {
      var tapped = false;
      await tester.pumpWidget(
          wrap(PushPermission.notAsked, onEnable: () => tapped = true));
      await tester.pumpAndSettle();

      expect(find.textContaining('10時〜19時'), findsOneWidget);
      await tester.tap(find.text('オンにする'));
      expect(tapped, isTrue);
    });

    testWidgets('拒否済みならブラウザ設定を案内し、ボタンは出さない',
        (WidgetTester tester) async {
      await tester.pumpWidget(wrap(PushPermission.denied));
      await tester.pumpAndSettle();

      expect(find.textContaining('ブロックされています'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('通知が使えない環境ではホーム画面への追加を案内する',
        (WidgetTester tester) async {
      // iOSでSafariのタブのまま開いた場合など。黙って消えると原因が分からない。
      await tester.pumpWidget(wrap(PushPermission.unsupported));
      await tester.pumpAndSettle();

      expect(find.textContaining('ホーム画面に追加'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('処理中は二重に押せない', (WidgetTester tester) async {
      await tester.pumpWidget(wrap(PushPermission.notAsked, busy: true));
      await tester.pump();

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });
  });
}
