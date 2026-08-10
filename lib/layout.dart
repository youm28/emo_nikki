/// 画面幅にまつわる共通の決まりごと。
///
/// このアプリはスマホで使うことを前提に作ってあり、iPhone 12 Pro（幅390px）で
/// ちょうど良く見えるように各所の余白やマーカーの大きさを決めている。
/// パソコンのブラウザで開くと幅が1920pxまで伸びてしまい、
/// サマリーカード1枚が600px以上になったり、318pxしかないチャートの右に
/// 1500px超の空白ができたりして、同じ画面とは思えない見た目になっていた。
///
/// そこで「本文の最大幅」を決めて中央に寄せる。スマホの幅はこれより狭いので
/// 従来の見た目はそのまま、広い画面だけが変わる。
library;

import 'package:flutter/material.dart';

/// 本文の最大幅。これより広い画面では中央に寄せて余白にする。
///
/// 480 は登録・ホーム画面で先に使っていた値に合わせてある。画面ごとに
/// 違う幅にすると、ホームとダッシュボードを行き来したときに本文の幅が
/// 変わってしまうため、1か所で決めて両方から参照する。
const double kMaxContentWidth = 480;

/// 本文を [kMaxContentWidth] に収めて中央に寄せる。
///
/// ホーム画面とダッシュボードで同じ物を使う。それぞれが自前で Center と
/// ConstrainedBox を書くと、片方だけ直したときに幅がずれるため。
class ContentWidth extends StatelessWidget {
  final Widget child;

  const ContentWidth({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kMaxContentWidth),
          child: child,
        ),
      );
}
