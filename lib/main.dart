import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dashboard_page.dart';
import 'emoji.dart';
import 'firebase_options.dart';

// 絵文字データと共通ウィジェットは emoji.dart に分離した。
// 既存の import 'main.dart' 利用箇所（テスト等）のために再公開する。
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
    setState(() {
      _username = (saved != null && saved.isNotEmpty) ? saved : null;
      _loading = false;
    });
  }

  /// 名前入力画面から登録されたとき。保存してグリッドへ。
  Future<void> _onRegister(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kUsernameKey, name);
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
    return EmojiGridPage(username: _username!);
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

  const EmojiGridPage({super.key, required this.username});

  @override
  State<EmojiGridPage> createState() => _EmojiGridPageState();
}

class _EmojiGridPageState extends State<EmojiGridPage> {
  bool _saving = false; // 保存中フラグ（二重タップ防止＋インジケータ表示）

  /// 絵文字タップ時：確認ダイアログを出し、「記録」が押されたら保存する。
  Future<void> _onEmojiTap(EmojiItem item) async {
    if (_saving) return; // Step 6: 保存中はタップを無視（二重送信防止）

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('この気分で記録しますか？'),
        content: SizedBox(
          width: 96,
          height: 96,
          child: EmojiImage(item: item), // 選んだ絵文字を大きく表示
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('記録'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    // await をまたいでも安全なように、context 依存の値を先に取得しておく。
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    setState(() => _saving = true); // Step 6: くるくる表示ON
    try {
      // Step 5: 保存直前に現在地を取得（失敗しても null のまま続行）。
      final loc = await tryGetLatLng();

      // 記録データを組み立てて lat/lng を上書きする。
      final record = buildEmotionRecord(item)
        ..['lat'] = loc.lat
        ..['lng'] = loc.lng;
      debugPrint('--- 記録データ（保存先: users/${widget.username}/emotions） ---');
      debugPrint(record.toString());

      // Step 4: Firestore に1件追加（users/{username}/emotions/{自動ID}）。
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.username)
          .collection('emotions')
          .add({
        ...record,
        'createdAt': FieldValue.serverTimestamp(),
      });
      debugPrint('Firestore に保存しました');

      messenger.showSnackBar(
        const SnackBar(content: Text('記録を保存しました')),
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
/// Step 3 では lat/lng は null、createdAt は付けない（Step 4/5 で追加）。
Map<String, dynamic> buildEmotionRecord(EmojiItem item, {DateTime? now}) {
  final t = now ?? DateTime.now();
  return {
    'day': '${t.year}/${_two(t.month)}/${_two(t.day)}', // yyyy/MM/dd
    'time': '${_two(t.hour)}:${_two(t.minute)}', // HH:mm
    'emoji': item.emoji,
    'name': item.name,
    'valence': item.valence,
    'arousal': item.arousal,
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

