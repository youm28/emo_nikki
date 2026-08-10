// 日記（1日1件・保存ボタン方式・過去日も編集可）のテスト。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:emo_nikki/dashboard_page.dart';
import 'package:emo_nikki/diary.dart';
import 'package:emo_nikki/emoji.dart';
import 'package:emo_nikki/emotion_analysis.dart';

EmotionEntry entry(String time, double valence) => EmotionEntry(
      time: time,
      emoji: '😊',
      name: 'SmilingFaceWithSmilingEyes',
      valence: valence,
      arousal: 7.03,
    );

/// 日記カードを単体で描画する（Firestoreに触れずに見た目と活性を確かめる）。
Widget wrap({
  required TextEditingController controller,
  List<EmotionEntry> entries = const [],
  bool dirty = false,
  bool saving = false,
  DateTime? updatedAt,
  VoidCallback? onSave,
}) =>
    MaterialApp(
      home: Scaffold(
        body: DiaryCard(
          controller: controller,
          entries: entries,
          dirty: dirty,
          saving: saving,
          updatedAt: updatedAt,
          onSave: onSave ?? () {},
        ),
      ),
    );

void main() {
  group('保存先の決まり方', () {
    test('ドキュメントIDは yyyy-MM-dd（/ は使えないのでハイフン）', () {
      expect(diaryDocId(DateTime(2026, 8, 10)), '2026-08-10');
      expect(diaryDocId(DateTime(2026, 12, 3)), '2026-12-03');
    });

    test('同じ日は常に同じIDになる＝1日1件が構造的に保証される', () {
      expect(
        diaryDocId(DateTime(2026, 8, 10, 9, 0)),
        diaryDocId(DateTime(2026, 8, 10, 23, 59)),
      );
    });

    test('day フィールドは感情記録と同じ表記のまま', () {
      // 照合や分析で emotions と突き合わせられるようにするため。
      expect(formatDay(DateTime(2026, 8, 10)), '2026/08/10');
    });
  });

  group('DiaryEntry.fromMap', () {
    test('text と day を読む。updatedAt は変換済みのものを受け取る', () {
      final at = DateTime(2026, 8, 10, 21, 14);
      final d = DiaryEntry.fromMap(
        {'day': '2026/08/10', 'text': '今日は…'},
        updatedAt: at,
      );
      expect(d.day, '2026/08/10');
      expect(d.text, '今日は…');
      expect(d.updatedAt, at);
    });

    test('フィールドが欠けていても空文字として読める', () {
      final d = DiaryEntry.fromMap({});
      expect(d.text, '');
      expect(d.day, '');
      expect(d.updatedAt, isNull);
    });
  });

  test('最終更新は HH:mm 表示', () {
    expect(formatUpdatedAt(DateTime(2026, 8, 10, 21, 14)), '21:14');
    expect(formatUpdatedAt(DateTime(2026, 8, 10, 9, 5)), '09:05');
  });

  group('日記カード', () {
    testWidgets('未記入のときは保存ボタンが押せない', (WidgetTester tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(wrap(controller: controller));
      await tester.pumpAndSettle();

      expect(find.text('まだ書かれていません'), findsOneWidget);
      expect(find.text('0 文字'), findsOneWidget);
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('未保存の変更があるときだけ保存できる', (WidgetTester tester) async {
      final controller = TextEditingController(text: '書きかけの日記');
      addTearDown(controller.dispose);
      var saved = false;

      await tester.pumpWidget(wrap(
        controller: controller,
        dirty: true,
        onSave: () => saved = true,
      ));
      await tester.pumpAndSettle();

      expect(find.text('未保存の変更があります'), findsOneWidget);
      expect(find.text('7 文字'), findsOneWidget);

      await tester.tap(find.byType(FilledButton));
      expect(saved, isTrue);
    });

    testWidgets('保存済みなら最終更新が出て、ボタンは押せない',
        (WidgetTester tester) async {
      final controller = TextEditingController(text: '保存済みの日記');
      addTearDown(controller.dispose);

      await tester.pumpWidget(wrap(
        controller: controller,
        updatedAt: DateTime(2026, 8, 10, 21, 14),
      ));
      await tester.pumpAndSettle();

      expect(find.text('最終更新 21:14'), findsOneWidget);
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('保存中は二重に押せない', (WidgetTester tester) async {
      final controller = TextEditingController(text: 'あ');
      addTearDown(controller.dispose);

      await tester.pumpWidget(wrap(
        controller: controller,
        dirty: true,
        saving: true,
      ));
      await tester.pump();

      expect(find.text('保存中…'), findsOneWidget);
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('その日の絵文字がカードに並ぶ（書きながら起伏を思い出せる）',
        (WidgetTester tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(wrap(
        controller: controller,
        entries: [entry('11:00', 7.75), entry('15:00', 3.02)],
      ));
      await tester.pumpAndSettle();

      expect(find.byType(EmojiImage), findsNWidgets(2));
    });

    testWidgets('絵文字は文字数に数えない（サロゲートペア対応）',
        (WidgetTester tester) async {
      final controller = TextEditingController(text: '😊あ');
      addTearDown(controller.dispose);

      await tester.pumpWidget(wrap(controller: controller));
      await tester.pumpAndSettle();

      // characters で数えるので絵文字1つ＋あ = 2文字。
      expect(find.text('2 文字'), findsOneWidget);
    });
  });
}
