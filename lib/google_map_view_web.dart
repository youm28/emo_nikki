/// Web 向けの実装。Flutter の画面の中に地図用の div を置き、そこへ
/// Maps JavaScript API で地図・絵文字のマーカー・時刻順の線を描く。
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import 'google_map_view.dart';
import 'google_maps_loader.dart';

int _nextViewId = 0;

class GoogleMapView extends StatefulWidget {
  final String apiKey;
  final List<GoogleMapPin> pins; // 時刻順
  final String mapTypeId; // 'roadmap'（地図） / 'hybrid'（航空写真＋地名）

  const GoogleMapView({
    super.key,
    required this.apiKey,
    required this.pins,
    required this.mapTypeId,
  });

  @override
  State<GoogleMapView> createState() => _GoogleMapViewState();
}

class _GoogleMapViewState extends State<GoogleMapView> {
  // 1つの地図ごとに別の名前で登録する（同じ名前だと前の地図が使い回される）。
  final String _viewType = 'emo-google-map-${_nextViewId++}';
  late final Future<void> _ready = _prepare();

  Future<void> _prepare() async {
    await loadGoogleMaps(widget.apiKey);
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) {
      final div = web.HTMLDivElement()
        ..style.width = '100%'
        ..style.height = '100%';
      _drawMap(div);
      return div;
    });
  }

  JSObject get _maps =>
      (globalContext['google'] as JSObject)['maps'] as JSObject;

  JSObject _new(String className, [List<JSAny?> args = const []]) =>
      (_maps[className] as JSFunction).callAsConstructorVarArgs<JSObject>(args);

  JSObject _latLng(GoogleMapPin p) =>
      {'lat': p.lat, 'lng': p.lng}.jsify() as JSObject;

  void _drawMap(web.HTMLDivElement div) {
    final pins = widget.pins;
    final map = _new('Map', [
      div,
      {
        'center': {'lat': pins.first.lat, 'lng': pins.first.lng},
        'zoom': 15,
        'mapTypeId': widget.mapTypeId,
        // 開発用の見比べなので、余計なボタンは出さない（拡大縮小は指でできる）。
        'disableDefaultUI': true,
        'gestureHandling': 'greedy',
      }.jsify(),
    ]);

    for (final p in pins) {
      // マーカーの画像は、アプリに入っている絵文字の画像をそのまま使う。
      final url = ui_web.assetManager.getAssetUrl(p.iconAsset);
      _new('Marker', [
        {
          'position': {'lat': p.lat, 'lng': p.lng},
          'map': map,
          'title': p.time,
          'icon': {
            'url': url,
            'scaledSize': _new('Size', [30.toJS, 30.toJS]),
            'anchor': _new('Point', [15.toJS, 15.toJS]),
          },
        }.jsify(),
      ]);
    }

    if (pins.length >= 2) {
      _new('Polyline', [
        {
          'path': [for (final p in pins) _latLng(p)].jsify(),
          'map': map,
          'strokeColor': '#000000',
          'strokeOpacity': 0.38,
          'strokeWeight': 2,
        }.jsify(),
      ]);
      // 全部の記録が入るように合わせる。
      //
      // 地図の div は作った直後はまだ画面に置かれておらず大きさが0で、その状態で
      // 合わせても効かない（確認用ページで、2件目以降が地図の外に出たままだった）。
      // そこで div の大きさが決まった瞬間に1回だけ合わせる。
      final bounds = _new('LatLngBounds');
      for (final p in pins) {
        bounds.callMethod('extend'.toJS, _latLng(p));
      }
      late final web.ResizeObserver observer;
      observer = web.ResizeObserver(
        ((JSArray<web.ResizeObserverEntry> _, web.ResizeObserver _) {
          if (div.clientWidth == 0 || div.clientHeight == 0) return;
          observer.disconnect();
          map.callMethod('fitBounds'.toJS, bounds, 36.toJS);
        }).toJS,
      );
      observer.observe(div);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: googleMapsAuthError,
      builder: (context, authError, _) {
        if (authError != null) return _message(authError);
        return FutureBuilder<void>(
          future: _ready,
          builder: (context, snap) {
            if (snap.hasError) return _message('${snap.error}');
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            return HtmlElementView(viewType: _viewType);
          },
        );
      },
    );
  }

  Widget _message(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SelectableText(text, textAlign: TextAlign.center),
        ),
      );
}
