/// ダッシュボードのロジック層（純粋関数のみ・Flutter非依存）。
/// ウィジェットから分離してテスト可能にしている（要件書 §5）。
library;

/// 1件の感情記録（Firestoreから読んだもの）。
class EmotionEntry {
  final String time; // "HH:mm"
  final String emoji; // Unicode絵文字
  final String name; // 画像ファイル名（拡張子なし）
  final double valence;
  final double arousal;
  final String? activity; // 行動の画像ファイル名。未入力・行動追加前の記録は null

  const EmotionEntry({
    required this.time,
    required this.emoji,
    required this.name,
    required this.valence,
    required this.arousal,
    this.activity,
  });

  /// Firestoreのドキュメントデータから生成。型が想定外なら null。
  static EmotionEntry? fromMap(Map<String, dynamic> data) {
    final time = data['time'];
    final emoji = data['emoji'];
    final name = data['name'];
    final valence = data['valence'];
    final arousal = data['arousal'];
    if (time is! String || emoji is! String || name is! String) return null;
    if (valence is! num || arousal is! num) return null;
    // activity は後から追加したフィールド。無い/文字列でない古い記録は null 扱い。
    final activity = data['activity'];
    return EmotionEntry(
      time: time,
      emoji: emoji,
      name: name,
      valence: valence.toDouble(),
      arousal: arousal.toDouble(),
      activity: activity is String && activity.isNotEmpty ? activity : null,
    );
  }

  /// "HH:mm" を 0:00 からの経過分に変換（例 "11:16" → 676）。不正なら null。
  int? get minutes => timeToMinutes(time);
}

/// "HH:mm" → 経過分。パースできなければ null。
int? timeToMinutes(String time) {
  final parts = time.split(':');
  if (parts.length != 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  return h * 60 + m;
}

/// DateTime → "yyyy/MM/dd"（Firestoreの day フィールドと同形式）。
String formatDay(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}/${two(d.month)}/${two(d.day)}';
}

/// DateTime → "2026/07/23（木）" 形式の表示用文字列。
String formatDayWithWeekday(DateTime d) {
  const weekdays = ['月', '火', '水', '木', '金', '土', '日'];
  return '${formatDay(d)}（${weekdays[d.weekday - 1]}）';
}

// ---------------------------------------------------------------------------
// ピーク値法（元研究 peak_value_estimator.py の移植。要件書 §F3）
// ---------------------------------------------------------------------------

const double kValenceMin = 2.88;
const double kValenceMax = 7.83;

/// valence を [-1, 1] に正規化する。
double normalizeValence(double v) =>
    2 * (v - kValenceMin) / (kValenceMax - kValenceMin) - 1;

enum Mood { positive, neutral, negative }

extension MoodLabel on Mood {
  String get labelJa => switch (this) {
        Mood.positive => 'ポジティブ',
        Mood.neutral => 'ニュートラル',
        Mood.negative => 'ネガティブ',
      };
}

/// ピーク値法の結果。記録0件なら mood=neutral, peakIndex=null。
class MoodEstimate {
  final Mood mood;
  final int? peakIndex; // entries 内のピーク記録の添字

  const MoodEstimate(this.mood, this.peakIndex);
}

/// その日の全記録から推定感情を求める。
/// |normalize(v)| が最大の記録をピークとする。同値なら先に現れる方（strict > で実現）。
MoodEstimate estimateMood(List<EmotionEntry> entries) {
  if (entries.isEmpty) return const MoodEstimate(Mood.neutral, null);

  var peakIndex = 0;
  var peakAbs = normalizeValence(entries[0].valence).abs();
  for (var i = 1; i < entries.length; i++) {
    final abs = normalizeValence(entries[i].valence).abs();
    if (abs > peakAbs) {
      peakAbs = abs;
      peakIndex = i;
    }
  }

  final p = normalizeValence(entries[peakIndex].valence);
  final Mood mood;
  if (p > 0.140) {
    mood = Mood.positive;
  } else if (p < -0.176) {
    mood = Mood.negative;
  } else {
    mood = Mood.neutral;
  }
  return MoodEstimate(mood, peakIndex);
}

/// 平均 valence。空なら null。
double? averageValence(List<EmotionEntry> entries) {
  if (entries.isEmpty) return null;
  final sum = entries.fold<double>(0, (a, e) => a + e.valence);
  return sum / entries.length;
}

// ---------------------------------------------------------------------------
// チャートの座標計算（要件書 §F2）
// ---------------------------------------------------------------------------

/// 縦軸は Valence 1〜9 固定（日間比較のため）。
const double kChartValenceMin = 1;
const double kChartValenceMax = 9;

/// 横軸の範囲（分）。基本 6:00〜24:00、範囲外の記録がある日は 0:00〜24:00。
({int startMin, int endMin}) chartTimeRange(List<EmotionEntry> entries) {
  const defaultStart = 6 * 60; // 6:00
  const end = 24 * 60; // 24:00
  for (final e in entries) {
    final m = e.minutes;
    if (m != null && m < defaultStart) {
      return (startMin: 0, endMin: end); // 早朝の記録がある日は全日表示
    }
  }
  return (startMin: defaultStart, endMin: end);
}

/// 経過分 → x座標（0〜width の線形写像）。
double timeToX(int minutes, ({int startMin, int endMin}) range, double width) {
  final span = (range.endMin - range.startMin).toDouble();
  return (minutes - range.startMin) / span * width;
}

/// valence → y座標（上が9・下が1。0〜height の線形写像）。
double valenceToY(double valence, double height) {
  final t = (valence - kChartValenceMin) / (kChartValenceMax - kChartValenceMin);
  return (1 - t) * height;
}

/// マーカーの重なり回避（右詰め）。
/// 時刻昇順の x 座標リストに対し、前のマーカーと最低 minGap 空くよう右へずらす。
List<double> adjustOverlaps(List<double> xs, double minGap) {
  final result = List<double>.from(xs);
  for (var i = 1; i < result.length; i++) {
    if (result[i] < result[i - 1] + minGap) {
      result[i] = result[i - 1] + minGap;
    }
  }
  return result;
}

/// マーカーの重なり回避（左右対称版・要件書 §F2 の改良）。
/// 重なって固まったグループを、その「本来の時刻位置の平均」を中心に左右へ広げる。
/// 右へ一方向にずらす adjustOverlaps と違い、時間軸の読みが右へ偏らない。
List<double> spreadSymmetric(List<double> xs, double minGap) {
  final n = xs.length;
  if (n == 0) return <double>[];

  // 1. まず右詰めで最小間隔を確保する。
  final packed = adjustOverlaps(xs, minGap);
  final result = List<double>.from(packed);

  // 2. 「密着している連続グループ」ごとに、本来位置の平均へ中心を合わせる。
  var i = 0;
  while (i < n) {
    var j = i;
    while (j + 1 < n && packed[j + 1] - packed[j] <= minGap + 1e-6) {
      j++;
    }
    if (j > i) {
      var origSum = 0.0;
      var packedSum = 0.0;
      for (var k = i; k <= j; k++) {
        origSum += xs[k];
        packedSum += packed[k];
      }
      final shift = (origSum - packedSum) / (j - i + 1);
      for (var k = i; k <= j; k++) {
        result[k] = packed[k] + shift;
      }
    }
    i = j + 1;
  }

  // 3. 中心寄せでグループ同士が近づきすぎた場合だけ、右詰めで解消する。
  final spread = adjustOverlaps(result, minGap);

  // 4. 左端で負にはみ出したら、間隔を保ったまま全体を右へ寄せて 0 以上にする。
  final minX = spread.reduce((a, b) => a < b ? a : b);
  if (minX < 0) {
    for (var k = 0; k < spread.length; k++) {
      spread[k] -= minX;
    }
  }
  return spread;
}

/// 5分以内（既定 windowMin=5）の既存記録があれば、その中で最も新しい記録のID
/// を返す（＝上書き対象）。無ければ null。誤タップや「選び直し」を1件にまとめるため。
String? pickRecentDuplicateId(
  List<({String id, int? minutes})> existing,
  int nowMinutes, {
  int windowMin = 5,
}) {
  String? bestId;
  int? bestMin;
  for (final e in existing) {
    final m = e.minutes;
    if (m == null) continue;
    if ((nowMinutes - m).abs() <= windowMin) {
      if (bestMin == null || m > bestMin) {
        bestMin = m;
        bestId = e.id;
      }
    }
  }
  return bestId;
}
