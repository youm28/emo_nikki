// ダッシュボードのロジック層（純粋関数）のテスト。

import 'package:flutter_test/flutter_test.dart';

import 'package:emo_nikki/emotion_analysis.dart';

EmotionEntry entry(String time, double valence) => EmotionEntry(
      time: time,
      emoji: '😀',
      name: 'GrinningFace',
      valence: valence,
      arousal: 5.0,
    );

void main() {
  group('normalizeValence', () {
    test('最小値2.88は-1、最大値7.83は+1に正規化される', () {
      expect(normalizeValence(2.88), closeTo(-1, 1e-9));
      expect(normalizeValence(7.83), closeTo(1, 1e-9));
    });
  });

  group('estimateMood（ピーク値法）', () {
    test('記録0件は Neutral・ピークなし', () {
      final r = estimateMood([]);
      expect(r.mood, Mood.neutral);
      expect(r.peakIndex, isNull);
    });

    test('7.83のみが最大なら Positive', () {
      final r = estimateMood([entry('10:00', 5.18), entry('11:00', 7.83)]);
      expect(r.mood, Mood.positive);
      expect(r.peakIndex, 1);
    });

    test('2.88（正規化-1）は Negative', () {
      final r = estimateMood([entry('10:00', 2.88), entry('11:00', 5.18)]);
      expect(r.mood, Mood.negative);
      expect(r.peakIndex, 0);
    });

    test('ニュートラル帯（例 5.18 → 約-0.07）は Neutral', () {
      final r = estimateMood([entry('10:00', 5.18)]);
      expect(r.mood, Mood.neutral);
    });

    test('受け入れ基準4: 2.88と7.83が両方ある日は先に現れる方がピーク', () {
      // |normalize| がどちらも 1 で等しい → 先勝ち。
      final r1 = estimateMood([entry('09:00', 2.88), entry('10:00', 7.83)]);
      expect(r1.peakIndex, 0);
      expect(r1.mood, Mood.negative);

      final r2 = estimateMood([entry('09:00', 7.83), entry('10:00', 2.88)]);
      expect(r2.peakIndex, 0);
      expect(r2.mood, Mood.positive);
    });
  });

  group('averageValence', () {
    test('平均が正しい・空は null', () {
      expect(averageValence([entry('10:00', 4.0), entry('11:00', 6.0)]), 5.0);
      expect(averageValence([]), isNull);
    });
  });

  group('チャート座標', () {
    test('横軸範囲: 基本は6:00〜24:00、早朝記録があれば0:00〜24:00', () {
      expect(chartTimeRange([entry('06:00', 5)]),
          (startMin: 360, endMin: 1440));
      expect(chartTimeRange([entry('05:59', 5)]), (startMin: 0, endMin: 1440));
      expect(chartTimeRange([]), (startMin: 360, endMin: 1440));
    });

    test('timeToX は範囲を幅に線形写像する', () {
      const range = (startMin: 360, endMin: 1440);
      expect(timeToX(360, range, 100), 0);
      expect(timeToX(1440, range, 100), 100);
      expect(timeToX(900, range, 100), 50); // 15:00 は中央
    });

    test('valenceToY は 1〜9 を高さに写像（9が上=0）', () {
      expect(valenceToY(9, 100), 0);
      expect(valenceToY(1, 100), 100);
      expect(valenceToY(5, 100), 50);
    });

    test('adjustOverlaps は最小間隔を確保して右へずらす', () {
      expect(adjustOverlaps([100, 105, 300], 38), [100, 138, 300]);
      expect(adjustOverlaps([100, 105, 110], 38), [100, 138, 176]);
      expect(adjustOverlaps([], 38), <double>[]);
    });
  });

  group('timeToMinutes / formatDay', () {
    test('"11:16" は 676 分、不正な文字列は null', () {
      expect(timeToMinutes('11:16'), 676);
      expect(timeToMinutes('bad'), isNull);
    });

    test('formatDayWithWeekday は曜日付き表示になる', () {
      expect(formatDayWithWeekday(DateTime(2026, 7, 23)), '2026/07/23（木）');
    });
  });
}
