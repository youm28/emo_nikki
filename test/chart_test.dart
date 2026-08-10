// チャートの横軸（固定縮尺・横スクロール・マーカーのずれ）のテスト。

import 'dart:math';

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
  // マーカーの自動ずらし（重なり回避）は廃止し、常に真の時刻位置に厳密表示する
  // 設計に変更された。時刻がどれだけ近くても x座標は timeToX の計算どおりになる。
  test('マーカーの位置は常に真の時刻どおり（重なっていてもずらさない）', () {
    const range = kChartBaseRange;
    final width = plotWidthFor(range);
    final farXs = [
      timeToX(11 * 60, range, width), // 11:00
      timeToX(13 * 60, range, width), // 13:00
    ];
    final closeXs = [
      timeToX(12 * 60, range, width), // 12:00
      timeToX(12 * 60 + 5, range, width), // 12:05（5分差）
    ];
    // 離れていても近くても、xs 自体（timeToXの結果）がそのままマーカー位置になる。
    // spreadSymmetric等の後処理を経由しないので、差分は時間比例のまま。
    expect(closeXs[1] - closeXs[0],
        closeTo((farXs[1] - farXs[0]) * (5 / 120), 1e-9));
  });

  testWidgets('5分差でもマーカーは重なり、位置は時刻どおりになる',
      (WidgetTester tester) async {
    final entries = [entry('12:00', 7.75), entry('12:05', 3.02)];
    await tester.pumpWidget(wrap(entries));
    await tester.pumpAndSettle();

    double contentX(int index) {
      final position =
          tester.state<ScrollableState>(find.byType(Scrollable)).position;
      return tester.getTopLeft(find.byType(EmojiImage).at(index)).dx +
          position.pixels;
    }

    final expectedGap =
        timeToX(12 * 60 + 5, kChartBaseRange, plotWidthFor(kChartBaseRange)) -
            timeToX(12 * 60, kChartBaseRange, plotWidthFor(kChartBaseRange));
    expect(contentX(1) - contentX(0), closeTo(expectedGap, 1));
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

  testWidgets('チャートは横スクロール可能で、最初の記録の手前から始まる',
      (WidgetTester tester) async {
    await tester.pumpWidget(wrap([entry('15:00', 5.18)]));
    await tester.pumpAndSettle();

    final view = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    expect(view.scrollDirection, Axis.horizontal);

    // チャート幅は1画面に収まる設計（縮尺調整による）なので、スマホ幅でも
    // 必ずスクロールが必要とは限らない。初期位置の計算が効いていることだけ確認する。
    final position =
        tester.state<ScrollableState>(find.byType(Scrollable)).position;
    // 15:00（x≒159）の少し手前が初期位置。ただしコンテンツが画面に収まる場合は
    // maxScrollExtentが0になり、pixelsも0に留まる。
    expect(position.pixels, closeTo(min(119, position.maxScrollExtent), 1));
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
    // 11:00（x≒32）の40px手前はマイナスになるので0に張り付く。
    expect(position.pixels, closeTo(0, 1));
  });

  testWidgets('既定の範囲(10:00〜20:00)の外の記録もチャートに出る',
      (WidgetTester tester) async {
    // 記録数・推定感情・平均は全記録から計算しているので、グラフだけ
    // 時間外を落とすと数字と食い違う。横軸のほうを広げて合わせている。
    await tester.pumpWidget(wrap([
      entry('07:30', 5.18),
      entry('12:00', 7.75),
      entry('22:00', 3.02),
    ]));
    await tester.pumpAndSettle();

    expect(find.byType(EmojiImage), findsNWidgets(3));
  });

  testWidgets('時間外の記録がある日は横スクロールできる幅になる',
      (WidgetTester tester) async {
    await tester.pumpWidget(wrap([entry('12:00', 7.75)]));
    await tester.pumpAndSettle();
    final normal =
        tester.state<ScrollableState>(find.byType(Scrollable)).position;
    final normalExtent = normal.maxScrollExtent;

    await tester.pumpWidget(wrap([entry('07:30', 5.18), entry('12:00', 7.75)]));
    await tester.pumpAndSettle();
    final widened =
        tester.state<ScrollableState>(find.byType(Scrollable)).position;

    expect(widened.maxScrollExtent, greaterThan(normalExtent),
        reason: '範囲が広がった分だけスクロールできる量も増えるはず');
  });
}
