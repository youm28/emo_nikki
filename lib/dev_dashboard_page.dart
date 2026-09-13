/// 開発用ダッシュボード（試作）。パスワードを入れた端末でだけ開ける。
///
/// 参加者が使う本番のダッシュボードとは完全に別の画面で、次を試す場所:
///   - 地図：その日どこで何を記録したか（記録の緯度・経度から）
///   - 写真：記録のあとに撮った写真
///   - 試作用の日記：地図と写真を見ながら書く。本番の日記とは別に保存する
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'dev_access.dart';
import 'dev_photos.dart';
import 'diary.dart';
import 'emoji.dart';
import 'emotion_analysis.dart';
import 'firebase_ready.dart';
import 'google_map_view.dart';
import 'layout.dart';

/// Google マップの API キー。コードや GitHub には書かず、起動・ビルドのときに
/// `--dart-define-from-file=dart_defines.json` で渡す（dart_defines.json は Git 管理外）。
/// 渡されなかったときは空になり、Google の地図は選べない（ほかの地図は使える）。
const String kGoogleMapsApiKey = String.fromEnvironment('GOOGLE_MAPS_API_KEY');

/// パスワードを入れてもらう。正しければ保存場所の鍵を返し、この端末に覚える。
Future<String?> showDevUnlockDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (context) => const _UnlockDialog(),
  );
}

class _UnlockDialog extends StatefulWidget {
  const _UnlockDialog();

  @override
  State<_UnlockDialog> createState() => _UnlockDialogState();
}

class _UnlockDialogState extends State<_UnlockDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _error;
  bool _checking = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _checking = true;
      _error = null;
    });
    // 計算を何万回も重ねるので少し時間がかかる。くるくるを出してから計算する。
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final key = unlockDev(_controller.text);
    if (!mounted) return;
    if (key == null) {
      setState(() {
        _checking = false;
        _error = 'パスワードが違います';
      });
      return;
    }
    await saveDevKey(key);
    if (mounted) Navigator.pop(context, key);
  }

  @override
  Widget build(BuildContext context) {
    if (!isDevPasswordConfigured) {
      return AlertDialog(
        title: const Text('開発用ダッシュボード'),
        content: const Text(
          'パスワードがまだ設定されていません。\n'
          'Mac で dart run tools/dev_password_hash.dart を実行して、'
          'lib/dev_config.dart に設定してください。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('閉じる'),
          ),
        ],
      );
    }
    return AlertDialog(
      title: const Text('開発用ダッシュボード'),
      // 入力欄には説明を付けない（何の画面かを見せないため）。
      content: TextField(
        controller: _controller,
        obscureText: true,
        autofocus: true,
        enabled: !_checking,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          errorText: _error,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: _checking ? null : () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: _checking ? null : _submit,
          child: _checking
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('開く'),
        ),
      ],
    );
  }
}

/// 地図の種類（Google マップの mapTypeId）。
/// 出典（Google のロゴと著作権表示）は Google が自動で出し、消せない。
const List<({String label, String type})> _mapTypes = [
  (label: 'Google 地図', type: 'roadmap'),
  (label: 'Google 航空写真', type: 'hybrid'),
];

/// 記録1件（地図に置くために緯度・経度も持つ）。位置の無い記録は point が null。
class _Spot {
  final EmotionEntry entry;
  final ({double lat, double lng})? point;

  const _Spot(this.entry, this.point);
}

EmojiItem _emojiOf(EmotionEntry e) =>
    emojiItemByName(e.name) ??
    EmojiItem(emoji: e.emoji, name: e.name, valence: e.valence, arousal: e.arousal);

class DevDashboardPage extends StatefulWidget {
  final String username;
  final String dataKey;

  const DevDashboardPage({
    super.key,
    required this.username,
    required this.dataKey,
  });

  @override
  State<DevDashboardPage> createState() => _DevDashboardPageState();
}

class _DevDashboardPageState extends State<DevDashboardPage> {
  DateTime _date = DateTime.now();
  bool _loading = true;
  String? _error;
  List<_Spot> _spots = const [];
  List<DevPhoto> _photos = const [];

  final TextEditingController _diary = TextEditingController();
  bool _savingDiary = false;

  // 地図の見た目（比べるための切り替え）。
  String _mapType = _mapTypes.first.type;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _diary.dispose();
    super.dispose();
  }

  bool get _isToday => formatDay(_date) == formatDay(DateTime.now());

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ensureFirebase();
      final day = formatDay(_date);
      final emotionsFuture = FirebaseFirestore.instance
          .collection('users')
          .doc(widget.username)
          .collection('emotions')
          .where('day', isEqualTo: day)
          .get();
      final photosFuture = fetchPhotos(
        dataKey: widget.dataKey,
        username: widget.username,
        day: day,
      );
      final diaryFuture = devDiaryDoc(
        dataKey: widget.dataKey,
        username: widget.username,
        docDay: diaryDocId(_date),
      ).get();

      final spots = <_Spot>[];
      for (final d in (await emotionsFuture).docs) {
        final data = d.data();
        final entry = EmotionEntry.fromMap(data);
        if (entry == null) continue;
        final lat = data['lat'];
        final lng = data['lng'];
        spots.add(_Spot(
          entry,
          lat is num && lng is num ? (lat: lat.toDouble(), lng: lng.toDouble()) : null,
        ));
      }
      spots.sort((a, b) => a.entry.time.compareTo(b.entry.time));
      final photos = await photosFuture;
      final diary = (await diaryFuture).data();

      if (!mounted) return;
      setState(() {
        _spots = spots;
        _photos = photos;
        _diary.text = diary?['text'] as String? ?? '';
        _loading = false;
      });
    } catch (e) {
      debugPrint('開発用ダッシュボードの読み込みに失敗: $e');
      if (!mounted) return;
      setState(() {
        _error = '読み込みに失敗しました\n$e';
        _loading = false;
      });
    }
  }

  void _moveDay(int delta) {
    setState(() => _date = DateTime(_date.year, _date.month, _date.day + delta));
    _fetch();
  }

  Future<void> _saveDiary() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _savingDiary = true);
    try {
      await ensureFirebase();
      await devDiaryDoc(
        dataKey: widget.dataKey,
        username: widget.username,
        docDay: diaryDocId(_date),
      ).set({
        'username': widget.username,
        'day': formatDay(_date),
        'text': _diary.text,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      messenger.showSnackBar(const SnackBar(content: Text('試作の日記を保存しました')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('保存に失敗しました: $e')));
    } finally {
      if (mounted) setState(() => _savingDiary = false);
    }
  }

  Future<void> _lock() async {
    await clearDevKey();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _openPhoto(DevPhoto photo) async {
    final delete = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.memory(photo.bytes, fit: BoxFit.contain),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Text(photo.time),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('削除'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('閉じる'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (delete != true) return;
    await deletePhoto(dataKey: widget.dataKey, id: photo.id);
    _fetch();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('開発用（${widget.username}）'),
        actions: [
          IconButton(
            // 入口のボタンが鍵のアイコンなので、こちらは「出る」形にして区別する。
            icon: const Icon(Icons.logout),
            tooltip: 'ロックする（この端末から鍵を消す）',
            onPressed: _lock,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SelectableText(_error!),
              const SizedBox(height: 12),
              FilledButton(onPressed: _fetch, child: const Text('再読み込み')),
            ],
          ),
        ),
      );
    }
    final theme = Theme.of(context);
    return ContentWidth(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: () => _moveDay(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              Text(formatDayWithWeekday(_date), style: theme.textTheme.titleMedium),
              IconButton(
                onPressed: _isToday ? null : () => _moveDay(1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _Section(title: '地図', child: _buildMap()),
          const SizedBox(height: 16),
          _Section(title: '写真（${_photos.length}枚）', child: _buildPhotos()),
          const SizedBox(height: 16),
          _Section(
            title: '試作の日記',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '本番の日記とは別に保存されます。',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _diary,
                  maxLines: null,
                  minLines: 4,
                  decoration: const InputDecoration(
                    hintText: '地図と写真を見ながら書いてみる',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: _savingDiary ? null : _saveDiary,
                    child: const Text('保存'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    if (kGoogleMapsApiKey.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            'Google マップのキーが渡されていません\n'
            '（--dart-define-from-file=dart_defines.json を付けて起動してください）',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final located = [for (final s in _spots) if (s.point != null) s];
    if (located.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: Text('位置のある記録がありません')),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (final t in _mapTypes)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(t.label),
                  selected: t.type == _mapType,
                  onSelected: (_) => setState(() => _mapType = t.type),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 280,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: GoogleMapView(
              // 日付や種類が変わったら作り直す（表示範囲を合わせ直すため）。
              key: ValueKey('$_mapType-${_date.toIso8601String()}'),
              apiKey: kGoogleMapsApiKey,
              mapTypeId: _mapType,
              pins: [
                for (final s in located)
                  GoogleMapPin(
                    lat: s.point!.lat,
                    lng: s.point!.lng,
                    time: s.entry.time,
                    iconAsset: _emojiOf(s.entry).assetPath,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPhotos() {
    if (_photos.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text('写真はまだありません\n（記録するときの「写真も追加」から撮れます）',
              textAlign: TextAlign.center),
        ),
      );
    }
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      children: [
        for (final p in _photos)
          InkWell(
            onTap: () => _openPhoto(p),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.memory(p.bytes, fit: BoxFit.cover),
                ),
                Positioned(
                  left: 4,
                  bottom: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (emojiItemByName(p.emojiName) case final item?)
                          SizedBox(width: 14, height: 14, child: EmojiImage(item: item)),
                        const SizedBox(width: 3),
                        Text(p.time,
                            style: const TextStyle(color: Colors.white, fontSize: 11)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;

  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}
