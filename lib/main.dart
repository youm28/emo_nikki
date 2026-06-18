import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';

Future<void> main() async {
  // Firebaseの初期化はrunApp前に1回だけ行う。
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const EmoNikkiApp());
}

/// 1件の絵文字データ（要件書 第5章の固定データ）。
class EmojiItem {
  final String emoji; // Unicodeの絵文字（画像が無いときのフォールバック表示用）
  final String name; // 画像ファイル名（拡張子なし）。保存時の `name` フィールドにもなる
  final double valence; // 感情価
  final double arousal; // 覚醒度

  const EmojiItem({
    required this.emoji,
    required this.name,
    required this.valence,
    required this.arousal,
  });

  /// 画像のアセットパス（`assets/emoji_list/{name}.png`）。
  String get assetPath => 'assets/emoji_list/$name.png';
}

/// 要件書 第5章の絵文字リスト（12種・固定）。
const List<EmojiItem> kEmojiList = [
  EmojiItem(emoji: '😰', name: 'AnxiousFaceWithSweat', valence: 2.88, arousal: 6.53),
  EmojiItem(emoji: '😊', name: 'SmilingFaceWithSmilingEyes', valence: 7.75, arousal: 7.03),
  EmojiItem(emoji: '😵', name: 'DizzyFace', valence: 4.04, arousal: 5.93),
  EmojiItem(emoji: '😀', name: 'GrinningFace', valence: 7.51, arousal: 5.87),
  EmojiItem(emoji: '😗', name: 'KissingFace', valence: 4.92, arousal: 4.63),
  EmojiItem(emoji: '😮', name: 'FaceWithOpenMouth', valence: 5.18, arousal: 5.52),
  EmojiItem(emoji: '😩', name: 'WearyFace', valence: 3.02, arousal: 6.31),
  EmojiItem(emoji: '😁', name: 'BeamingFaceWithSmilingEyes', valence: 7.83, arousal: 7.32),
  EmojiItem(emoji: '😢', name: 'CryingFace', valence: 3.56, arousal: 5.58),
  EmojiItem(emoji: '😙', name: 'KissingFaceWithSmilingEyes', valence: 6.58, arousal: 6.00),
  EmojiItem(emoji: '😯', name: 'HushedFace', valence: 5.47, arousal: 5.25),
  EmojiItem(emoji: '🤭', name: 'FaceWithHandOverMouth', valence: 5.70, arousal: 5.43),
];

class EmoNikkiApp extends StatelessWidget {
  const EmoNikkiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Emo Nikki',
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

/// Step 1: 12個の絵文字を3列グリッドで表示する画面。
/// タップ処理はまだ無い（Step 3で追加）。
class EmojiGridPage extends StatelessWidget {
  /// ゲートを通過したユーザー名（後のステップで保存先パスに使う）。
  final String username;

  const EmojiGridPage({super.key, required this.username});

  /// 絵文字タップ時：確認ダイアログを出し、「記録」が押されたらデータを組み立てる。
  Future<void> _onEmojiTap(BuildContext context, EmojiItem item) async {
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

    // Step 5: 保存直前に現在地を取得（失敗しても null のまま続行）。
    final loc = await tryGetLatLng();

    // 記録データを組み立てて lat/lng を上書きする。
    final record = buildEmotionRecord(item)
      ..['lat'] = loc.lat
      ..['lng'] = loc.lng;
    debugPrint('--- 記録データ（保存先: users/$username/emotions） ---');
    debugPrint(record.toString());

    // Step 4: Firestore に1件追加する。
    // パスは users/{username}/emotions/{自動ID}。createdAt はサーバー時刻。
    await FirebaseFirestore.instance
        .collection('users')
        .doc(username)
        .collection('emotions')
        .add({
      ...record,
      'createdAt': FieldValue.serverTimestamp(),
    });
    debugPrint('Firestore に保存しました');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('今の気分は？（$username）')),
      body: Center(
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
                  onTap: () => _onEmojiTap(context, item),
                ),
            ],
          ),
        ),
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

/// PNG画像があれば画像、無ければUnicode絵文字を表示する共通ウィジェット。
/// タイルと確認ダイアログの両方で使う。
class EmojiImage extends StatelessWidget {
  final EmojiItem item;

  const EmojiImage({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      item.assetPath,
      fit: BoxFit.contain,
      // 画像が見つからない/読めないときはUnicode絵文字でフォールバック表示。
      errorBuilder: (context, error, stackTrace) {
        return Center(
          child: Text(item.emoji, style: const TextStyle(fontSize: 40)),
        );
      },
    );
  }
}
