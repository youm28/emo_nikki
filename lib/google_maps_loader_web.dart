/// Web 向けの実装。Maps JavaScript API の script タグをその場で差し込む。
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

/// キーの認証に失敗したときの理由。失敗していなければ null。
///
/// Google は読み込み自体には成功させてから、あとでキーを確かめて
/// `gm_authFailure` を呼ぶ。そのため読み込みの Future とは別に知らせる。
final ValueNotifier<String?> googleMapsAuthError = ValueNotifier(null);

Future<void>? _loading;

/// 1回だけ読み込む。2回目以降は同じ読み込みを待つだけ。
Future<void> loadGoogleMaps(String apiKey) => _loading ??= _load(apiKey);

Future<void> _load(String apiKey) {
  final done = Completer<void>();

  globalContext.setProperty(
    '__emoGoogleMapsReady'.toJS,
    (() {
      if (!done.isCompleted) done.complete();
    }).toJS,
  );
  globalContext.setProperty(
    'gm_authFailure'.toJS,
    (() {
      googleMapsAuthError.value =
          'Google マップのキーが使えませんでした。Google Cloud のコンソールで、'
          'このキーに Maps JavaScript API が許可されているか、'
          '開いているアドレスが許可されているかを確認してください。';
    }).toJS,
  );

  final params = Uri(queryParameters: {
    'key': apiKey,
    'callback': '__emoGoogleMapsReady',
    'language': 'ja',
    'region': 'JP',
    'loading': 'async',
  }).query;
  final script = web.HTMLScriptElement()
    ..src = 'https://maps.googleapis.com/maps/api/js?$params'
    ..async = true;
  script.onerror = ((web.Event _) {
    if (!done.isCompleted) {
      done.completeError(StateError('Google マップを読み込めませんでした（通信エラー）'));
    }
  }).toJS;
  web.document.head!.append(script);

  return done.future.timeout(
    const Duration(seconds: 20),
    onTimeout: () => throw TimeoutException('Google マップの読み込みが20秒で終わりませんでした'),
  );
}
