// 画面幅ごとのレイアウトのテスト。
//
// このアプリはスマホ前提で作ってあり、iPhone 12 Pro（幅390px）で
// ちょうど良く見えるように余白やマーカーの大きさを決めている。
// パソコンのブラウザは幅が1920pxまで伸びるため、本文の幅を制限しないと
// サマリーカードが1枚600px以上になり、同じ画面に見えなくなる。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:emo_nikki/dashboard_page.dart';
import 'package:emo_nikki/emotion_analysis.dart';
import 'package:emo_nikki/layout.dart';

EmotionEntry entry(String time, double valence) => EmotionEntry(
      time: time,
      emoji: '😊',
      name: 'SmilingFaceWithSmilingEyes',
      valence: valence,
      arousal: 7.03,
    );

/// 画面幅 [width] でウィジェットを描く（テスト用ウィンドウごと差し替える）。
Future<void> pumpAt(
  WidgetTester tester,
  double width,
  Widget child,
) async {
  tester.view.physicalSize = Size(width, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  await tester.pumpAndSettle();
}

void main() {
  group('ContentWidth', () {
    // スマホの幅（390）は上限より狭いので、制限は何もしない＝従来どおり。
    testWidgets('スマホ幅では何も制限しない（今の見た目を変えない）',
        (WidgetTester tester) async {
      await pumpAt(tester, 390, const ContentWidth(child: Placeholder()));
      expect(tester.getSize(find.byType(Placeholder)).width, 390);
    });

    for (final width in [768.0, 1280.0, 1920.0]) {
      testWidgets('幅$widthでは本文を$kMaxContentWidthに収める',
          (WidgetTester tester) async {
        await pumpAt(tester, width, const ContentWidth(child: Placeholder()));
        expect(tester.getSize(find.byType(Placeholder)).width,
            kMaxContentWidth);
      });
    }

    testWidgets('本文は中央に寄る（左に貼りつかない）', (WidgetTester tester) async {
      await pumpAt(tester, 1280, const ContentWidth(child: Placeholder()));
      final left = tester.getTopLeft(find.byType(Placeholder)).dx;
      expect(left, closeTo((1280 - kMaxContentWidth) / 2, 0.01));
    });
  });

  group('ダッシュボードの中身', () {
    Widget body(List<EmotionEntry> entries) => ContentWidth(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SummaryCards(entries: entries, estimate: estimateMood(entries)),
              const SizedBox(height: 16),
              EmotionChart(entries: entries),
            ],
          ),
        );

    testWidgets('サマリーカードはパソコン幅でも広がりすぎない',
        (WidgetTester tester) async {
      final entries = [entry('11:00', 7.75), entry('15:00', 3.02)];

      await pumpAt(tester, 390, body(entries));
      final onPhone = tester.getSize(find.byType(Card).first).width;

      await pumpAt(tester, 1920, body(entries));
      final onDesktop = tester.getSize(find.byType(Card).first).width;

      // 制限が無いと1920pxのとき1枚624pxまで広がっていた。
      expect(onDesktop, lessThan(160));
      // スマホ側は変わらない（390pxのときの見た目を壊していない）。
      expect(onPhone, closeTo(114, 1));
    });

    testWidgets('画面をどれだけ広げても本文の幅は変わらない',
        (WidgetTester tester) async {
      final entries = [entry('12:00', 7.75)];

      await pumpAt(tester, 1280, body(entries));
      final at1280 = tester.getSize(find.byType(Card).first).width;

      await pumpAt(tester, 1920, body(entries));
      final at1920 = tester.getSize(find.byType(Card).first).width;

      expect(at1920, closeTo(at1280, 0.01));
    });
  });
}
