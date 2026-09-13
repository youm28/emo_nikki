/// Web 以外（テストなど）向けのスタブ。Google マップは使えない。
library;

import 'package:flutter/foundation.dart';

/// キーの認証に失敗したときの理由（Web 以外では常に null）。
final ValueNotifier<String?> googleMapsAuthError = ValueNotifier(null);

Future<void> loadGoogleMaps(String apiKey) =>
    Future.error(UnsupportedError('Google マップは Web でのみ使えます'));
