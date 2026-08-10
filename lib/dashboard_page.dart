import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'activity.dart';
import 'diary.dart';
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

  // 日記。保存ボタン方式なので「保存済みの本文」を持っておき、
  // 入力中の本文と突き合わせて未保存かどうかを判定する。
  final TextEditingController _diaryController = TextEditingController();
  String _savedDiaryText = '';
  DateTime? _diaryUpdatedAt;
  bool _diaryExists = false; // createdAt を初回だけ付けるための判定
  bool _diaryLoadError = false; // 日記だけ読めなかった（上書き事故を避けて保存を止める）
  bool _savingDiary = false;

  @override
  void initState() {
    super.initState();
    // 文字数と保存ボタンの活性を入力に追従させる。
    _diaryController.addListener(_onDiaryChanged);
    _fetch();
  }

  @override
  void dispose() {
    _diaryController.removeListener(_onDiaryChanged);
    _diaryController.dispose();
    super.dispose();
  }

  void _onDiaryChanged() => setState(() {});

  bool get _isToday => formatDay(_date) == formatDay(DateTime.now());

  /// 未保存の変更があるか（保存ボタンの活性・離脱ガードに使う）。
  bool get _diaryDirty => _diaryController.text != _savedDiaryText;

  /// 表示中の日付の記録と日記を Firestore から1回取得する（購読はしない）。
  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user =
          FirebaseFirestore.instance.collection('users').doc(widget.username);

      // 感情記録と日記は並行して取得する。日記の失敗でチャートまで消えないよう、
      // 日記側は自前でエラーを受け止める（_fetchDiary を参照）。
      final emotionsFuture = user
          .collection('emotions')
          .where('day', isEqualTo: formatDay(_date))
          .get();
      final diaryFuture = _fetchDiary(user);

      final emotionSnap = await emotionsFuture;
      final entries = emotionSnap.docs
          .map((d) => EmotionEntry.fromMap(d.data()))
          .whereType<EmotionEntry>()
          .toList()
        // ソートは time 文字列の昇順・クライアント側で行う（要件書 §2.1）。
        ..sort((a, b) => a.time.compareTo(b.time));

      final diary = await diaryFuture;

      if (!mounted) return;
      setState(() {
        _entries = entries;
        _diaryExists = diary != null;
        _savedDiaryText = diary?.text ?? '';
        _diaryController.text = _savedDiaryText;
        _diaryUpdatedAt = diary?.updatedAt;
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

  /// 日記を1件読む。ドキュメントIDが日付なのでクエリは不要。
  ///
  /// ここで失敗しても例外を投げず null を返し、[_diaryLoadError] を立てる。
  /// 日記が読めないだけでチャートや履歴まで見られなくなるのを避けるため。
  /// ただし読めなかった内容を空のまま上書きしてしまわないよう、
  /// この場合は保存を止める（カード側でその旨を出す）。
  Future<DiaryEntry?> _fetchDiary(
    DocumentReference<Map<String, dynamic>> user,
  ) async {
    try {
      final snap = await user.collection('diaries').doc(diaryDocId(_date)).get();
      _diaryLoadError = false;
      final data = snap.data();
      if (data == null) return null; // まだ書かれていない日
      return DiaryEntry.fromMap(
        data,
        updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      );
    } catch (e) {
      debugPrint('日記の取得に失敗（記録の表示は続行）: $e');
      _diaryLoadError = true;
      return null;
    }
  }

  /// 日記を保存する（同じ日は常に同じ1件を上書きする）。
  Future<void> _saveDiary() async {
    if (_savingDiary) return;
    final text = _diaryController.text;
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;

    setState(() => _savingDiary = true);
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.username)
          .collection('diaries')
          .doc(diaryDocId(_date))
          .set({
        'day': formatDay(_date),
        'text': text,
        // createdAt は初回だけ。以後は updatedAt のみ更新する。
        if (!_diaryExists) 'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      setState(() {
        _savedDiaryText = text;
        _diaryExists = true;
        _diaryUpdatedAt = DateTime.now();
        _savingDiary = false;
      });
      messenger.showSnackBar(const SnackBar(content: Text('日記を保存しました')));
    } catch (e) {
      debugPrint('日記の保存に失敗: $e');
      if (!mounted) return;
      setState(() => _savingDiary = false);
      messenger.showSnackBar(
        SnackBar(
          content: const Text('日記の保存に失敗しました'),
          backgroundColor: errorColor,
        ),
      );
    }
  }

  /// 未保存の日記があるとき、破棄してよいか確認する。
  /// 保存ボタン方式なので、書きかけのまま日付を移動して消える事故を防ぐ。
  Future<bool> _confirmDiscardIfDirty() async {
    if (!_diaryDirty) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('保存していない日記があります'),
        content: const Text('このまま移動すると、書きかけの内容は失われます。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('このまま残る'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('破棄して移動'),
          ),
        ],
      ),
    );
    return discard == true;
  }

  Future<void> _moveDay(int delta) async {
    if (!await _confirmDiscardIfDirty()) return;
    if (!mounted) return;
    setState(() {
      _date = DateTime(_date.year, _date.month, _date.day + delta);
    });
    _fetch();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 書きかけがあるときは戻るを止めて確認をはさむ。
      canPop: !_diaryDirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _confirmDiscardIfDirty() && mounted) {
          if (context.mounted) Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(title: Text('ダッシュボード（${widget.username}）')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: _buildBody(),
          ),
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
        // 範囲外の記録があることを隠さず知らせる（件数・平均には入っている）。
        if (outOfChartRangeCount(_entries) > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'グラフは${chartRangeLabel()}の範囲です。'
              'この範囲外の記録が${outOfChartRangeCount(_entries)}件あります（下の一覧に出ています）。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: 16),
        // 日記はチャートのすぐ下（履歴の上）。グラフを見ながら書けるようにする。
        DiaryCard(
          controller: _diaryController,
          entries: _entries,
          dirty: _diaryDirty,
          saving: _savingDiary,
          loadError: _diaryLoadError,
          updatedAt: _diaryUpdatedAt,
          onSave: _saveDiary,
        ),
        const SizedBox(height: 16),
        if (_entries.isNotEmpty) _HistoryList(entries: _entries),
      ],
    );
  }
}

/// 日記カード。表示中の日付の日記を書く／書き直す。
///
/// 保存は明示的な「保存」ボタンのみ（自動保存はしない）。未保存のときだけ
/// ボタンが有効になり、その旨も文言で示す。
class DiaryCard extends StatelessWidget {
  final TextEditingController controller;

  /// その日の感情記録。カード右上に絵文字を並べて、入力中でも
  /// その日の起伏を思い出せるようにする。
  final List<EmotionEntry> entries;

  final bool dirty; // 未保存の変更があるか
  final bool saving;

  /// 日記の読み込みに失敗したか。書かれている内容を空で上書きしてしまう
  /// おそれがあるので、この間は保存させない。
  final bool loadError;

  final DateTime? updatedAt;
  final VoidCallback onSave;

  const DiaryCard({
    super.key,
    required this.controller,
    required this.entries,
    required this.dirty,
    required this.saving,
    this.loadError = false,
    required this.updatedAt,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = controller.text.characters.length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.menu_book_outlined,
                    size: 18, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text('この日の日記', style: theme.textTheme.titleSmall),
                const SizedBox(width: 12),
                // 記録が多い日は右端（最新）を見せたまま横スクロールできる。
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    child: Row(
                      children: [
                        for (final e in entries)
                          Padding(
                            padding: const EdgeInsets.only(left: 2),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: EmojiImage(
                                item: emojiItemByName(e.name) ??
                                    EmojiItem(
                                      emoji: e.emoji,
                                      name: e.name,
                                      valence: e.valence,
                                      arousal: e.arousal,
                                    ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              maxLines: null,
              minLines: 4,
              enabled: !loadError,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: '今日はどんな一日でしたか？',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text('$count 文字', style: theme.textTheme.bodySmall),
                const Spacer(),
                Flexible(
                  child: Text(
                    _statusText(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: dirty ? theme.colorScheme.primary : null,
                    ),
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  // 未保存のときだけ押せる（＝二重保存や無意味な書き込みを防ぐ）。
                  // 読み込みに失敗した日は、既存の内容を消さないよう保存させない。
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

  String _statusText() {
    if (loadError) return '日記を読み込めませんでした';
    if (saving) return '保存中…';
    if (dirty) return '未保存の変更があります';
    if (updatedAt != null) return '最終更新 ${formatUpdatedAt(updatedAt!)}';
    return 'まだ書かれていません';
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

const double _leftPad = 24; // 縦軸ラベル分（スクロールしても固定）
const double _labelPad = 22; // 横軸ラベル分
const double _lanePad = 34; // 行動レーン分（行動が1件も無い日は0）
const double _plotHeight = 278; // 折れ線の描画領域の高さ
const int _tickIntervalHours = 1; // 目盛りは1時間おき

/// 感情推移チャート（要件書 §F2）。
/// CustomPaint で折れ線と目盛りを描き、絵文字マーカーは Positioned で重ねる。
///
/// 横軸は 0:00〜24:00・1分=1px で**固定**し、画面に入らない分は横スクロールする。
/// 画面幅に合わせて伸縮させていた頃は、狭い画面ほど1時間あたりの幅が縮んで
/// マーカーが重なり、重なり回避で本来の時刻から大きくずれていた。縮尺と範囲を
/// 固定したことで、同じ時刻は常に同じ位置に来る（日をまたいだ比較もできる）。
/// 縦軸ラベルはスクロール領域の外に置くので常に見える。
class EmotionChart extends StatefulWidget {
  final List<EmotionEntry> entries;
  final int? peakIndex;

  const EmotionChart({super.key, required this.entries, this.peakIndex});

  @override
  State<EmotionChart> createState() => _EmotionChartState();
}

class _EmotionChartState extends State<EmotionChart> {
  late final ScrollController _controller = ScrollController(
    // 開いた直後に最初の記録が見えるようにする（0:00 の空白から始めない）。
    initialScrollOffset: initialScrollOffset(widget.entries),
  );

  @override
  void didUpdateWidget(EmotionChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 日付を切り替えたら、その日の最初の記録が見える位置に戻す。
    if (!identical(oldWidget.entries, widget.entries)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_controller.hasClients) return;
        final max = _controller.position.maxScrollExtent;
        _controller.jumpTo(initialScrollOffset(widget.entries).clamp(0.0, max));
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// この日に行動が1件でも記録されていれば行動レーンを出す。
  bool get _hasActivity => widget.entries.any((e) => e.activity != null);

  double get _height =>
      _plotHeight + _labelPad + (_hasActivity ? _lanePad : 0);

  @override
  Widget build(BuildContext context) {
    const range = kChartRange;
    const plotHeight = _plotHeight;
    const plotWidth = kChartPlotWidth;

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
          // チャート本体。24時間ぶんの固定幅なので常に横スクロールになる。
          Expanded(
            child: Builder(builder: (context) {
              // 時刻 → x（時刻不明・範囲外の記録はチャートから除外）。
              final plotted = [
                for (final e in widget.entries)
                  if (isInChartRange(e)) e,
              ];
              var xs = [
                for (final e in plotted) timeToX(e.minutes!, range, plotWidth),
              ];
              // 30分より近い記録だけ、真の時刻を中心に左右対称へ広げる。
              xs = spreadSymmetric(xs, kMarkerSize);
              final ys = [
                for (final e in plotted) valenceToY(e.valence, plotHeight),
              ];

              // 目盛りの時刻とx座標。
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

              return SingleChildScrollView(
                controller: _controller,
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
    final peak = widget.peakIndex;
    if (peak == null) return false;
    return identical(widget.entries[peak], plotted[i]);
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
