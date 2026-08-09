// チャートの横軸（固定縮尺・横スクロール・マーカーのずれ）のテスト。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:emo_nikki/dashboard_page.dart';
import 'package:emo_nikki/emoji.dart';
import 'package:emo_nikki/emotion_analysis.dart';

EmotionEntry entry(String time, double valence) => EmotionEntry(
      time: time,
      emoji: '😊',
      name: 'SmilingFaceWithSmilingEyes',
      valence: valence,
      arousal: 7.03,
    );

/// 指定幅の中にチャートを置く（スマホ幅を想定）。
Widget wrap(List<EmotionEntry> entries, {double width = 360}) => MaterialApp(
      home: Scaffold(
        body: SizedBox(width: width, child: EmotionChart(entries: entries)),
      ),
    );

void main() {
  test('30分以上離れた記録はマーカーがずれない（真の時刻位置に出る）', () {
    final xs = [
      timeToX(11 * 60, kChartRange, kChartPlotWidth), // 11:00
      timeToX(11 * 60 + 30, kChartRange, kChartPlotWidth), // 11:30（ちょうど30分）
      timeToX(13 * 60, kChartRange, kChartPlotWidth), // 13:00
    ];
    expect(spreadSymmetric(xs, kMarkerSize), xs);
  });

  test('29分差だとわずかにずれる（30分が境目であることの確認）', () {
    final xs = [
      timeToX(11 * 60, kChartRange, kChartPlotWidth),
      timeToX(11 * 60 + 29, kChartRange, kChartPlotWidth),
    ];
    expect(spreadSymmetric(xs, kMarkerSize), isNot(xs));
  });

  test('30分より近い記録だけ、真の時刻を中心に左右へ広がる', () {
    final xs = [
      timeToX(12 * 60, kChartRange, kChartPlotWidth), // 12:00 → 120
      timeToX(12 * 60 + 10, kChartRange, kChartPlotWidth), // 12:10 → 130
    ];
    final spread = spreadSymmetric(xs, kMarkerSize);
    expect(spread[1] - spread[0], closeTo(kMarkerSize, 1e-9));
    // 2件の中心は本来の中心(125)から動かない。
    expect((spread[0] + spread[1]) / 2, closeTo(125, 1e-9));
  });

  testWidgets('画面幅が変わっても同じ時刻は同じ位置に来る', (WidgetTester tester) async {
    // 画面上の位置はスクロール量で変わるので、スクロール内の座標で比べる。
    double contentX(WidgetTester tester) {
      final position =
          tester.state<ScrollableState>(find.byType(Scrollable)).position;
      return tester.getTopLeft(find.byType(EmojiImage).first).dx +
          position.pixels;
    }

    final entries = [entry('12:00', 7.75)];

    await tester.pumpWidget(wrap(entries, width: 320));
    await tester.pumpAndSettle();
    final narrow = contentX(tester);

    await tester.pumpWidget(wrap(entries, width: 700));
    await tester.pumpAndSettle();
    final wide = contentX(tester);

    // 以前は幅に合わせて伸縮していたためここがずれていた。
    expect(narrow, closeTo(wide, 0.01));
  });

  testWidgets('チャートは常に横スクロールでき、最初の記録の手前から始まる',
      (WidgetTester tester) async {
    await tester.pumpWidget(wrap([entry('15:00', 5.18)]));
    await tester.pumpAndSettle();

    final view = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    expect(view.scrollDirection, Axis.horizontal);

    final position =
        tester.state<ScrollableState>(find.byType(Scrollable)).position;
    // 10時間ぶんの幅があるので、スマホ幅では必ずスクロールできる。
    expect(position.maxScrollExtent, greaterThan(0));
    // 15:00（x=300）の少し手前が初期位置。
    expect(position.pixels, closeTo(260, 1));
  });

  testWidgets('日付を切り替えると、その日の最初の記録の位置に戻る',
      (WidgetTester tester) async {
    await tester.pumpWidget(wrap([entry('20:00', 5.18)]));
    await tester.pumpAndSettle();

    final position =
        tester.state<ScrollableState>(find.byType(Scrollable)).position;
    // 20:00 は右端なので上限まで寄る（記録はちゃんと画面内に入る）。
    expect(position.pixels, closeTo(position.maxScrollExtent, 1));

    // 別の日（午前だけ記録がある日）に切り替える。
    await tester.pumpWidget(wrap([entry('11:00', 5.18)]));
    await tester.pumpAndSettle();
    expect(position.pixels, closeTo(20, 1)); // 11:00 → 60 の40px手前
  });

  testWidgets('範囲外(9:00〜20:00の外)の記録はチャートに出さない',
      (WidgetTester tester) async {
    await tester.pumpWidget(wrap([
      entry('07:30', 5.18), // 範囲外
      entry('12:00', 7.75), // 範囲内
      entry('22:00', 3.02), // 範囲外
    ]));
    await tester.pumpAndSettle();

    // チャートに出るマーカーは範囲内の1件だけ。
    expect(find.byType(EmojiImage), findsOneWidget);
  });
}
