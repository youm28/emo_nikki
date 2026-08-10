// 通知（リマインダー）まわりのテスト。
// 許可状態の判定と、案内カードの出し分けを確かめる。

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:emo_nikki/main.dart';
import 'package:emo_nikki/push.dart';

void main() {
  group('許可状態の変換', () {
    test('authorized / provisional は「許可済み」', () {
      expect(toPushPermission(AuthorizationStatus.authorized),
          PushPermission.granted);
      // iOSの暫定許可も、通知は届くので許可済みとして扱う。
      expect(toPushPermission(AuthorizationStatus.provisional),
          PushPermission.granted);
    });

    test('notDetermined は「まだ聞いていない」＝案内を出す', () {
      expect(toPushPermission(AuthorizationStatus.notDetermined),
          PushPermission.notAsked);
    });

    test('denied は「拒否」＝案内を出さない（ブラウザ設定から戻す必要がある）', () {
      expect(
          toPushPermission(AuthorizationStatus.denied), PushPermission.denied);
    });
  });

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
