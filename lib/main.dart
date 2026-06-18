import 'package:flutter/material.dart';

void main() {
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
      home: const EmojiGridPage(),
    );
  }
}

/// Step 1: 12個の絵文字を3列グリッドで静的に表示する画面。
/// タップ処理はまだ無い（Step 3で追加）。
class EmojiGridPage extends StatelessWidget {
  const EmojiGridPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('今の気分は？')),
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
              for (final item in kEmojiList) EmojiTile(item: item),
            ],
          ),
        ),
      ),
    );
  }
}

/// 絵文字1個分のタイル。PNG画像があれば画像、無ければUnicode絵文字を表示する。
class EmojiTile extends StatelessWidget {
  final EmojiItem item;

  const EmojiTile({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Image.asset(
          item.assetPath,
          fit: BoxFit.contain,
          // 画像が見つからない/読めないときはUnicode絵文字でフォールバック表示。
          // これにより assets/emoji_list/ にPNGを置く前でもグリッドが崩れない。
          errorBuilder: (context, error, stackTrace) {
            return Center(
              child: Text(
                item.emoji,
                style: const TextStyle(fontSize: 40),
              ),
            );
          },
        ),
      ),
    );
  }
}
