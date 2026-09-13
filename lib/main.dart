import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:shared_preferences/shared_preferences.dart';

import 'activity.dart';
import 'browser_push.dart';
import 'dashboard_page.dart';
import 'dev_access.dart';
// 開発用ダッシュボード（地図の部品を含む）は、開くときにだけ読み込む。
// 参加者を含む全員が毎回ダウンロードするアプリ本体を大きくしないため。
import 'dev_dashboard_page.dart' deferred as dev;
import 'dev_photos.dart';
import 'emoji.dart';
import 'layout.dart';
import 'emotion_analysis.dart';
import 'firebase_ready.dart';
import 'push.dart';
import 'splash.dart';
import 'url_updater.dart';

// 絵文字・行動データと共通ウィジェットは別ファイルに分離した。
// 既存の import 'main.dart' 利用箇所（テスト等）のために再公開する。
export 'activity.dart';
export 'emoji.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Firebase の準備は始めるだけで待たない。待つと、その間は画面が何も
  // 出ないため。使う側（保存・読み込み）が ensureFirebase() で待つ。
  unawaited(
    ensureFirebase().catchError(
      (Object e) => debugPrint('Firebase の準備に失敗（保存時に再試行はしない）: $e'),
    ),
  );
  // 最初の画面が描けたら、index.html の「読み込み中」を消す。
  WidgetsBinding.instance.addPostFrameCallback((_) => removeSplash());
  runApp(const EmoNikkiApp());
}

class EmoNikkiApp extends StatelessWidget {
  const EmoNikkiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Emo日記',
      debugShowCheckedModeBanner: false, // 右上の DEBUG 帯を非表示
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const HomeGate(),
    );
  }
}

/// shared_preferences に保存するときのキー。
const String kUsernameKey = 'username';

/// 直近で URL の `?u=` から取り込んだ名前を覚えておくキー。
/// これがあるおかげで「リンクで開いたあと画面で名前を変更 → リロード」しても
/// 変更が URL に巻き戻されない（同じ `?u=` は一度きり反映する）。
const String kLastUrlUsernameKey = 'lastUrlUsername';

/// URL の `?u=` からユーザー名を取り出す。無い・空なら null。
String? usernameFromUrl(Uri uri) {
  final u = uri.queryParameters['u']?.trim();
  return (u == null || u.isEmpty) ? null : u;
}

/// URL が日記を書くためにダッシュボードを開くよう求めているか
/// （21時の日記の通知は `?open=diary` を付ける）。
bool wantsDiaryFromUrl(Uri uri) => uri.queryParameters['open'] == 'diary';

/// URL の `?u=` と保存済みの値から、実際に使う名前を決める。
///
/// - 新しい `?u=` が来たらそれを採用する（参加者への配布リンク／端末を変えた・
///   ブラウザのデータが消えたときの復帰リンクとして機能する）
/// - 前回と同じ `?u=` なら、あとから画面で変更した名前のほうを優先する
({String? username, bool persistUrlName}) resolveUsername({
  required String? fromUrl,
  required String? saved,
  required String? lastUrl,
}) {
  if (fromUrl != null && fromUrl != lastUrl) {
    return (username: fromUrl, persistUrlName: true);
  }
  return (username: saved, persistUrlName: false);
}

/// 参加者に配る個人用リンク（`https://.../?u=名前`）を組み立てる。
String buildPersonalLink(Uri base, String username) =>
    base.replace(queryParameters: {'u': username}).toString();

/// 登録後にアドレスバーへ反映する相対URL（例 `/?u=p01`）。
/// これでブックマーク／ホーム画面追加が、そのまま復帰用リンクになる。
String personalRoute(String username) =>
    Uri(path: '/', queryParameters: {'u': username}).toString();

/// Step 2: ユーザー名ゲート。
/// 起動時に shared_preferences から名前を読み、
/// - 未設定なら [NameInputPage]（名前入力画面）
/// - 設定済みなら [EmojiGridPage]（グリッド）
/// を表示する。リロードしても名前が残るので、2回目以降は直接グリッドが出る。
class HomeGate extends StatefulWidget {
  const HomeGate({super.key});

  @override
  State<HomeGate> createState() => _HomeGateState();
}

class _HomeGateState extends State<HomeGate> {
  bool _loading = true; // 名前の読み込み中
  String? _username; // null/空 = 未設定
  bool _openDiary = false; // 日記の通知から開かれた（最初にダッシュボードを出す）

  @override
  void initState() {
    super.initState();
    _loadUsername();
  }

  Future<void> _loadUsername() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(kUsernameKey);
    final resolved = resolveUsername(
      fromUrl: usernameFromUrl(Uri.base),
      saved: (saved != null && saved.isNotEmpty) ? saved : null,
      lastUrl: prefs.getString(kLastUrlUsernameKey),
    );

    // リンクから来た名前は、次回以降オフラインでも使えるよう保存しておく。
    if (resolved.persistUrlName && resolved.username != null) {
      await prefs.setString(kUsernameKey, resolved.username!);
      await prefs.setString(kLastUrlUsernameKey, resolved.username!);
    }

    // 日記の通知から来たときは一度だけダッシュボードを開く。?open= はアドレスバー
    // から消しておく（残すと、リロードやホーム画面追加のたびに開いてしまう）。
    final openDiary =
        resolved.username != null && wantsDiaryFromUrl(Uri.base);
    if (openDiary) replaceUrl(personalRoute(resolved.username!));

    if (!mounted) return;
    setState(() {
      _username = resolved.username;
      _openDiary = openDiary;
      _loading = false;
    });
  }

  /// 登録／ログイン画面から名前が確定したとき。保存してグリッドへ。
  Future<void> _onRegister(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kUsernameKey, name);
    await prefs.setString(kLastUrlUsernameKey, name);

    // アドレスバーを個人用リンク（?u=名前）にする。
    // こうしておけば、そのままブックマーク／ホーム画面に追加するだけで
    // 端末のデータが消えたときの復帰リンクになる。
    replaceUrl(personalRoute(name));

    if (!mounted) return;
    setState(() => _username = name);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_username == null) {
      return NameInputPage(onRegister: _onRegister);
    }
    return EmojiGridPage(username: _username!, openDiaryOnStart: _openDiary);
  }
}

/// 登録／ログイン画面。名前が未設定のときだけ表示する。
///
/// はじめての人はここで名前を決め（＝登録）、すでに使っている人は同じ名前を
/// 入れる（＝ログイン）と、その名前の記録に戻れる。
/// 名前はあとから変更できない仕様なので、その旨を画面上でも伝える。
class NameInputPage extends StatefulWidget {
  /// 名前が確定したとき（空でないとき）に呼ばれる。
  final Future<void> Function(String name) onRegister;

  const NameInputPage({super.key, required this.onRegister});

  @override
  State<NameInputPage> createState() => _NameInputPageState();
}

class _NameInputPageState extends State<NameInputPage> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 「はじめる」を押したとき。名前は後から変更できないので、必ず確認してから確定する。
  ///
  /// 確認を挟むのは打ち間違い対策だけでなく、ブラウザのオートフィルが入力欄を
  /// 別の名前（保存済みの氏名など）に書き換えてしまうことがあるため。
  /// 確認画面には「これから使う名前」をそのまま出して、気づけるようにする。
  Future<void> _submit() async {
    final name = _controller.text.trim();
    if (name.isEmpty) return; // 空のときは何もしない
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('このお名前ではじめますか？'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            Text(
              'あとから変更できません。'
              '間違っていたら「入力しなおす」を押してください。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('入力しなおす'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('このお名前ではじめる'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await widget.onRegister(name);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('登録 / ログイン')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'はじめての方は、記録に使うお名前を決めてください。\n'
                  'すでに使っている方は、同じお名前を入れると'
                  'これまでの記録に戻れます。',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _controller,
                  decoration: const InputDecoration(
                    labelText: 'お名前',
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(), // Enterでも確定
                ),
                const SizedBox(height: 8),
                Text(
                  '※お名前はあとから変更できません。'
                  '打ち間違いにご注意ください。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _submit,
                  child: const Text('はじめる'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 絵文字グリッド画面。タップ→確認→（位置情報付き）Firestore保存まで行う。
class EmojiGridPage extends StatefulWidget {
  /// ゲートを通過したユーザー名（保存先パスに使う）。
  final String username;

  /// 開いた直後にダッシュボードへ進むか（日記の通知から来たとき）。
  /// ダッシュボードはこの画面の上に積むので、戻れば記録画面に戻れる。
  final bool openDiaryOnStart;

  const EmojiGridPage({
    super.key,
    required this.username,
    this.openDiaryOnStart = false,
  });

  @override
  State<EmojiGridPage> createState() => _EmojiGridPageState();
}

class _EmojiGridPageState extends State<EmojiGridPage> {
  bool _saving = false; // 保存中フラグ（二重タップ防止＋インジケータ表示）

  // 通知（リマインダー）の許可状態。未許可のときだけ案内を出す。
  PushPermission _push = PushPermission.unsupported;
  bool _enablingPush = false;

  // 開発用の鍵（パスワードを入れた端末でだけ入っている）。
  // これがあるときだけ、記録のあとに「写真を追加」を出す。
  String? _devKey;

  @override
  void initState() {
    super.initState();
    _loadPushPermission();
    _loadDevKey();
    if (widget.openDiaryOnStart) {
      // 画面ができあがってからでないと Navigator に積めない。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openDashboard();
      });
    }
  }

  /// ダッシュボードを上から表示する。日記の通知から来たときも日記欄へは
  /// スクロールしない。日記はチャートのすぐ下にあり、その日の感情の流れを
  /// 見ながら書けるようにしてあるので、チャートを画面の外へ押し出さない。
  void _openDashboard() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DashboardPage(username: widget.username),
      ),
    );
  }

  Future<void> _loadDevKey() async {
    final key = await loadDevKey();
    if (!mounted) return;
    setState(() => _devKey = key);
  }

  /// 開発用ダッシュボード。鍵が無ければ先にパスワードを聞く。
  Future<void> _openDevDashboard() async {
    await dev.loadLibrary(); // 初回だけ通信が発生する（2回目以降はすぐ終わる）
    if (!mounted) return;
    final key = _devKey ?? await dev.showDevUnlockDialog(context);
    if (key == null || !mounted) return;
    setState(() => _devKey = key);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            dev.DevDashboardPage(username: widget.username, dataKey: key),
      ),
    );
    // 開発用ダッシュボードで「ロック」された場合に備えて読み直す。
    _loadDevKey();
  }

  /// 確認画面の「写真も追加」で撮った写真を、保存した記録に付けて保存する。
  /// カメラは確認画面のボタンを押した時点ですでに開いている（[capture]）。
  Future<void> _savePhoto(
    Future<XFile?> capture, {
    required String dataKey,
    required String emotionId,
    required Map<String, dynamic> record,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await savePhoto(
        capture,
        dataKey: dataKey,
        username: widget.username,
        emotionId: emotionId,
        day: record['day'] as String,
        time: record['time'] as String,
        emojiName: record['name'] as String,
      );
      final message = switch (result) {
        PhotoResult.saved => '写真を保存しました',
        PhotoResult.cancelled => null,
        PhotoResult.tooLarge => '写真が大きすぎて保存できませんでした',
      };
      if (message != null) {
        messenger.showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e) {
      debugPrint('写真の保存に失敗: $e');
      messenger.showSnackBar(SnackBar(content: Text('写真の保存に失敗しました: $e')));
    }
  }

  Future<void> _loadPushPermission() async {
    final permission = await currentPushPermission();
    if (!mounted) return;
    setState(() => _push = permission);

    // 通知許可はサイト単位なので、同じ端末で別のIDを開くと
    // 「許可済み」のまま そのIDの宛先が未登録になる。ここで登録し直す。
    if (permission == PushPermission.granted) {
      await registerTokenIfGranted(widget.username);
    }
  }

  /// 「オンにする」を押したとき。ブラウザの許可ダイアログはユーザー操作から
  /// でないと出せないので、必ずここ（ボタンのコールバック）で呼ぶ。
  Future<void> _onEnablePush() async {
    // iOS Safari は「タップから連続した呼び出し」でないと許可ダイアログを
    // 出さない。await を挟む前に、ここで要求を開始する。
    final requested = requestBrowserNotificationPermission();

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _enablingPush = true);

    final permission = fromBrowserPermission(await requested);
    final result = await registerToken(widget.username, permission);
    if (!mounted) return;
    setState(() {
      _push = result.permission;
      _enablingPush = false;
    });

    // 許可はされたのに宛先が登録できなかった場合は、原因が分からないと
    // 手の打ちようがないので、エラーをそのまま読める形で出す。
    if (result.error != null) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('通知の登録に失敗しました'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('通知の許可自体は取れています。下の内容を管理者に伝えてください。'),
                const SizedBox(height: 12),
                SelectableText(
                  result.error!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('閉じる'),
            ),
          ],
        ),
      );
      return;
    }

    final message = switch (result.permission) {
      PushPermission.granted => '通知をオンにしました',
      PushPermission.denied => 'ブラウザで通知がブロックされています。設定から許可してください',
      // ダイアログが出ずに終わった場合。もう一度押せば出ることがある。
      PushPermission.notAsked => '許可のダイアログが表示されませんでした。もう一度お試しください',
      PushPermission.unsupported => 'この環境では通知を使えませんでした',
    };
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  /// 絵文字タップ時：確認＋行動選択ダイアログを出し、「記録」が押されたら保存する。
  Future<void> _onEmojiTap(EmojiItem item) async {
    if (_saving) return; // Step 6: 保存中はタップを無視（二重送信防止）

    // null = キャンセル。activity は未選択なら null（行動の入力は任意）。
    // photo は「写真も追加」を押したときだけ入る（すでにカメラが開いている）。
    final devKey = _devKey;
    final result = await showDialog<ConfirmResult>(
      context: context,
      builder: (context) =>
          _ConfirmDialog(item: item, allowPhoto: devKey != null),
    );

    if (result == null) return;
    if (!mounted) return;
    final activity = result.activity;

    // await をまたいでも安全なように、context 依存の値を先に取得しておく。
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    setState(() => _saving = true); // Step 6: くるくる表示ON
    try {
      final now = DateTime.now();

      // Step 5: 保存直前に現在地を取得（失敗しても null のまま続行）。
      final loc = await tryGetLatLng();

      // 記録データを組み立てて lat/lng を上書きする。
      final record = buildEmotionRecord(item, now: now, activity: activity)
        ..['lat'] = loc.lat
        ..['lng'] = loc.lng;
      debugPrint('--- 記録データ（保存先: users/${widget.username}/emotions） ---');
      debugPrint(record.toString());

      await ensureFirebase(); // 起動直後に押された場合は、ここで準備を待つ
      final col = FirebaseFirestore.instance
          .collection('users')
          .doc(widget.username)
          .collection('emotions');

      // 誤タップ/選び直し対策：同じ日の5分以内の記録があれば「上書き」する。
      // 取得に失敗しても新規追加へフォールバックする。
      String? targetId;
      try {
        final today = await col.where('day', isEqualTo: record['day']).get();
        final existing = [
          for (final d in today.docs)
            (
              id: d.id,
              minutes: d.data()['time'] is String
                  ? timeToMinutes(d.data()['time'] as String)
                  : null,
            ),
        ];
        targetId = pickRecentDuplicateId(existing, now.hour * 60 + now.minute);
      } catch (e) {
        debugPrint('既存記録の確認に失敗（新規追加にフォールバック）: $e');
      }

      final payload = {...record, 'createdAt': FieldValue.serverTimestamp()};
      final String savedId;
      if (targetId != null) {
        // 直近の記録を上書き（1件にまとめる）。
        await col.doc(targetId).set(payload);
        savedId = targetId;
        debugPrint('Firestore の直近記録を上書きしました');
      } else {
        savedId = (await col.add(payload)).id;
        debugPrint('Firestore に保存しました');
      }

      messenger.showSnackBar(
        SnackBar(
          content: Text(targetId != null ? '記録を更新しました' : '記録を保存しました'),
        ),
      );

      // 「写真も追加」だった場合は、撮り終わるのを待って記録に付ける。
      // 記録はすでに保存済みなので、写真で失敗・中止しても記録は残る。
      // 撮影は時間がかかることがあるので、くるくる表示は先に消す（待たない）。
      final photo = result.photo;
      if (photo != null && devKey != null) {
        unawaited(_savePhoto(
          photo,
          dataKey: devKey,
          emotionId: savedId,
          record: record,
        ));
      }
    } catch (e) {
      // Step 6: 保存失敗時のフィードバック。
      debugPrint('保存に失敗: $e');
      messenger.showSnackBar(
        SnackBar(
          content: const Text('保存に失敗しました'),
          backgroundColor: errorColor,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false); // くるくる表示OFF
    }
  }

  /// 名前の確認と、個人用リンクのコピーを行うダイアログを開く（表示専用）。
  void _openAccountDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => _AccountDialog(username: widget.username),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('今の気分は？（${widget.username}）'),
        actions: [
          // ダッシュボード画面への遷移（ダッシュボード要件書 §F1）。
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: 'ダッシュボード',
            onPressed: _openDashboard,
          ),
          // 開発用ダッシュボード（パスワードを入れた人だけ開ける）。
          IconButton(
            icon: const Icon(Icons.lock_outline),
            tooltip: '開発用ダッシュボード',
            onPressed: _openDevDashboard,
          ),
          IconButton(
            icon: const Icon(Icons.manage_accounts),
            tooltip: '名前とリンク',
            onPressed: _openAccountDialog,
          ),
        ],
      ),
      body: Stack(
        children: [
          // Webの広い画面でも横に伸びすぎないよう最大幅を制限する。
          // 幅はダッシュボードと共通（layout.dart）。行き来しても本文の幅が
          // 変わらないようにするため。
          ContentWidth(
            child: Column(
                children: [
                  // 許可済み以外は、理由が分かるように必ず何か出す。
                  // 黙って消えると、参加者も実験者も原因を追えないため。
                  if (_push != PushPermission.granted)
                    PushPrompt(
                      permission: _push,
                      busy: _enablingPush,
                      onEnable: _onEnablePush,
                    ),
                  Expanded(
                    child: GridView.count(
                      crossAxisCount: 3, // 3列
                      padding: const EdgeInsets.all(16),
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      children: [
                        for (final item in kEmojiList)
                          EmojiTile(
                            item: item,
                            onTap: () => _onEmojiTap(item),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
          ),
          // Step 6: 保存中は半透明オーバーレイ＋くるくるで操作をブロック。
          if (_saving)
            const ModalBarrier(dismissible: false, color: Colors.black45),
          if (_saving) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}

/// 2桁ゼロ埋め（例: 5 -> "05"）。
String _two(int n) => n.toString().padLeft(2, '0');

/// 要件書 第4章のフィールドを組み立てる。
/// lat/lng は呼び出し側で上書きする（createdAt は保存直前に付ける）。
/// [activity] は任意入力なので、未選択なら `activity` フィールドは null になる。
Map<String, dynamic> buildEmotionRecord(
  EmojiItem item, {
  DateTime? now,
  ActivityItem? activity,
}) {
  final t = now ?? DateTime.now();
  return {
    'day': '${t.year}/${_two(t.month)}/${_two(t.day)}', // yyyy/MM/dd
    'time': '${_two(t.hour)}:${_two(t.minute)}', // HH:mm
    'emoji': item.emoji,
    'name': item.name,
    'valence': item.valence,
    'arousal': item.arousal,
    'activity': activity?.name,
    'lat': null,
    'lng': null,
  };
}

/// 現在地の緯度経度を取得する（Step 5）。
/// 権限拒否・取得失敗・タイムアウトのいずれでも例外を投げず (null, null) を返す。
/// → 位置情報が取れなくても記録の保存は止めない、という要件のため。
Future<({double? lat, double? lng})> tryGetLatLng() async {
  try {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission(); // ブラウザの許可ダイアログ
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return (lat: null, lng: null); // 拒否されたら null のまま続行
    }
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: Duration(seconds: 10), // 取得が長引いたら諦める
      ),
    );
    return (lat: pos.latitude, lng: pos.longitude);
  } catch (e) {
    debugPrint('位置情報の取得に失敗（null のまま続行）: $e');
    return (lat: null, lng: null);
  }
}

/// 名前の確認と、個人用リンクのコピーを行うダイアログ（表示専用）。
///
/// 名前はあとから変更できない仕様なので、ここでは編集させない。
/// ブラウザのデータが消えても、ここでコピーしたリンクを開けば元の名前に戻れる。
class _AccountDialog extends StatelessWidget {
  final String username;

  const _AccountDialog({required this.username});

  @override
  Widget build(BuildContext context) {
    final link = buildPersonalLink(Uri.base, username);

    return AlertDialog(
      title: const Text('名前とリンク'),
      content: SizedBox(
        width: 320,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('お名前', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 4),
              SelectableText(
                username,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'お名前は変更できません。'
                '別のお名前で使いたい場合は、管理者にご連絡ください。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const Divider(height: 24),
              Text(
                'この端末のデータが消えても、次のリンクを開けば元の記録に戻れます。'
                'ブックマークかホーム画面に追加しておいてください。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              SelectableText(
                link,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: link));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('リンクをコピーしました')),
                    );
                  },
                  icon: const Icon(Icons.link),
                  label: const Text('リンクをコピー'),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('閉じる'),
        ),
      ],
    );
  }
}

/// 確認画面の結果。[photo] は「写真も追加」を押したときだけ入る。
typedef ConfirmResult = ({ActivityItem? activity, Future<XFile?>? photo});

/// 絵文字タップ後の確認ダイアログ。選んだ気分の確認と、行動の選択を1画面で行う。
///
/// 「記録」で `(activity: 選んだ行動 or null, photo: null)` を返し、
/// キャンセル/画面外タップでは null を返す。行動の入力は任意なので、
/// 未選択のままでも記録できる。
///
/// [allowPhoto] のとき（開発用の鍵がある端末）は「写真も追加」も出す。
/// 押すとその場でカメラを開き、記録と写真の両方を行う。
class _ConfirmDialog extends StatefulWidget {
  final EmojiItem item;
  final bool allowPhoto;

  const _ConfirmDialog({required this.item, this.allowPhoto = false});

  @override
  State<_ConfirmDialog> createState() => _ConfirmDialogState();
}

class _ConfirmDialogState extends State<_ConfirmDialog> {
  ActivityItem? _selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    void record() => Navigator.pop<ConfirmResult>(
          context,
          (activity: _selected, photo: null),
        );
    void recordWithPhoto() {
      // iPhone はタップの直後でないとカメラを開かせないので、
      // 閉じるより先にカメラを開く。撮影の結果は記録の保存後に受け取る。
      final photo = startPhotoCapture();
      Navigator.pop<ConfirmResult>(context, (activity: _selected, photo: photo));
    }

    const title = Text('この気分で記録しますか？');
    return AlertDialog(
      // 写真のボタンがあるときは、スマホ幅でも2つのボタンが横に並ぶよう
      // 画面の端との余白を詰める（既定の左右40pxのままだと縦に積まれる）。
      insetPadding: widget.allowPhoto
          ? const EdgeInsets.symmetric(horizontal: 20, vertical: 24)
          : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      // 写真のボタンがあるときは「キャンセル」をタイトル横の×にして、
      // 下の段を「写真も追加」「記録」の2つだけにする。
      title: widget.allowPhoto
          ? Row(
              children: [
                const Expanded(child: title),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'キャンセル',
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            )
          : title,
      content: SizedBox(
        width: 320,
        // 画面が低いときはダイアログ内容ごとスクロールさせる。
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 72,
                height: 72,
                child: EmojiImage(item: widget.item), // 選んだ絵文字を大きく表示
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '何をしていましたか？（任意）',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: 8),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                  // アイコン(30)＋余白(4×2)＋選択枠(2×2)。名前の文字を
                  // 出さなくなったので、その分だけ行を低くしてある。
                  mainAxisExtent: 42,
                ),
                itemCount: kActivityList.length,
                itemBuilder: (context, i) {
                  final activity = kActivityList[i];
                  final selected = _selected?.name == activity.name;
                  return InkWell(
                    borderRadius: BorderRadius.circular(8),
                    // もう一度タップで選択解除（間違えて選んでも戻せる）。
                    onTap: () => setState(
                      () => _selected = selected ? null : activity,
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        color: selected ? scheme.primaryContainer : null,
                        border: Border.all(
                          color: selected ? scheme.primary : Colors.transparent,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.all(4),
                      // 行動はアイコンだけで示す（名前の文字は出さない）。
                      // 読み上げ機能向けに名前だけは残しておく。
                      child: Semantics(
                        label: activity.labelJa,
                        selected: selected,
                        child: Center(
                          child: SizedBox(
                            width: 30,
                            height: 30,
                            child: ActivityImage(
                              item: activity,
                              fallbackFontSize: 22,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
      actions: widget.allowPhoto
          ? [
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      onPressed: recordWithPhoto,
                      icon: const Icon(Icons.photo_camera_outlined, size: 18),
                      label: const Text('写真も追加'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: record,
                      child: const Text('記録'),
                    ),
                  ),
                ],
              ),
            ]
          : [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('キャンセル'),
              ),
              FilledButton(onPressed: record, child: const Text('記録')),
            ],
    );
  }
}

/// 通知の案内。許可済み以外のときに、いまの状態と次にすることを示す。
///
/// 状態ごとに何も出さずに消えると「なぜボタンが無いのか」が誰にも分からない。
/// とくに iOS は**ホーム画面に追加していないと通知APIそのものが使えない**ため、
/// その場合は追加を促す文言を出す。
///
/// ブラウザの許可ダイアログはユーザー操作からしか出せないので、
/// 起動時に自動で求めるのではなくボタンを踏んでもらう形にしている。
class PushPrompt extends StatelessWidget {
  final PushPermission permission;
  final bool busy;
  final VoidCallback onEnable;

  const PushPrompt({
    super.key,
    required this.permission,
    required this.busy,
    required this.onEnable,
  });

  /// 状態ごとの説明文。
  String get message => switch (permission) {
        PushPermission.notAsked => '10時〜19時の毎時、記録の時間をお知らせします。',
        PushPermission.denied =>
          '通知がブロックされています。ブラウザの設定から、このサイトの通知を許可してください。',
        PushPermission.unsupported =>
          'この開き方では通知を使えません。共有ボタンから「ホーム画面に追加」して、そのアイコンから開いてください。',
        PushPermission.granted => '通知はオンになっています。',
      };

  /// ボタンを出すのは、押せば状況が進む「まだ聞いていない」ときだけ。
  bool get showButton => permission == PushPermission.notAsked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              permission == PushPermission.notAsked
                  ? Icons.notifications_none
                  : Icons.info_outline,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(message, style: theme.textTheme.bodySmall),
            ),
            if (showButton) ...[
              const SizedBox(width: 8),
              FilledButton(
                onPressed: busy ? null : onEnable,
                child: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('オンにする'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 絵文字1個分のタイル。タップできる。
class EmojiTile extends StatelessWidget {
  final EmojiItem item;
  final VoidCallback? onTap;

  const EmojiTile({super.key, required this.item, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: EmojiImage(item: item),
        ),
      ),
    );
  }
}

