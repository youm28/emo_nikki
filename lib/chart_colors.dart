/// グラフの線の色。記録のグラフ（dashboard_page.dart）と
/// 予定のグラフ（plan_card.dart）の両方から使うので、1か所にまとめる。
library;

import 'package:flutter/material.dart';

/// 実際の記録の線（要件書 §F2: コーラル系）。
const Color kLineColor = Color(0xFFF0997B);

/// 明日の予定の線。実際の記録と並べたときに見分けられるよう、別系統の色にする。
const Color kPlanColor = Color(0xFF6C7BF0);
