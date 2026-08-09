// 行動入力（絵文字と一緒に「何をしていたか」を記録する）のテスト。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:emo_nikki/dashboard_page.dart';
import 'package:emo_nikki/emotion_analysis.dart';
import 'package:emo_nikki/main.dart';

EmotionEntry entry(String time, double valence, {String? activity}) =>
    EmotionEntry(
      time: time,
      emoji: '😊',
      name: 'SmilingFaceWithSmilingEyes',
      valence: valence,
      arousal: 7.03,
      activity: activity,
    );

void main() {
  test('固定の行動データは17件・name は重複しない', () {
    expect(kActivityList.length, 17);
    final names = kActivityList.map((a) => a.name).toSet();
    expect(names.length, kActivityList.length);
  });

  test('activityItemByName は未選択(null)・未知の名前で null を返す', () {
    expect(activityItemByName('work')?.labelJa, '仕事');
    expect(activityItemByName(null), isNull);
    expect(activityItemByName('unknown'), isNull);
  });

  test('記録データに activity が入る（未選択なら null）', () {
    final item = kEmojiList[1];
    final withAct = buildEmotionRecord(
      item,
      now: DateTime(2026, 8, 9, 14, 30),
      activity: kActivityList.first, // work
    );
    expect(withAct['activity'], 'work');

    final without = buildEmotionRecord(item, now: DateTime(2026, 8, 9, 14, 30));
    expect(without['activity'], isNull);
  });

  test('EmotionEntry.fromMap は activity 未設定の古い記録も読める', () {
    final old = EmotionEntry.fromMap({
      'time': '09:00',
      'emoji': '😊',
      'name': 'SmilingFaceWithSmilingEyes',
      'valence': 7.75,
      'arousal': 7.03,
    });
    expect(old, isNotNull);
    expect(old!.activity, isNull);

    final withAct = EmotionEntry.fromMap({
      'time': '09:00',
      'emoji': '😊',
      'name': 'SmilingFaceWithSmilingEyes',
      'valence': 7.75,
      'arousal': 7.03,
      'activity': 'sara',
    });
    expect(withAct!.activity, 'sara');
  });

  testWidgets('絵文字をタップすると行動17件つきの確認ダイアログが出る',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'username': 'taro'});
    await tester.pumpWidget(const EmoNikkiApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(EmojiTile).first);
    await tester.pumpAndSettle();

    expect(find.text('何をしていましたか？（任意）'), findsOneWidget);
    expect(find.byType(ActivityImage), findsNWidgets(kActivityList.length));
    expect(find.text('記録'), findsOneWidget);

    // キャンセルで閉じられる（保存処理には進まない）。
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    expect(find.text('何をしていましたか？（任意）'), findsNothing);
  });

  testWidgets('スマホ幅(375x667)でもダイアログがはみ出さない',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({'username': 'taro'});
    await tester.pumpWidget(const EmoNikkiApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(EmojiTile).first);
    await tester.pumpAndSettle();

    // オーバーフローがあればこの時点で例外になる。
    expect(find.byType(ActivityImage), findsNWidgets(kActivityList.length));
  });

  testWidgets('チャートは行動が記録された分だけ行動レーンに並べる',
      (WidgetTester tester) async {
    final entries = [
      entry('11:00', 7.75, activity: 'work'),
      entry('12:00', 3.02), // 行動なし → レーンには出ない
      entry('18:00', 5.18, activity: 'sara'),
    ];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: EmotionChart(entries: entries, peakIndex: 0)),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(ActivityImage), findsNWidgets(2));
  });

  testWidgets('行動が1件も無い日は行動レーンを出さない', (WidgetTester tester) async {
    final entries = [entry('09:00', 7.75), entry('12:00', 3.02)];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: EmotionChart(entries: entries)),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(ActivityImage), findsNothing);
  });
}
