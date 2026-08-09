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
    test('横軸範囲は日によらず 10:00〜20:00 固定（1分=1px）', () {
      expect(kChartRange, (startMin: 600, endMin: 1200));
      expect(kChartPlotWidth, 600); // 10時間ぶん
      // 縮尺は常に 1分=1px（範囲を変えてもここは変わらない）。
      expect(timeToX(10 * 60, kChartRange, kChartPlotWidth), 0);
      expect(timeToX(12 * 60, kChartRange, kChartPlotWidth), 120);
      expect(timeToX(20 * 60, kChartRange, kChartPlotWidth), 600);
    });

    test('範囲外の記録はチャートに出さないが件数は数える', () {
      expect(isInChartRange(entry('10:00', 5)), isTrue);
      expect(isInChartRange(entry('20:00', 5)), isTrue); // 端は含む
      expect(isInChartRange(entry('09:59', 5)), isFalse);
      expect(isInChartRange(entry('20:01', 5)), isFalse);

      final entries = [entry('07:00', 5), entry('12:00', 5), entry('23:00', 5)];
      expect(outOfChartRangeCount(entries), 2);
      expect(chartRangeLabel(), '10:00〜20:00');
    });

    test('timeToX は範囲を幅に線形写像する', () {
      const range = (startMin: 360, endMin: 1440);
      expect(timeToX(360, range, 100), 0);
      expect(timeToX(1440, range, 100), 100);
      expect(timeToX(900, range, 100), 50); // 15:00 は中央
    });

    test('初期スクロール位置は最初の記録の少し手前', () {
      // 15:00 の記録 → x=300 の 40px 手前。
      expect(initialScrollOffset([entry('15:00', 5)]), 260);
      // 左端寄りの記録はマイナスにせず 0 に張り付く。
      expect(initialScrollOffset([entry('10:20', 5)]), 0);
      // 記録が無い日・範囲外だけの日は左端（10:00）。
      expect(initialScrollOffset([]), 0);
      expect(initialScrollOffset([entry('07:00', 5)]), 0);
      // 範囲外の記録は飛ばして、範囲内の最初の記録に合わせる。
      expect(initialScrollOffset([entry('07:00', 5), entry('15:00', 5)]), 260);
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

    test('spreadSymmetric は固まりを本来位置の中心へ左右対称に広げる', () {
      // 3件が同一位置(200) → 中心200のまま、-gap/0/+gap に広がる。
      expect(spreadSymmetric([200, 200, 200], 30), [170, 200, 230]);
      // 十分離れていれば動かさない（真の時刻位置を保つ）。
      expect(spreadSymmetric([100, 300], 30), [100, 300]);
      // 左端の固まりは負にならないよう 0 以上へ寄せる。
      final r = spreadSymmetric([0, 0], 30);
      expect(r.first, greaterThanOrEqualTo(0));
      expect(r[1] - r[0], closeTo(30, 1e-9));
    });
  });

  group('pickRecentDuplicateId（5分以内の上書き対象）', () {
    test('5分以内の記録があればその中で最も新しいIDを返す', () {
      final existing = [
        (id: 'a', minutes: 600), // 10:00
        (id: 'b', minutes: 613), // 10:13
        (id: 'c', minutes: 616), // 10:16
      ];
      // now=10:18(618)。5分以内は b(5分)とc(2分) → 新しい方 c。
      expect(pickRecentDuplicateId(existing, 618), 'c');
    });

    test('5分より離れていれば null（新規追加になる）', () {
      final existing = [(id: 'a', minutes: 600)];
      expect(pickRecentDuplicateId(existing, 606), isNull); // 6分差
    });

    test('境界5分ちょうどは対象に含む', () {
      final existing = [(id: 'a', minutes: 600)];
      expect(pickRecentDuplicateId(existing, 605), 'a');
    });

    test('記録が無ければ null', () {
      expect(pickRecentDuplicateId(const [], 605), isNull);
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
