import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'activity.dart';
import 'emoji.dart';
import 'emotion_analysis.dart';

/// 折れ線の色（要件書 §F2: コーラル系）。
const Color kLineColor = Color(0xFFF0997B);

/// チャート上の絵文字マーカーの大きさ（px）。小さいほど時間の分解能が上がる。
const double kMarkerSize = 30;

/// 行動レーンのアイコンの大きさ（px）。感情マーカーより一回り小さくする。
const double kActivitySize = 26;

/// ダッシュボード画面：1日の感情推移チャート＋サマリー＋履歴（要件書 §3）。
class DashboardPage extends StatefulWidget {
  final String username;

  const DashboardPage({super.key, required this.username});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  DateTime _date = DateTime.now(); // 表示中の日付（デフォルトは今日）
  bool _loading = true;
  String? _error; // 取得失敗時のメッセージ
  List<EmotionEntry> _entries = const [];

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  bool get _isToday => formatDay(_date) == formatDay(DateTime.now());

  /// 表示中の日付の記録を Firestore から1回取得する（リアルタイム購読はしない）。
  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // day フィールドの文字列一致で1日分を取得（要件書 §2.1）。
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.username)
          .collection('emotions')
          .where('day', isEqualTo: formatDay(_date))
          .get();

      final entries = snap.docs
          .map((d) => EmotionEntry.fromMap(d.data()))
          .whereType<EmotionEntry>()
          .toList()
        // ソートは time 文字列の昇順・クライアント側で行う（要件書 §2.1）。
        ..sort((a, b) => a.time.compareTo(b.time));

      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (e) {
      debugPrint('記録の取得に失敗: $e');
      if (!mounted) return;
      setState(() {
        _error = '記録の読み込みに失敗しました';
        _loading = false;
      });
    }
  }

  void _moveDay(int delta) {
    setState(() {
      _date = DateTime(_date.year, _date.month, _date.day + delta);
    });
    _fetch();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('ダッシュボード（${widget.username}）')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      // エラー時はインライン表示＋再読み込みボタン（要件書 §4）。
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _fetch,
              icon: const Icon(Icons.refresh),
              label: const Text('再読み込み'),
            ),
          ],
        ),
      );
    }

    final estimate = estimateMood(_entries);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _DateNavigator(
          date: _date,
          canGoNext: !_isToday,
          onPrev: () => _moveDay(-1),
          onNext: () => _moveDay(1),
        ),
        const SizedBox(height: 12),
        _SummaryCards(entries: _entries, estimate: estimate),
        const SizedBox(height: 16),
        if (_entries.isEmpty)
          // 空状態（要件書 §F5）。
          const SizedBox(
            height: 200,
            child: Center(child: Text('この日の記録はありません')),
          )
        else
          EmotionChart(entries: _entries, peakIndex: estimate.peakIndex),
        const SizedBox(height: 16),
        if (_entries.isNotEmpty) _HistoryList(entries: _entries),
      ],
    );
  }
}

/// 日付ナビゲーション（要件書 §F4）。
class _DateNavigator extends StatelessWidget {
  final DateTime date;
  final bool canGoNext; // 未来日ガード：今日なら翌日へは進めない
  final VoidCallback onPrev;
  final VoidCallback onNext;

  const _DateNavigator({
    required this.date,
    required this.canGoNext,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          onPressed: onPrev,
          icon: const Icon(Icons.chevron_left),
          tooltip: '前日',
        ),
        Text(
          formatDayWithWeekday(date),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        IconButton(
          onPressed: canGoNext ? onNext : null, // 無効化で未来日をガード
          icon: const Icon(Icons.chevron_right),
          tooltip: '翌日',
        ),
      ],
    );
  }
}

/// サマリーカード3枚（要件書 §F3）。
class _SummaryCards extends StatelessWidget {
  final List<EmotionEntry> entries;
  final MoodEstimate estimate;

  const _SummaryCards({required this.entries, required this.estimate});

  @override
  Widget build(BuildContext context) {
    final avg = averageValence(entries);
    final peakItem = estimate.peakIndex == null
        ? null
        : emojiItemByName(entries[estimate.peakIndex!].name);

    return Row(
      children: [
        Expanded(
          child: _SummaryCard(
            title: '今日の記録数',
            child: Text('${entries.length} 件',
                style: Theme.of(context).textTheme.titleLarge),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SummaryCard(
            title: '推定感情',
            child: entries.isEmpty
                ? Text('−', style: Theme.of(context).textTheme.titleLarge)
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (peakItem != null)
                        SizedBox(
                          width: 28,
                          height: 28,
                          child: EmojiImage(item: peakItem),
                        ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          estimate.mood.labelJa,
                          style: Theme.of(context).textTheme.titleMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SummaryCard(
            title: '平均 Valence',
            child: Text(
              avg == null ? '−' : avg.toStringAsFixed(1),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SummaryCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          children: [
            Text(title, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 6),
            child,
          ],
        ),
      ),
    );
  }
}

/// 感情推移チャート（要件書 §F2）。
/// CustomPaint で折れ線と目盛りを描き、絵文字マーカーは Positioned で重ねる。
/// 「1時間あたりの最小幅」を保証し、画面が狭いときはチャート部分だけ横スクロールする
/// （時刻比例の配置をスマホ幅でも保つため）。縦軸ラベルは左に固定。
class EmotionChart extends StatelessWidget {
  final List<EmotionEntry> entries;
  final int? peakIndex;

  const EmotionChart({super.key, required this.entries, this.peakIndex});

  static const double _leftPad = 24; // 縦軸ラベル分（スクロールしても固定）
  static const double _labelPad = 22; // 横軸ラベル分
  static const double _lanePad = 34; // 行動レーン分（行動が1件も無い日は0）
  static const double _plotHeight = 278; // 折れ線の描画領域の高さ
  static const double _minPxPerHour = 24; // 1時間あたりの最小幅
  static const int _tickIntervalHours = 3; // 目盛りは3時間おき

  /// この日に行動が1件でも記録されていれば行動レーンを出す。
  bool get _hasActivity => entries.any((e) => e.activity != null);

  double get _height =>
      _plotHeight + _labelPad + (_hasActivity ? _lanePad : 0);

  @override
  Widget build(BuildContext context) {
    final range = chartTimeRange(entries);
    const plotHeight = _plotHeight;

    return SizedBox(
      height: _height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 縦軸ラベル（2, 5, 8）。スクロール領域の外なので常に見える。
          SizedBox(
            width: _leftPad,
            height: _height,
            child: Stack(
              children: [
                for (final v in const [2.0, 5.0, 8.0])
                  Positioned(
                    left: 0,
                    top: valenceToY(v, plotHeight) - 7,
                    child: Text('${v.toInt()}', style: _axisStyle(context)),
                  ),
              ],
            ),
          ),
          // チャート本体。狭ければ横スクロール。
          Expanded(
            child: LayoutBuilder(builder: (context, constraints) {
              final hours = (range.endMin - range.startMin) / 60.0;
              // 画面にフィットする幅と、時間比例を保てる最小幅の大きい方を採用。
              final fitWidth = constraints.maxWidth - kMarkerSize;
              final minWidth = hours * _minPxPerHour;
              final plotWidth = fitWidth > minWidth ? fitWidth : minWidth;

              // 時刻 → x（時刻不明の記録はチャートから除外）。
              final plotted = [
                for (final e in entries)
                  if (e.minutes != null) e,
              ];
              var xs = [
                for (final e in plotted) timeToX(e.minutes!, range, plotWidth),
              ];
              // 数分差の連続記録の重なり回避：真の時刻を中心に左右対称へ広げる。
              xs = spreadSymmetric(xs, kMarkerSize);
              final ys = [
                for (final e in plotted) valenceToY(e.valence, plotHeight),
              ];

              // 目盛りの時刻（3時間おき）とx座標。
              final tickHours = [
                for (var h = range.startMin ~/ 60;
                    h <= range.endMin ~/ 60;
                    h += _tickIntervalHours)
                  h,
              ];
              final tickXs = [
                for (final h in tickHours) timeToX(h * 60, range, plotWidth),
              ];

              // 重なり回避で右へはみ出した分も含めた実コンテンツ幅。
              final lastX = xs.isEmpty ? 0.0 : xs.last;
              final contentWidth =
                  (plotWidth > lastX ? plotWidth : lastX) + kMarkerSize;

              final chart = SizedBox(
                width: contentWidth,
                height: _height,
                child: Stack(
                  children: [
                    // 折れ線と目盛り線（絵文字の背面）。
                    Positioned(
                      left: kMarkerSize / 2,
                      top: 0,
                      child: CustomPaint(
                        size: Size(contentWidth - kMarkerSize, plotHeight),
                        painter:
                            _ChartPainter(xs: xs, ys: ys, tickXs: tickXs),
                      ),
                    ),
                    // 横軸ラベル。
                    for (var t = 0; t < tickHours.length; t++)
                      Positioned(
                        left: kMarkerSize / 2 + tickXs[t] - 12,
                        top: plotHeight + 4,
                        child:
                            Text('${tickHours[t]}時', style: _axisStyle(context)),
                      ),
                    // 絵文字マーカー（前面）。ピークはリングで強調。
                    for (var i = 0; i < plotted.length; i++)
                      Positioned(
                        left: xs[i],
                        top: ys[i] - kMarkerSize / 2,
                        child: Tooltip(
                          message:
                              '${plotted[i].time}  valence ${plotted[i].valence}',
                          child: Container(
                            width: kMarkerSize,
                            height: kMarkerSize,
                            decoration: _isPeak(plotted, i)
                                ? BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: kLineColor.withValues(alpha: 0.8),
                                      width: 2.5,
                                    ),
                                  )
                                : null,
                            padding: const EdgeInsets.all(2),
                            child: EmojiImage(
                              item: emojiItemByName(plotted[i].name) ??
                                  EmojiItem(
                                    emoji: plotted[i].emoji,
                                    name: plotted[i].name,
                                    valence: plotted[i].valence,
                                    arousal: plotted[i].arousal,
                                  ),
                            ),
                          ),
                        ),
                      ),
                    // 行動レーン：感情マーカーと同じx座標に、そのとき何をしていたかを並べる。
                    // 行動が未入力の記録はここに何も置かない（縦の対応で読ませる）。
                    if (_hasActivity)
                      for (var i = 0; i < plotted.length; i++)
                        if (activityItemByName(plotted[i].activity)
                            case final act?)
                          Positioned(
                            left: xs[i] + (kMarkerSize - kActivitySize) / 2,
                            top: plotHeight + _labelPad + 2,
                            child: Tooltip(
                              message: '${plotted[i].time}  ${act.labelJa}',
                              child: SizedBox(
                                width: kActivitySize,
                                height: kActivitySize,
                                child: ActivityImage(
                                  item: act,
                                  fallbackFontSize: 18,
                                ),
                              ),
                            ),
                          ),
                  ],
                ),
              );

              // フィットするならそのまま、狭ければ横スクロール。
              if (contentWidth <= constraints.maxWidth) return chart;
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: chart,
              );
            }),
          ),
        ],
      ),
    );
  }

  /// entries 全体でのピークが、チャート表示対象 plotted の i 番目かどうか。
  bool _isPeak(List<EmotionEntry> plotted, int i) {
    if (peakIndex == null) return false;
    return identical(entries[peakIndex!], plotted[i]);
  }

  TextStyle _axisStyle(BuildContext context) => TextStyle(
        fontSize: 11,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
      );
}

/// 折れ線＋薄い目盛り線（水平: valence 2/5/8、垂直: 3時間おき）を描くペインタ。
class _ChartPainter extends CustomPainter {
  final List<double> xs;
  final List<double> ys;
  final List<double> tickXs; // 垂直目盛り線のx座標

  _ChartPainter({required this.xs, required this.ys, required this.tickXs});

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = const Color(0x14000000) // ごく薄い黒
      ..strokeWidth = 1;

    // 水平の目盛り線（valence 2, 5, 8）。
    for (final v in const [2.0, 5.0, 8.0]) {
      final y = valenceToY(v, size.height);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    // 垂直の目盛り線（3時間おき）。時間の対応を追いやすくする。
    for (final x in tickXs) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }

    // コーラルの折れ線（マーカーの背面）。
    if (xs.length >= 2) {
      final line = Paint()
        ..color = kLineColor
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      final path = Path()..moveTo(xs[0], ys[0]);
      for (var i = 1; i < xs.length; i++) {
        path.lineTo(xs[i], ys[i]);
      }
      canvas.drawPath(path, line);
    }
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.xs != xs || old.ys != ys || old.tickXs != tickXs;
}

/// 入力履歴リスト（要件書 §F6）：時刻降順。リスト内スクロールは作らない。
class _HistoryList extends StatelessWidget {
  final List<EmotionEntry> entries;

  const _HistoryList({required this.entries});

  @override
  Widget build(BuildContext context) {
    final desc = entries.reversed.toList(); // entries は時刻昇順なので反転
    return Card(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('この日の記録',
                  style: Theme.of(context).textTheme.titleSmall),
            ),
          ),
          for (final e in desc) _HistoryTile(entry: e),
        ],
      ),
    );
  }
}

/// 履歴の1行。時刻・絵文字・valence に加え、行動が入力されていればそれも出す。
class _HistoryTile extends StatelessWidget {
  final EmotionEntry entry;

  const _HistoryTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final act = activityItemByName(entry.activity);

    return ListTile(
      dense: true,
      leading: SizedBox(
        width: 28,
        height: 28,
        child: EmojiImage(
          item: emojiItemByName(entry.name) ??
              EmojiItem(
                emoji: entry.emoji,
                name: entry.name,
                valence: entry.valence,
                arousal: entry.arousal,
              ),
        ),
      ),
      title: Text(entry.time),
      subtitle: act == null
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: ActivityImage(item: act, fallbackFontSize: 12),
                ),
                const SizedBox(width: 4),
                Text(act.labelJa),
              ],
            ),
      trailing: Text('valence ${entry.valence}'),
    );
  }
}
