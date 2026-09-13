/// 開発用ダッシュボードのパスワードから、照合用の値と保存場所の鍵を作る。
///
/// Flutter に依存しない（tools/dev_password_hash.dart からも同じ計算を使うため）。
///
/// 仕組み:
///   - パスワードそのものはアプリにも GitHub にも書かない。
///   - アプリに入れるのは「照合用の値（verifier）」だけ。入力されたパスワードから
///     同じ値が作れたら正しいとみなす。
///   - 写真などの保存場所 `dev/{dataKey}/...` の鍵（dataKey）もパスワードから作る。
///     verifier とは別の計算なので、アプリ本体を読んでも dataKey は分からない。
///     dataKey を知らないと保存場所のパスを組み立てられないので、読み書きできない。
///
/// 弱点:
///   verifier は公開しているアプリ本体に入るので、そこから総当たりで
///   パスワードを探すことはできてしまう。計算を何万回も重ねて1回の試行を
///   重くしてあるが、**短い・よくあるパスワードだと破られる**。長い文にすること。
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// 計算を重ねる回数。多いほど総当たりに強いが、解錠に時間がかかる。
const int kDevHashRounds = 50000;

/// パスワードから (照合用の値, 保存場所の鍵) を作る。どちらも64桁の16進数。
({String verifier, String dataKey}) deriveDevKeys(
  String password, {
  int rounds = kDevHashRounds,
}) {
  var digest = sha256.convert(utf8.encode('emo_nikki/dev/v1:$password')).bytes;
  for (var i = 1; i < rounds; i++) {
    digest = sha256.convert(digest).bytes;
  }
  String tagged(String tag) =>
      sha256.convert([...utf8.encode('$tag:'), ...digest]).toString();
  return (verifier: tagged('verify'), dataKey: tagged('data'));
}
