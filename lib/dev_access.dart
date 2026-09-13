/// 開発用ダッシュボードの解錠状態（この端末に保存する）。
///
/// 一度パスワードを入れると、保存場所の鍵（dataKey）をこの端末に覚えておく。
/// 鍵がある端末では、記録のあとの「写真を追加」と開発用ダッシュボードが使える。
/// 「ロック」を押すと端末から消える。
library;

import 'package:shared_preferences/shared_preferences.dart';

import 'dev_config.dart';
import 'dev_crypto.dart';

const String _prefsKey = 'devDataKey';

/// パスワードが設定されているか（dev_config.dart に照合用の値があるか）。
bool get isDevPasswordConfigured => kDevPasswordVerifier.isNotEmpty;

/// パスワードが正しければ保存場所の鍵を返す。違えば null。
String? unlockDev(String password) {
  if (!isDevPasswordConfigured) return null;
  final keys = deriveDevKeys(password);
  return keys.verifier == kDevPasswordVerifier ? keys.dataKey : null;
}

Future<String?> loadDevKey() async {
  final prefs = await SharedPreferences.getInstance();
  final key = prefs.getString(_prefsKey);
  return (key != null && key.length == 64) ? key : null;
}

Future<void> saveDevKey(String dataKey) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_prefsKey, dataKey);
}

Future<void> clearDevKey() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_prefsKey);
}
