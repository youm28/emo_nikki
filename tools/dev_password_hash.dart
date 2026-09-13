// 開発用ダッシュボードのパスワードから、lib/dev_config.dart に書く1行を作る。
//
//   dart run tools/dev_password_hash.dart
//
// 入力したパスワードは画面に出ず、どこにも保存されない。表示された1行を
// lib/dev_config.dart の kDevPasswordVerifier の行と置き換える。
// パスワードを忘れると、それまでに保存した写真などは読めなくなる
// （保存場所の鍵もパスワードから作っているため）。

import 'dart:io';

import 'package:emo_nikki/dev_crypto.dart';

void main() {
  stdout.write('パスワード（12文字以上。長い文がおすすめ）: ');
  stdin.echoMode = false;
  final password = stdin.readLineSync() ?? '';
  stdin.echoMode = true;
  stdout.writeln();

  if (password.length < 12) {
    stderr.writeln('12文字以上にしてください。短いと総当たりで破られます。');
    exit(1);
  }

  stdout.write('もう一度: ');
  stdin.echoMode = false;
  final again = stdin.readLineSync() ?? '';
  stdin.echoMode = true;
  stdout.writeln();
  if (again != password) {
    stderr.writeln('一致しませんでした。');
    exit(1);
  }

  final keys = deriveDevKeys(password);
  stdout.writeln();
  stdout.writeln('lib/dev_config.dart の該当行をこれに置き換えてください:');
  stdout.writeln("const String kDevPasswordVerifier = '${keys.verifier}';");
}
