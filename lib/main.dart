import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'activity.dart';
import 'dashboard_page.dart';
import 'emoji.dart';
import 'emotion_analysis.dart';
import 'firebase_options.dart';

// 絵文字・行動データと共通ウィジェットは別ファイルに分離した。
// 既存の import 'main.dart' 利用箇所（テスト等）のために再公開する。
export 'activity.dart';
export 'emoji.dart';

Future<void> main() async {
  // Firebaseの初期化はrunApp前に1回だけ行う。
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const EmoNikkiApp());
}

class EmoNikkiApp extends StatelessWidget {
  const EmoNikkiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Emo Nikki',
      debugShowCheckedModeBanner: false, // 右上の DEBUG 帯を非表示
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const HomeGate(),
    );
  }
}

/// shared_preferences に保存するときのキー。
const String kUsernameKey = 'username';

/// 直近で URL の `?u=` から取り込んだ名前を覚えておくキー。
/// これがあるおかげで「リンクで開いたあと画面で名前を変更 → リロード」しても
/// 変更が URL に巻き戻されない（同じ `?u=` は一度きり反映する）。
const String kLastUrlUsernameKey = 'lastUrlUsername';

/// URL の `?u=` からユーザー名を取り出す。無い・空なら null。
String? usernameFromUrl(Uri uri) {
  final u = uri.queryParameters['u']?.trim();
  return (u == null || u.isEmpty) ? null : u;
}

/// URL の `?u=` と保存済みの値から、実際に使う名前を決める。
///
/// - 新しい `?u=` が来たらそれを採用する（参加者への配布リンク／端末を変えた・
///   ブラウザのデータが消えたときの復帰リンクとして機能する）
/// - 前回と同じ `?u=` なら、あとから画面で変更した名前のほうを優先する
({String? username, bool persistUrlName}) resolveUsername({
  required String? fromUrl,
  required String? saved,
  required String? lastUrl,
}) {
  if (fromUrl != null && fromUrl != lastUrl) {
    return (username: fromUrl, persistUrlName: true);
  }
  return (username: saved, persistUrlName: false);
}

/// 参加者に配る個人用リンク（`https://.../?u=名前`）を組み立てる。
String buildPersonalLink(Uri base, String username) =>
    base.replace(queryParameters: {'u': username}).toString();

/// Step 2: ユーザー名ゲート。
/// 起動時に shared_preferences から名前を読み、
/// - 未設定なら [NameInputPage]（名前入力画面）
/// - 設定済みなら [EmojiGridPage]（グリッド）
/// を表示する。リロードしても名前が残るので、2回目以降は直接グリッドが出る。
class HomeGate extends StatefulWidget {
  const HomeGate({super.key});

  @override
  State<HomeGate> createState() => _HomeGateState();
}

class _HomeGateState extends State<HomeGate> {
  bool _loading = true; // 名前の読み込み中
  String? _username; // null/空 = 未設定

  @override
  void initState() {
    super.initState();
    _loadUsername();
  }

  Future<void> _loadUsername() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(kUsernameKey);
    final resolved = resolveUsername(
      fromUrl: usernameFromUrl(Uri.base),
      saved: (saved != null && saved.isNotEmpty) ? saved : null,
      lastUrl: prefs.getString(kLastUrlUsernameKey),
    );

    // リンクから来た名前は、次回以降オフラインでも使えるよう保存しておく。
    if (resolved.persistUrlName && resolved.username != null) {
      await prefs.setString(kUsernameKey, resolved.username!);
      await prefs.setString(kLastUrlUsernameKey, resolved.username!);
    }

    if (!mounted) return;
    setState(() {
      _username = resolved.username;
      _loading = false;
    });
  }

  /// 名前入力画面から登録されたとき。保存してグリッドへ。
  Future<void> _onRegister(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kUsernameKey, name);
    if (!mounted) return;
    setState(() => _username = name);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_username == null) {
      return NameInputPage(onRegister: _onRegister);
    }
    return EmojiGridPage(
      username: _username!,
      onChangeUsername: _onRegister, // 変更も「保存して切り替え」なので同じ処理
    );
  }
}

/// 初回だけ表示する名前入力画面。
class NameInputPage extends StatefulWidget {
  /// 登録ボタンが押され、名前が空でないときに呼ばれる。
  final Future<void> Function(String name) onRegister;

  const NameInputPage({super.key, required this.onRegister});

  @override
  State<NameInputPage> createState() => _NameInputPageState();
}

class _NameInputPageState extends State<NameInputPage> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) return; // 空のときは何もしない
    widget.onRegister(name);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('お名前を入力')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '記録に使うお名前を入力してください。\n（次回からは入力不要です）',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _controller,
                  decoration: const InputDecoration(
                    labelText: 'お名前',
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(), // Enterでも登録
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _submit,
                  child: const Text('登録'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 絵文字グリッド画面。タップ→確認→（位置情報付き）Firestore保存まで行う。
class EmojiGridPage extends StatefulWidget {
  /// ゲートを通過したユーザー名（保存先パスに使う）。
  final String username;

  /// 名前が変更されたとき。保存して画面を切り替えるのは呼び出し側の責任。
  final Future<void> Function(String name)? onChangeUsername;

  const EmojiGridPage({
    super.key,
    required this.username,
    this.onChangeUsername,
  });

  @override
  State<EmojiGridPage> createState() => _EmojiGridPageState();
}

class _EmojiGridPageState extends State<EmojiGridPage> {
  bool _saving = false; // 保存中フラグ（二重タップ防止＋インジケータ表示）

  /// 絵文字タップ時：確認＋行動選択ダイアログを出し、「記録」が押されたら保存する。
  Future<void> _onEmojiTap(EmojiItem item) async {
    if (_saving) return; // Step 6: 保存中はタップを無視（二重送信防止）

    // null = キャンセル。activity は未選択なら null（行動の入力は任意）。
    final result = await showDialog<({ActivityItem? activity})>(
      context: context,
      builder: (context) => _ConfirmDialog(item: item),
    );

    if (result == null) return;
    if (!mounted) return;
    final activity = result.activity;

    // await をまたいでも安全なように、context 依存の値を先に取得しておく。
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    setState(() => _saving = true); // Step 6: くるくる表示ON
    try {
      final now = DateTime.now();

      // Step 5: 保存直前に現在地を取得（失敗しても null のまま続行）。
      final loc = await tryGetLatLng();

      // 記録データを組み立てて lat/lng を上書きする。
      final record = buildEmotionRecord(item, now: now, activity: activity)
        ..['lat'] = loc.lat
        ..['lng'] = loc.lng;
      debugPrint('--- 記録データ（保存先: users/${widget.username}/emotions） ---');
      debugPrint(record.toString());

      final col = FirebaseFirestore.instance
          .collection('users')
          .doc(widget.username)
          .collection('emotions');

      // 誤タップ/選び直し対策：同じ日の5分以内の記録があれば「上書き」する。
      // 取得に失敗しても新規追加へフォールバックする。
      String? targetId;
      try {
        final today = await col.where('day', isEqualTo: record['day']).get();
        final existing = [
          for (final d in today.docs)
            (
              id: d.id,
              minutes: d.data()['time'] is String
                  ? timeToMinutes(d.data()['time'] as String)
                  : null,
            ),
        ];
        targetId = pickRecentDuplicateId(existing, now.hour * 60 + now.minute);
      } catch (e) {
        debugPrint('既存記録の確認に失敗（新規追加にフォールバック）: $e');
      }

      final payload = {...record, 'createdAt': FieldValue.serverTimestamp()};
      if (targetId != null) {
        // 直近の記録を上書き（1件にまとめる）。
        await col.doc(targetId).set(payload);
        debugPrint('Firestore の直近記録を上書きしました');
      } else {
        await col.add(payload);
        debugPrint('Firestore に保存しました');
      }

      messenger.showSnackBar(
        SnackBar(
          content: Text(targetId != null ? '記録を更新しました' : '記録を保存しました'),
        ),
      );
    } catch (e) {
      // Step 6: 保存失敗時のフィードバック。
      debugPrint('保存に失敗: $e');
      messenger.showSnackBar(
        SnackBar(
          content: const Text('保存に失敗しました'),
          backgroundColor: errorColor,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false); // くるくる表示OFF
    }
  }

  /// 名前の確認・変更と、個人用リンクのコピーを行うダイアログを開く。
  Future<void> _openAccountDialog() async {
    final messenger = ScaffoldMessenger.of(context);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => _AccountDialog(username: widget.username),
    );
    if (newName == null || newName == widget.username) return;

    await widget.onChangeUsername?.call(newName);
    messenger.showSnackBar(
      SnackBar(content: Text('$newName に切り替えました')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('今の気分は？（${widget.username}）'),
        actions: [
          // ダッシュボード画面への遷移（ダッシュボード要件書 §F1）。
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: 'ダッシュボード',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DashboardPage(username: widget.username),
                ),
              );
            },
          ),
          if (widget.onChangeUsername != null)
            IconButton(
              icon: const Icon(Icons.manage_accounts),
              tooltip: '名前とリンク',
              onPressed: _openAccountDialog,
            ),
        ],
      ),
      body: Stack(
        children: [
          Center(
            child: ConstrainedBox(
              // Webの広い画面でも横に伸びすぎないよう最大幅を制限する。
              constraints: const BoxConstraints(maxWidth: 480),
              child: GridView.count(
                crossAxisCount: 3, // 3列
                padding: const EdgeInsets.all(16),
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                children: [
                  for (final item in kEmojiList)
                    EmojiTile(
                      item: item,
                      onTap: () => _onEmojiTap(item),
                    ),
                ],
              ),
            ),
          ),
          // Step 6: 保存中は半透明オーバーレイ＋くるくるで操作をブロック。
          if (_saving)
            const ModalBarrier(dismissible: false, color: Colors.black45),
          if (_saving) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}

/// 2桁ゼロ埋め（例: 5 -> "05"）。
String _two(int n) => n.toString().padLeft(2, '0');

/// 要件書 第4章のフィールドを組み立てる。
/// lat/lng は呼び出し側で上書きする（createdAt は保存直前に付ける）。
/// [activity] は任意入力なので、未選択なら `activity` フィールドは null になる。
Map<String, dynamic> buildEmotionRecord(
  EmojiItem item, {
  DateTime? now,
  ActivityItem? activity,
}) {
  final t = now ?? DateTime.now();
  return {
    'day': '${t.year}/${_two(t.month)}/${_two(t.day)}', // yyyy/MM/dd
    'time': '${_two(t.hour)}:${_two(t.minute)}', // HH:mm
    'emoji': item.emoji,
    'name': item.name,
    'valence': item.valence,
    'arousal': item.arousal,
    'activity': activity?.name,
    'lat': null,
    'lng': null,
  };
}

/// 現在地の緯度経度を取得する（Step 5）。
/// 権限拒否・取得失敗・タイムアウトのいずれでも例外を投げず (null, null) を返す。
/// → 位置情報が取れなくても記録の保存は止めない、という要件のため。
Future<({double? lat, double? lng})> tryGetLatLng() async {
  try {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission(); // ブラウザの許可ダイアログ
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return (lat: null, lng: null); // 拒否されたら null のまま続行
    }
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: Duration(seconds: 10), // 取得が長引いたら諦める
      ),
    );
    return (lat: pos.latitude, lng: pos.longitude);
  } catch (e) {
    debugPrint('位置情報の取得に失敗（null のまま続行）: $e');
    return (lat: null, lng: null);
  }
}

/// 名前の確認・変更と、個人用リンクのコピーを行うダイアログ。
///
/// 「変更」で新しい名前を返し、キャンセル/画面外タップでは null を返す。
/// ブラウザのデータが消えても、ここでコピーしたリンクを開けば元の名前に戻れる。
class _AccountDialog extends StatefulWidget {
  final String username;

  const _AccountDialog({required this.username});

  @override
  State<_AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<_AccountDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.username);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) return; // 空では変更させない
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    final link = buildPersonalLink(Uri.base, widget.username);

    return AlertDialog(
      title: const Text('名前とリンク'),
      content: SizedBox(
        width: 320,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _controller,
                decoration: const InputDecoration(
                  labelText: 'お名前',
                  border: OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 8),
              Text(
                '名前を変えると、その名前の記録に切り替わります。'
                'これまでの記録が消えることはありません（元の名前に戻せば また表示されます）。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const Divider(height: 24),
              Text(
                'この端末のデータが消えても、次のリンクを開けば元の名前で再開できます。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              SelectableText(
                link,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: link));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('リンクをコピーしました')),
                    );
                  },
                  icon: const Icon(Icons.link),
                  label: const Text('リンクをコピー'),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('閉じる'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('変更'),
        ),
      ],
    );
  }
}

/// 絵文字タップ後の確認ダイアログ。選んだ気分の確認と、行動の選択を1画面で行う。
///
/// 「記録」で `(activity: 選んだ行動 or null)` を返し、キャンセル/画面外タップでは
/// null を返す。行動の入力は任意なので、未選択のままでも記録できる。
class _ConfirmDialog extends StatefulWidget {
  final EmojiItem item;

  const _ConfirmDialog({required this.item});

  @override
  State<_ConfirmDialog> createState() => _ConfirmDialogState();
}

class _ConfirmDialogState extends State<_ConfirmDialog> {
  ActivityItem? _selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('この気分で記録しますか？'),
      content: SizedBox(
        width: 320,
        // 画面が低いときはダイアログ内容ごとスクロールさせる。
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 72,
                height: 72,
                child: EmojiImage(item: widget.item), // 選んだ絵文字を大きく表示
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '何をしていましたか？（任意）',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: 8),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                  mainAxisExtent: 64,
                ),
                itemCount: kActivityList.length,
                itemBuilder: (context, i) {
                  final activity = kActivityList[i];
                  final selected = _selected?.name == activity.name;
                  return InkWell(
                    borderRadius: BorderRadius.circular(8),
                    // もう一度タップで選択解除（間違えて選んでも戻せる）。
                    onTap: () => setState(
                      () => _selected = selected ? null : activity,
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        color: selected ? scheme.primaryContainer : null,
                        border: Border.all(
                          color: selected ? scheme.primary : Colors.transparent,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 30,
                            height: 30,
                            child: ActivityImage(
                              item: activity,
                              fallbackFontSize: 22,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            activity.labelJa,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight:
                                  selected ? FontWeight.bold : FontWeight.normal,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, (activity: _selected)),
          child: const Text('記録'),
        ),
      ],
    );
  }
}

/// 絵文字1個分のタイル。タップできる。
class EmojiTile extends StatelessWidget {
  final EmojiItem item;
  final VoidCallback? onTap;

  const EmojiTile({super.key, required this.item, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: EmojiImage(item: item),
        ),
      ),
    );
  }
}

