/// 日記のロジック層（純粋関数のみ・Flutter非依存）。
/// ウィジェットから分離してテスト可能にしている。
library;

/// 1日分の日記（Firestoreから読んだもの）。
///
/// 保存先は `users/{username}/diaries/{yyyy-MM-dd}`。
/// ドキュメントIDが日付そのものなので「1日1件」が構造的に保証され、
/// 何度保存しても同じ1件が上書きされる。
class DiaryEntry {
  final String day; // "yyyy/MM/dd"（感情記録の day と同じ表記）
  final String text;
  final DateTime? updatedAt; // 最終更新の表示に使う

  const DiaryEntry({
    required this.day,
    required this.text,
    this.updatedAt,
  });

  /// Firestoreのドキュメントデータから生成。text が無ければ空文字として扱う。
  ///
  /// [updatedAt] は Firestore の Timestamp を DateTime に変換したものを渡す
  /// （このファイルを cloud_firestore に依存させないため）。
  static DiaryEntry fromMap(Map<String, dynamic> data, {DateTime? updatedAt}) {
    final day = data['day'];
    final text = data['text'];
    return DiaryEntry(
      day: day is String ? day : '',
      text: text is String ? text : '',
      updatedAt: updatedAt,
    );
  }
}

/// DateTime → 日記のドキュメントID（`"2026-08-10"`）。
///
/// FirestoreのドキュメントIDに `/` は使えないので、感情記録の `day`
/// （`"2026/08/10"`）とは区切り文字が異なる。表示や照合に使う `day` は
/// ドキュメント側のフィールドに持たせて、両方の表記を保つ。
String diaryDocId(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}';
}

/// 最終更新の表示用（`"21:14"`）。
String formatUpdatedAt(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.hour)}:${two(d.minute)}';
}
