import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';

Future<FirebaseApp>? _initializing;

/// Firebase の準備（1回だけ行う）。Firestore を使う直前に必ず await する。
///
/// 以前は main() で準備が終わるまで runApp しておらず、その間は画面が何も
/// 出なかった。Firebase が要るのは記録の保存やダッシュボードの読み込みのとき
/// だけなので、起動時は準備を始めるだけにして先に絵文字の画面を出す。
/// 何度呼んでも初期化は1回で、2回目以降は同じ結果を待つだけになる。
Future<void> ensureFirebase() =>
    _initializing ??= Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
