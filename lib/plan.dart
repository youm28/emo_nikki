/// 明日の「感情と行動の予定」（計画）のロジック（純粋関数のみ・Flutter非依存）。
///
/// 夜の日記のときに、翌日の気分の推移を指でなぞって描いてもらう。
/// 翌日になったら、その予定と実際の記録を並べて見せ、違いから振り返りを促す。
library;

import 'emoji.dart';
import 'emotion_analysis.dart';

/// 予定を立てる時間帯（記録を促す時間帯と同じ 10:00〜20:00）。
const int kPlanStartHour = 10;
const int kPlanEndHour = 20;

/// 予定の点が置ける時刻（毎正時）。10時〜20時なら11個。
List<int> get kPlanHours =>
    [for (var h = kPlanStartHour; h <= kPlanEndHour; h++) h];

/// 予定の1点。[hour] の気分を [valence]（2〜8）で表す。
class PlanPoint {
  final int hour;
  final double valence;

  /// その時間に予定している行動（任意）。
  final String? activity;

  const PlanPoint({required this.hour, required this.valence, this.activity});

  PlanPoint copyWith({double? valence, String? activity, bool clearActivity = false}) =>
      PlanPoint(
        hour: hour,
        valence: valence ?? this.valence,
        activity: clearActivity ? null : (activity ?? this.activity),
      );

  Map<String, dynamic> toMap() => {
        'hour': hour,
        'valence': valence,
        'activity': activity,
      };

  static PlanPoint? fromMap(Object? data) {
    if (data is! Map) return null;
    final hour = data['hour'];
    final valence = data['valence'];
    if (hour is! num || valence is! num) return null;
    final activity = data['activity'];
    return PlanPoint(
      hour: hour.toInt(),
      valence: valence.toDouble(),
      activity: activity is String && activity.isNotEmpty ? activity : null,
    );
  }
}

/// 1日ぶんの予定。[points] は時刻順。
class DayPlan {
  final String day; // yyyy/MM/dd（記録と同じ表記）
  final List<PlanPoint> points;

  const DayPlan({required this.day, required this.points});

  bool get isEmpty => points.isEmpty;

  Map<String, dynamic> toMap() => {
        'day': day,
        'points': [for (final p in points) p.toMap()],
      };

  static DayPlan fromMap(Map<String, dynamic> data) {
    final raw = data['points'];
    final points = <PlanPoint>[
      if (raw is List)
        for (final p in raw) ?PlanPoint.fromMap(p),
    ]..sort((a, b) => a.hour.compareTo(b.hour));
    return DayPlan(day: data['day'] as String? ?? '', points: points);
  }
}

/// 予定の保存先のドキュメントID（日記と同じ yyyy-MM-dd）。
String planDocId(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}';
}

/// その valence に一番近い絵文字。描いた線を「どの気分か」に対応させるために使う。
///
/// 同じ差なら、先に並んでいる絵文字を選ぶ（結果が毎回同じになるように）。
EmojiItem emojiForValence(double valence) {
  var best = kEmojiList.first;
  var bestDiff = (best.valence - valence).abs();
  for (final item in kEmojiList) {
    final diff = (item.valence - valence).abs();
    if (diff < bestDiff) {
      best = item;
      bestDiff = diff;
    }
  }
  return best;
}

/// 指の位置（x）から、どの時刻の点を動かしているかを決める。
/// [width] はグラフ本体の幅。範囲外の x でも両端の点に寄せる。
int planHourFromX(double x, double width) {
  final hours = kPlanHours;
  final step = width / (hours.length - 1);
  final index = (x / step).round().clamp(0, hours.length - 1);
  return hours[index];
}

/// 指の高さ（y）から valence を求める（上が8・下が2）。[valenceToY] の逆。
double planValenceFromY(double y, double height) {
  final t = 1 - (y / height);
  final v = kChartValenceMin + t * (kChartValenceMax - kChartValenceMin);
  return v.clamp(kChartValenceMin, kChartValenceMax);
}

/// 予定に点を足す／動かす（同じ時刻の点は1つだけ）。行動は引き継ぐ。
List<PlanPoint> setPlanPoint(List<PlanPoint> points, int hour, double valence) {
  final next = [for (final p in points) if (p.hour != hour) p];
  final old = points.where((p) => p.hour == hour).firstOrNull;
  next.add(PlanPoint(hour: hour, valence: valence, activity: old?.activity));
  next.sort((a, b) => a.hour.compareTo(b.hour));
  return next;
}

/// その時刻の点に行動を付ける／外す。
List<PlanPoint> setPlanActivity(List<PlanPoint> points, int hour, String? activity) =>
    [
      for (final p in points)
        if (p.hour == hour)
          p.copyWith(activity: activity, clearActivity: activity == null)
        else
          p,
    ];

/// 予定と実際の記録の突き合わせ1件ぶん。
class PlanComparison {
  final int hour;
  final double planned;

  /// その時刻に近い実際の記録（±[kPlanMatchMinutes]分以内）。無ければ null。
  final EmotionEntry? actual;

  const PlanComparison({required this.hour, required this.planned, this.actual});

  /// 実際 − 予定。実際の記録が無ければ null。
  double? get diff => actual == null ? null : actual!.valence - planned;
}

/// 予定の時刻と実際の記録を結びつけるときの許容幅（分）。
const int kPlanMatchMinutes = 30;

/// 予定の各点に、一番近い時刻の実際の記録を結びつける。
List<PlanComparison> comparePlan(DayPlan plan, List<EmotionEntry> entries) {
  return [
    for (final p in plan.points)
      PlanComparison(
        hour: p.hour,
        planned: p.valence,
        actual: _nearestEntry(entries, p.hour * 60),
      ),
  ];
}

EmotionEntry? _nearestEntry(List<EmotionEntry> entries, int minutes) {
  EmotionEntry? best;
  var bestDiff = kPlanMatchMinutes + 1;
  for (final e in entries) {
    final m = e.minutes;
    if (m == null) continue;
    final diff = (m - minutes).abs();
    if (diff <= kPlanMatchMinutes && diff < bestDiff) {
      best = e;
      bestDiff = diff;
    }
  }
  return best;
}

/// 振り返りの一言。突き合わせできた点が無ければ null。
///
/// 予定より良かった／悪かったを、平均のずれで伝える。0.5 未満は「ほぼ予定どおり」。
String? planReflection(List<PlanComparison> comparisons) {
  final diffs = [for (final c in comparisons) ?c.diff];
  if (diffs.isEmpty) return null;
  final mean = diffs.reduce((a, b) => a + b) / diffs.length;
  final n = diffs.length;
  if (mean.abs() < 0.5) {
    return '$n点のうち、気分はおおむね予定どおりでした。';
  }
  final word = mean > 0 ? '良い' : '沈んだ';
  return '$n点で見ると、予定より平均 ${mean.abs().toStringAsFixed(1)} ぶん$word一日でした。';
}
