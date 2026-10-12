// 記録時の一言メモのテスト。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:emo_nikki/emotion_analysis.dart';
import 'package:emo_nikki/main.dart';

void main() {
  const item = EmojiItem(
    emoji: '😊',
    name: 'SmilingFaceWithSmilingEyes',
    valence: 7.75,
    arousal: 7.03,
  );

  group('保存する記録', () {
    test('メモを書くと memo に入る', () {
      final rec = buildEmotionRecord(
        item,
        now: DateTime(2026, 9, 28, 14, 30),
        memo: '会議が長引いた',
      );
      expect(rec['memo'], '会議が長引いた');
    });

    test('未入力なら memo は null（空文字では入れない）', () {
      // 空文字で入れると「メモを書かなかった記録」と「空で保存した記録」を
      // あとで区別できなくなる。
      expect(buildEmotionRecord(item, now: DateTime(2026, 9, 28))['memo'], isNull);
      expect(
        buildEmotionRecord(item, now: DateTime(2026, 9, 28), memo: '')['memo'],
        isNull,
      );
    });
  });

  group('EmotionEntry.fromMap', () {
    final base = {
      'time': '14:30',
      'emoji': '😊',
      'name': 'SmilingFaceWithSmilingEyes',
      'valence': 7.75,
      'arousal': 7.03,
    };

    test('メモを読む', () {
      expect(EmotionEntry.fromMap({...base, 'memo': '会議が長引いた'})!.memo, '会議が長引いた');
    });

    test('メモを追加する前の古い記録も読める（memo は null）', () {
      expect(EmotionEntry.fromMap(base)!.memo, isNull);
      expect(EmotionEntry.fromMap({...base, 'memo': null})!.memo, isNull);
      expect(EmotionEntry.fromMap({...base, 'memo': ''})!.memo, isNull);
    });
  });

  group('確認画面', () {
    testWidgets('一言メモの欄が出る。キーボードは勝手に開かない',
        (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({'username': 'taro'});
      await tester.pumpWidget(const EmoNikkiApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byType(EmojiTile).first);
      await tester.pumpAndSettle();

      expect(find.text('一言メモ（任意）'), findsOneWidget);
      // 記録は「絵文字→記録」の2タップで終えられる速さが大事なので、
      // 勝手にキーボードを出して流れを止めない。
      expect(tester.testTextInput.isVisible, isFalse);

      // 書いた内容はそのまま入る。
      await tester.enterText(find.byType(TextField), '会議が長引いた');
      await tester.pump();
      expect(find.text('会議が長引いた'), findsOneWidget);
    });
  });
}
