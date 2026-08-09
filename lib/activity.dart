import 'package:flutter/material.dart';

/// 1件の行動データ（感情と一緒に記録する「そのとき何をしていたか」）。
class ActivityItem {
  final String name; // 画像ファイル名（拡張子なし）。保存時の `activity` フィールドになる
  final String labelJa; // 選択画面・履歴での表示名
  final String emoji; // 画像が無いときのフォールバック表示用

  const ActivityItem({
    required this.name,
    required this.labelJa,
    required this.emoji,
  });

  /// 画像のアセットパス（`assets/activity_list/{name}.png`）。
  String get assetPath => 'assets/activity_list/$name.png';
}

/// 行動リスト（17種・固定）。並びは一日の流れと使用頻度を意識した順。
/// ラベルを変えたいときはこの labelJa を書き換えるだけでよい。
const List<ActivityItem> kActivityList = [
  ActivityItem(name: 'work', labelJa: '仕事', emoji: '💼'),
  ActivityItem(name: 'memo', labelJa: '勉強', emoji: '📝'),
  ActivityItem(name: 'train', labelJa: '移動', emoji: '🚃'),
  ActivityItem(name: 'sara', labelJa: '食事', emoji: '🍽️'),
  ActivityItem(name: 'kohi', labelJa: '休憩', emoji: '☕'),
  ActivityItem(name: 'houki', labelJa: '家事', emoji: '🧹'),
  ActivityItem(name: 'kaimono', labelJa: '買い物', emoji: '🛒'),
  ActivityItem(name: 'tv', labelJa: 'テレビ', emoji: '📺'),
  ActivityItem(name: 'me', labelJa: 'スマホ', emoji: '👀'),
  ActivityItem(name: 'wifi', labelJa: 'ネット', emoji: '📶'),
  ActivityItem(name: 'gita', labelJa: '趣味', emoji: '🎸'),
  ActivityItem(name: 'soccer', labelJa: 'スポーツ', emoji: '⚽'),
  ActivityItem(name: 'mattyo', labelJa: '筋トレ', emoji: '💪'),
  ActivityItem(name: 'hato', labelJa: '人と会う', emoji: '💗'),
  ActivityItem(name: 'ohuro', labelJa: 'お風呂', emoji: '🛁'),
  ActivityItem(name: 'zzz', labelJa: '睡眠', emoji: '💤'),
  ActivityItem(name: 'byouin', labelJa: '通院', emoji: '🏥'),
];

/// `name`（画像ファイル名）から行動マスタを引く。未選択・未知の name は null。
ActivityItem? activityItemByName(String? name) {
  if (name == null) return null;
  for (final item in kActivityList) {
    if (item.name == name) return item;
  }
  return null;
}

/// PNG画像があれば画像、無ければUnicode絵文字を表示する共通ウィジェット。
/// 選択ダイアログ・ダッシュボードの行動レーン・履歴で共用する。
class ActivityImage extends StatelessWidget {
  final ActivityItem item;
  final double fallbackFontSize;

  const ActivityImage({
    super.key,
    required this.item,
    this.fallbackFontSize = 24,
  });

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      item.assetPath,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        return Center(
          child: Text(
            item.emoji,
            style: TextStyle(fontSize: fallbackFontSize),
          ),
        );
      },
    );
  }
}
