// 明日の予定（感情と行動の推移）のテスト。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:emo_nikki/emoji.dart';
import 'package:emo_nikki/emotion_analysis.dart';
import 'package:emo_nikki/plan.dart';
import 'package:emo_nikki/plan_card.dart';

EmotionEntry entry(String time, double valence) => EmotionEntry(
      time: time,
      emoji: '😊',
      name: 'SmilingFaceWithSmilingEyes',
      valence: valence,
      arousal: 7.03,
    );

void main() {
  group('描いた高さを絵文字に対応させる', () {
    test('一番近い valence の絵文字になる', () {
      expect(emojiForValence(2.88).name, 'AnxiousFaceWithSweat'); // 最小
      expect(emojiForValence(7.83).name, 'BeamingFaceWithSmilingEyes'); // 最大
      expect(emojiForValence(5.2).name, 'FaceWithOpenMouth'); // 5.18 が最も近い
    });

    test('範囲の外を描いても端の絵文字になる', () {
      expect(emojiForValence(0).name, 'AnxiousFaceWithSweat');
      expect(emojiForValence(10).name, 'BeamingFaceWithSmilingEyes');
    });
  });

  group('指の位置から時刻と気分を決める', () {
    test('左端が10時、右端が20時、中央が15時', () {
      expect(planHourFromX(0, 300), 10);
      expect(planHourFromX(300, 300), 20);
      expect(planHourFromX(150, 300), 15);
    });

    test('はみ出しても両端に寄せる（指が外れても描ける）', () {
      expect(planHourFromX(-50, 300), 10);
      expect(planHourFromX(999, 300), 20);
    });

    test('上が8・下が2。外にはみ出す分は切り詰める', () {
      expect(planValenceFromY(0, 100), 8);
      expect(planValenceFromY(100, 100), 2);
      expect(planValenceFromY(50, 100), 5);
      expect(planValenceFromY(-30, 100), 8);
      expect(planValenceFromY(130, 100), 2);
    });
  });

  group('点の付け外し', () {
    test('同じ時刻は1つだけになり、時刻順に並ぶ', () {
      var points = setPlanPoint(const [], 15, 7);
      points = setPlanPoint(points, 11, 3);
      points = setPlanPoint(points, 15, 4); // 15時を描き直す
      expect(points.map((p) => p.hour), [11, 15]);
      expect(points.last.valence, 4);
    });

    test('描き直しても、その時刻の行動は残る', () {
      var points = setPlanPoint(const [], 12, 6);
      points = setPlanActivity(points, 12, 'sara');
      points = setPlanPoint(points, 12, 3);
      expect(points.single.activity, 'sara');
      expect(points.single.valence, 3);
    });

    test('行動は外せる', () {
      var points = setPlanActivity(setPlanPoint(const [], 12, 6), 12, 'sara');
      points = setPlanActivity(points, 12, null);
      expect(points.single.activity, isNull);
    });
  });

  group('保存と読み込み', () {
    test('書いて読み戻せる。壊れた点は飛ばし、時刻順に並べる', () {
      final plan = DayPlan(day: '2026/10/06', points: [
        const PlanPoint(hour: 14, valence: 6.5, activity: 'work'),
        const PlanPoint(hour: 10, valence: 4),
      ]);
      final read = DayPlan.fromMap({
        ...plan.toMap(),
        'points': [...plan.toMap()['points'] as List, 'こわれた点', {'hour': 9}],
      });
      expect(read.day, '2026/10/06');
      expect(read.points.map((p) => p.hour), [10, 14]);
      expect(read.points.last.activity, 'work');
    });

    test('予定が無い日は空になる', () {
      expect(DayPlan.fromMap(const {}).isEmpty, isTrue);
    });

    test('保存先のIDは日記と同じ yyyy-MM-dd', () {
      expect(planDocId(DateTime(2026, 10, 6)), '2026-10-06');
    });
  });

  group('予定と実際の見比べ', () {
    test('30分以内の記録と結びつく。離れていれば結びつかない', () {
      final plan = DayPlan(day: '2026/10/06', points: const [
        PlanPoint(hour: 11, valence: 7),
        PlanPoint(hour: 15, valence: 7),
      ]);
      final result = comparePlan(plan, [entry('11:20', 5.18), entry('16:10', 3)]);
      expect(result.first.actual?.time, '11:20');
      expect(result.first.diff, closeTo(5.18 - 7, 1e-9));
      expect(result.last.actual, isNull); // 16:10 は15時から70分離れている
      expect(result.last.diff, isNull);
    });

    test('同じ時刻に複数あれば、より近いほうと結びつく', () {
      final plan = DayPlan(
          day: '2026/10/06', points: const [PlanPoint(hour: 14, valence: 5)]);
      final result = comparePlan(plan, [entry('13:40', 3), entry('14:05', 7)]);
      expect(result.single.actual?.time, '14:05');
    });

    test('振り返りの一言は、ずれの平均で変わる', () {
      final plan = DayPlan(
          day: '2026/10/06', points: const [PlanPoint(hour: 14, valence: 5)]);
      // 記録が無ければ何も言わない。
      expect(planReflection(comparePlan(plan, const [])), isNull);
      // 0.5未満のずれは「予定どおり」。
      expect(planReflection(comparePlan(plan, [entry('14:00', 5.2)])),
          contains('予定どおり'));
      expect(planReflection(comparePlan(plan, [entry('14:00', 7.0)])),
          contains('良い'));
      expect(planReflection(comparePlan(plan, [entry('14:00', 3.0)])),
          contains('沈んだ'));
    });
  });

  group('予定が読めなかったとき', () {
    testWidgets('描けず、保存もできない（空で上書きしないため）',
        (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PlanCard(
              planDate: DateTime(2026, 10, 6),
              points: const [PlanPoint(hour: 12, valence: 6)],
              onChanged: (_) => fail('読み込みに失敗した状態では描けてはいけない'),
              onClear: () {},
              onSave: () => fail('読み込みに失敗した状態では保存できてはいけない'),
              saving: false,
              dirty: true,
              loadError: true,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('予定を読み込めませんでした（保存もできません）'), findsOneWidget);
      final save = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(save.onPressed, isNull);

      // なぞっても onChanged は呼ばれない（呼ばれたら fail で落ちる）。
      await tester.dragFrom(
        tester.getCenter(find.byType(PlanChart)),
        const Offset(60, -20),
      );
      await tester.pumpAndSettle();
    });
  });

  group('指でなぞって描く', () {
    testWidgets('なぞった場所に点ができる', (WidgetTester tester) async {
      var points = <PlanPoint>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 340,
            child: StatefulBuilder(
              builder: (context, setState) => PlanChart(
                points: points,
                onChanged: (next) => setState(() => points = next),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // 左のほうから右へなぞる。
      final box = tester.getRect(find.byType(PlanChart));
      await tester.dragFrom(
        Offset(box.left + 30, box.top + 40),
        const Offset(200, 40),
      );
      await tester.pumpAndSettle();

      expect(points, isNotEmpty);
      // 時刻順に並んでいて、同じ時刻は重複しない。
      final hours = points.map((p) => p.hour).toList();
      expect(hours, equals([...hours]..sort()));
      expect(hours.toSet().length, hours.length);
    });

    testWidgets('見るだけのとき（onChanged なし）は描けない',
        (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 340,
            child: PlanChart(
              points: const [PlanPoint(hour: 12, valence: 6)],
              actual: [entry('12:00', 5.18)],
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final box = tester.getRect(find.byType(PlanChart));
      await tester.dragFrom(box.center, const Offset(80, -30));
      await tester.pumpAndSettle();

      // 点は1つのまま（なぞっても増えない）。実際の記録は重ねて描ける。
      expect(find.byType(EmojiImage), findsOneWidget);
    });
  });
}
