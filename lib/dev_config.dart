/// 開発用ダッシュボードのパスワードの照合用の値。
///
/// 空のままだと開発用ダッシュボードは開けない（「未設定」と出る）。
/// 設定するには、Mac で次を実行してパスワードを入れ、表示された1行で
/// 下の行を置き換える（パスワード自体はどこにも保存されない）。
///
///   dart run tools/dev_password_hash.dart
const String kDevPasswordVerifier = 'f3bd6bab3bea31d6b71e5b1220c1efa911716c13c1e95551d8160178fb5d5c35';
