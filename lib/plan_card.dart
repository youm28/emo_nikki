/// 明日の予定（感情と行動の推移）を指で描く画面部品。ロジックは plan.dart。
library;

import 'package:flutter/material.dart';

import 'activity.dart';
import 'chart_colors.dart';
import 'emoji.dart';
import 'emotion_analysis.dart';
import 'plan.dart';

const double _planHeight = 170; // 線を描く領域の高さ
const double _planLabelPad = 18; // 下の時刻ラベル
const double _planLeftPad = 18; // 左の数字ラベル
const double _planMarker = 24; // 絵文字の大きさ

/// 予定を描く／見るグラフ。
///
/// [onChanged] が null なら見るだけ（翌日の振り返り表示に使う）。
/// [actual] を渡すと、実際の記録を重ねて描く。
class PlanChart extends StatelessWidget {
  final List<PlanPoint> points;
  final ValueChanged<List<PlanPoint>>? onChanged;
  final ValueChanged<int>? onLongPressHour; // その時刻の行動を選ばせる
  final List<EmotionEntry> actual;

  const PlanChart({
    super.key,
    required this.points,
    this.onChanged,
    this.onLongPressHour,
    this.actual = const [],
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        // 指で触りやすいよう、画面の幅いっぱいに広げる（記録のグラフと違い、
        // 予定は毎正時の11点だけなので、縮尺を固定する必要がない）。
        final width = constraints.maxWidth - _planLeftPad;
        final plotHeight = _planHeight;

        void update(Offset local) {
          final onChanged = this.onChanged;
          if (onChanged == null) return;
          final x = local.dx - _planLeftPad;
          final hour = planHourFromX(x, width);
          final valence = planValenceFromY(local.dy, plotHeight);
          onChanged(setPlanPoint(points, hour, valence));
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => update(d.localPosition),
          onPanDown: (d) => update(d.localPosition),
          onPanUpdate: (d) => update(d.localPosition),
          onLongPressStart: (d) {
            final onLongPressHour = this.onLongPressHour;
            if (onLongPressHour == null) return;
            onLongPressHour(planHourFromX(d.localPosition.dx - _planLeftPad, width));
          },
          child: SizedBox(
            height: plotHeight + _planLabelPad,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _PlanPainter(
                      points: points,
                      actual: actual,
                      plotHeight: plotHeight,
                      leftPad: _planLeftPad,
                      gridColor: theme.colorScheme.outlineVariant,
                      labelColor: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                // 予定の点（絵文字）。描いた高さに一番近い気分を出す。
                for (final p in points)
                  Positioned(
                    left: _planLeftPad +
                        _xOf(p.hour, width) -
                        _planMarker / 2,
                    top: valenceToY(p.valence, plotHeight) - _planMarker / 2,
                    width: _planMarker,
                    height: _planMarker,
                    child: IgnorePointer(
                      child: EmojiImage(item: emojiForValence(p.valence)),
                    ),
                  ),
                // 予定している行動は、点の下にアイコンだけで出す。
                for (final p in points)
                  if (activityItemByName(p.activity) case final act?)
                    Positioned(
                      left: _planLeftPad + _xOf(p.hour, width) - 7,
                      top: plotHeight - 16,
                      width: 14,
                      height: 14,
                      child: IgnorePointer(
                        child: ActivityImage(item: act, fallbackFontSize: 11),
                      ),
                    ),
              ],
            ),
          ),
        );
      },
    );
  }

  static double _xOf(int hour, double width) {
    final hours = kPlanHours;
    return (hour - hours.first) / (hours.last - hours.first) * width;
  }
}

class _PlanPainter extends CustomPainter {
  final List<PlanPoint> points;
  final List<EmotionEntry> actual;
  final double plotHeight;
  final double leftPad;
  final Color gridColor;
  final Color labelColor;

  _PlanPainter({
    required this.points,
    required this.actual,
    required this.plotHeight,
    required this.leftPad,
    required this.gridColor,
    required this.labelColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width - leftPad;
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;

    // 縦軸の目盛り（2・5・8）と、2時間おきの縦線。
    for (final v in [2.0, 5.0, 8.0]) {
      final y = valenceToY(v, plotHeight);
      canvas.drawLine(Offset(leftPad, y), Offset(size.width, y), grid);
      _label(canvas, '${v.toInt()}', Offset(0, y - 6));
    }
    for (final hour in kPlanHours) {
      if ((hour - kPlanHours.first) % 2 != 0) continue;
      final x = leftPad + PlanChart._xOf(hour, width);
      canvas.drawLine(Offset(x, 0), Offset(x, plotHeight), grid);
      _label(canvas, '$hour', Offset(x - 7, plotHeight + 2));
    }

    // 実際の記録（重ねて見せるとき）。先に描いて予定を手前にする。
    if (actual.isNotEmpty) {
      final line = Paint()
        ..color = kLineColor
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      final path = Path();
      var started = false;
      for (final e in actual) {
        final m = e.minutes;
        if (m == null) continue;
        final x = leftPad +
            (m - kPlanHours.first * 60) /
                ((kPlanHours.last - kPlanHours.first) * 60) *
                width;
        final y = valenceToY(e.valence, plotHeight);
        started ? path.lineTo(x, y) : path.moveTo(x, y);
        started = true;
        canvas.drawCircle(Offset(x, y), 3, Paint()..color = kLineColor);
      }
      canvas.drawPath(path, line);
    }

    // 予定の線（点が2つ以上のときだけ）。
    if (points.length >= 2) {
      final path = Path();
      for (final (i, p) in points.indexed) {
        final x = leftPad + PlanChart._xOf(p.hour, width);
        final y = valenceToY(p.valence, plotHeight);
        i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = kPlanColor
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );
    }
  }

  void _label(Canvas canvas, String text, Offset at) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: 10, color: labelColor),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(_PlanPainter old) =>
      old.points != points || old.actual != actual;
}

/// 「明日の予定」を描いて保存するカード。
class PlanCard extends StatelessWidget {
  final DateTime planDate; // 予定を立てる日（ふつうは明日）
  final List<PlanPoint> points;
  final ValueChanged<List<PlanPoint>> onChanged;
  final VoidCallback onSave;
  final VoidCallback onClear;
  final bool saving;
  final bool dirty;

  /// 予定の読み込みに失敗したか。描きかけを空で上書きしないよう保存を止める。
  final bool loadError;

  const PlanCard({
    super.key,
    required this.planDate,
    required this.points,
    required this.onChanged,
    required this.onSave,
    required this.onClear,
    required this.saving,
    required this.dirty,
    this.loadError = false,
  });

  Future<void> _pickActivity(BuildContext context, int hour) async {
    final current = points.where((p) => p.hour == hour).firstOrNull;
    if (current == null) return; // まだ点が無い時刻は何もしない
    final picked = await showModalBottomSheet<ActivityItem?>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('$hour時の予定', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final a in kActivityList)
                    InkWell(
                      onTap: () => Navigator.pop(context, a),
                      child: Semantics(
                        label: a.labelJa,
                        child: SizedBox(
                          width: 34,
                          height: 34,
                          child: ActivityImage(item: a, fallbackFontSize: 24),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('行動を外す'),
              ),
            ],
          ),
        ),
      ),
    );
    onChanged(setPlanActivity(points, hour, picked?.name));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.timeline, size: 18, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text('明日（${formatDayWithWeekday(planDate)}）の予定',
                    style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              'グラフを指でなぞって、明日の気分の移り変わりを描いてみましょう。'
              '点を長押しすると、その時間の行動も選べます。',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            if (loadError)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '予定を読み込めませんでした（保存もできません）',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error),
                ),
              ),
            PlanChart(
              points: points,
              onChanged: loadError ? null : onChanged,
              onLongPressHour: (hour) => _pickActivity(context, hour),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text('${points.length} / ${kPlanHours.length} 点',
                    style: theme.textTheme.bodySmall),
                const Spacer(),
                TextButton(
                  onPressed: points.isEmpty ? null : onClear,
                  child: const Text('消す'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: (dirty && !saving && !loadError) ? onSave : null,
                  child: saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('保存'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 立てた予定と、その日の実際の記録を見比べるカード。
class PlanReviewCard extends StatelessWidget {
  final DayPlan plan;
  final List<EmotionEntry> entries;

  const PlanReviewCard({super.key, required this.plan, required this.entries});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final comparisons = comparePlan(plan, entries);
    final reflection = planReflection(comparisons);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.compare_arrows,
                    size: 18, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text('予定と実際', style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                _Legend(color: kPlanColor, label: '予定'),
                const SizedBox(width: 12),
                _Legend(color: kLineColor, label: '実際'),
              ],
            ),
            const SizedBox(height: 8),
            PlanChart(points: plan.points, actual: entries),
            if (reflection != null) ...[
              const SizedBox(height: 8),
              Text(reflection, style: theme.textTheme.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;

  const _Legend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 14, height: 3, color: color),
          const SizedBox(width: 4),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}
