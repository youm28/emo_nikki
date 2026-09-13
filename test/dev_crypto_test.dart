// 開発用パスワードから作る値のテスト。

import 'package:flutter_test/flutter_test.dart';

import 'package:emo_nikki/dev_crypto.dart';

void main() {
  // テストでは計算の回数を減らして速くする（仕組みは同じ）。
  ({String verifier, String dataKey}) keys(String pw) =>
      deriveDevKeys(pw, rounds: 10);

  test('同じパスワードからは毎回同じ値ができる', () {
    expect(keys('correct horse battery'), keys('correct horse battery'));
  });

  test('パスワードが1文字違えば、どちらの値も変わる', () {
    final a = keys('correct horse battery');
    final b = keys('correct horse batterz');
    expect(a.verifier, isNot(b.verifier));
    expect(a.dataKey, isNot(b.dataKey));
  });

  test('照合用の値と保存場所の鍵は別物（アプリの中身から鍵は分からない）', () {
    final k = keys('correct horse battery');
    expect(k.verifier, isNot(k.dataKey));
  });

  test('どちらも64桁の16進数（Firestore のルールで長さを確かめている）', () {
    final k = keys('correct horse battery');
    final hex64 = RegExp(r'^[0-9a-f]{64}$');
    expect(k.verifier, matches(hex64));
    expect(k.dataKey, matches(hex64));
  });

  test('計算を重ねる回数が違えば値も変わる（回数も鍵の一部）', () {
    expect(
      deriveDevKeys('correct horse battery', rounds: 10),
      isNot(deriveDevKeys('correct horse battery', rounds: 11)),
    );
  });
}
