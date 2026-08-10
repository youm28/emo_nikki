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

  group('通知の案内カード', () {
    testWidgets('時間帯を伝え、オンにするボタンが押せる', (WidgetTester tester) async {
      var tapped = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PushPrompt(busy: false, onEnable: () => tapped = true),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('10時〜19時'), findsOneWidget);

      await tester.tap(find.text('オンにする'));
      expect(tapped, isTrue);
    });

    testWidgets('処理中は二重に押せない', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: PushPrompt(busy: true, onEnable: () {})),
      ));
      await tester.pump();

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });
  });
}
