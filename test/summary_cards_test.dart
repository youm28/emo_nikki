// サマリーカード（記録数／推定感情／平均Valence）の表示テスト。
//
// 推定感情のラベルは3枚並んだカードの1枚に入るため、横幅がいちばん厳しい。
// 以前は絵文字と横並びにしていて「ニュートラル」が「…」で切れていた。

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:emo_nikki/dashboard_page.dart';
import 'package:emo_nikki/emotion_analysis.dart';

EmotionEntry entry(String time, double valence) => EmotionEntry(
      time: time,
      emoji: '😊',
      name: 'SmilingFaceWithSmilingEyes',
      valence: valence,
      arousal: 7.03,
    );

/// 指定幅にサマリーカードを置く（既定はスマホの実幅）。
Widget wrap(List<EmotionEntry> entries, {double width = 360}) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: width,
          child: SummaryCards(
            entries: entries,
            estimate: estimateMood(entries),
          ),
        ),
      ),
    );

/// そのテキストが省略記号なしで全部描かれているか。
bool isFullyVisible(WidgetTester tester, String text) {
  final rp = tester.renderObject<RenderParagraph>(find.text(text));
  return !rp.didExceedMaxLines;
}

void main() {
  group('推定感情のラベルは切り詰めない', () {
    // 「ニュートラル」6文字がいちばん長い＝いちばん厳しい条件。
    for (final (label, valence) in [
      ('ニュートラル', 5.18),
      ('ポジティブ', 7.83),
      ('ネガティブ', 2.88),
    ]) {
      testWidgets('スマホ幅(360)でも「$label」が全部見える',
          (WidgetTester tester) async {
        await tester.pumpWidget(wrap([entry('12:00', valence)]));
        await tester.pumpAndSettle();

        expect(find.text(label), findsOneWidget);
        expect(isFullyVisible(tester, label), isTrue,
            reason: '「$label」が省略されている');
      });
    }

    testWidgets('さらに狭い画面(320)でも省略しない', (WidgetTester tester) async {
      await tester.pumpWidget(wrap([entry('12:00', 5.18)], width: 320));
      await tester.pumpAndSettle();

      expect(isFullyVisible(tester, 'ニュートラル'), isTrue);
    });
  });

  testWidgets('記録が無い日は3枚とも「−」相当の表示になる',
      (WidgetTester tester) async {
    await tester.pumpWidget(wrap(const []));
    await tester.pumpAndSettle();

    expect(find.text('0 件'), findsOneWidget);
    expect(find.text('−'), findsNWidgets(2)); // 推定感情と平均Valence
  });

  testWidgets('3枚のカードは同じ高さに揃う', (WidgetTester tester) async {
    // 推定感情だけ絵文字の分だけ背が高くなるので、揃っていることを確かめる。
    await tester.pumpWidget(wrap([entry('12:00', 5.18)]));
    await tester.pumpAndSettle();

    final heights = <double>[
      for (var i = 0; i < 3; i++) tester.getSize(find.byType(Card).at(i)).height,
    ];
    expect(heights[1], closeTo(heights[0], 0.01));
    expect(heights[2], closeTo(heights[0], 0.01));
  });
}
