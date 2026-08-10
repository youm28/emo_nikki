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
    test('既定の範囲は 10:00〜20:00（1分=0.53px）', () {
      expect(kChartBaseRange, (startMin: 600, endMin: 1200));
      final range = chartRangeFor([entry('12:00', 5)]);
      expect(range, kChartBaseRange);
      expect(plotWidthFor(range), closeTo(318, 0.01)); // 10時間 × 0.53
      expect(timeToX(10 * 60, range, plotWidthFor(range)), 0);
      expect(
          timeToX(15 * 60, range, plotWidthFor(range)), closeTo(159, 0.01));
      expect(
          timeToX(20 * 60, range, plotWidthFor(range)), closeTo(318, 0.01));
    });

    test('記録が範囲外なら、その記録を含む正時まで広げる', () {
      // 集計（記録数・推定感情・平均）は全記録を対象にしているので、
      // グラフだけ時間外を捨てると数字と食い違う。範囲のほうを合わせる。
      expect(chartRangeFor([entry('07:30', 5)]),
          (startMin: 7 * 60, endMin: 20 * 60));
      expect(chartRangeFor([entry('22:10', 5)]),
          (startMin: 10 * 60, endMin: 23 * 60));
      // 両側にはみ出す日は両方広がる。
      expect(chartRangeFor([entry('06:05', 5), entry('23:50', 5)]),
          (startMin: 6 * 60, endMin: 24 * 60));
      // 正時ちょうどは端に合わせるだけで、余分な1時間は足さない。
      expect(chartRangeFor([entry('21:00', 5)]),
          (startMin: 10 * 60, endMin: 21 * 60));
    });

    test('範囲が広がると幅も比例して伸びる（縮尺は固定）', () {
      final wide = chartRangeFor([entry('07:00', 5)]);
      // 13時間ぶん。1分あたりの px は変わらない。
      expect(plotWidthFor(wide), closeTo(13 * 60 * 0.53, 0.01));
    });

    test('時刻が読めない記録だけがチャートから落ちる', () {
      final range = chartRangeFor([entry('12:00', 5)]);
      expect(isInChartRange(entry('10:00', 5), range), isTrue);
      expect(isInChartRange(entry('20:00', 5), range), isTrue); // 端は含む
      expect(isInChartRange(entry('09:59', 5), range), isFalse);

      // 時刻が壊れた記録は範囲を広げる根拠にもならず、描画対象にもならない。
      final broken = entry('bad', 5);
      expect(chartRangeFor([broken]), kChartBaseRange);
      expect(isInChartRange(broken, chartRangeFor([broken])), isFalse);
    });

    test('時間外の記録もチャートに出る（描画対象から漏れない）', () {
      final entries = [entry('07:00', 5), entry('12:00', 5), entry('23:00', 5)];
      final range = chartRangeFor(entries);
      expect(entries.every((e) => isInChartRange(e, range)), isTrue);
    });

    test('timeToX は範囲を幅に線形写像する', () {
      const range = (startMin: 360, endMin: 1440);
      expect(timeToX(360, range, 100), 0);
      expect(timeToX(1440, range, 100), 100);
      expect(timeToX(900, range, 100), 50); // 15:00 は中央
    });

    test('初期スクロール位置は最初の記録の少し手前', () {
      // 15:00 の記録 → x≒159 の 40px 手前。
      expect(initialScrollOffset([entry('15:00', 5)]), closeTo(119, 1));
      // 左端寄りの記録はマイナスにせず 0 に張り付く。
      expect(initialScrollOffset([entry('10:20', 5)]), 0);
      // 記録が無い日は左端（10:00）。
      expect(initialScrollOffset([]), 0);
      // 時間外の記録は範囲ごと広がるので、そこが左端になる（0に張り付く）。
      expect(initialScrollOffset([entry('07:00', 5)]), 0);
      // 時間外の記録も飛ばさない。7:00 が最初の記録なら、そこが左端になる。
      // （以前は範囲外として読み飛ばし、10:00 に合わせていた）
      expect(initialScrollOffset([entry('07:00', 5), entry('15:00', 5)]), 0);
      // 記録が既定範囲に収まる日は今までどおり、最初の記録の 40px 手前。
      expect(initialScrollOffset([entry('13:00', 5), entry('15:00', 5)]),
          closeTo(3 * 60 * 0.53 - 40, 1));
    });

    test('valenceToY は 2〜8 を高さに写像（8が上=0）', () {
      expect(valenceToY(8, 100), 0);
      expect(valenceToY(2, 100), 100);
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
