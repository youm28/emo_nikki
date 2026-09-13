/// Web 以外（テストなど）向けのスタブ。Google マップは Web でしか表示できない。
library;

import 'package:flutter/material.dart';

import 'google_map_view.dart';

class GoogleMapView extends StatelessWidget {
  final String apiKey;
  final List<GoogleMapPin> pins;
  final String mapTypeId;

  const GoogleMapView({
    super.key,
    required this.apiKey,
    required this.pins,
    required this.mapTypeId,
  });

  @override
  Widget build(BuildContext context) =>
      const Center(child: Text('Google マップは Web でのみ表示できます'));
}
