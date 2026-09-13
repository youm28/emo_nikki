/// 記録に付ける写真（開発用・試作）。
///
/// 保存先は `dev/{dataKey}/photos/{自動ID}`。dataKey はパスワードから作る鍵で、
/// アプリには書かれていないので、知らない人はここを読めない（dev_crypto.dart）。
///
/// 写真は iPhone の中で縮小してから Firestore に直接入れる（Cloud Storage は
/// 2026年2月から有料プランが必須になったため、無料プランのまま試せる形にした）。
/// Firestore は1件1MiBまでなので、長辺1024px・JPEG品質70に縮めて入れる。
library;

import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';

import 'firebase_ready.dart';

/// 1件あたりの上限（Firestore の1MiBに余裕を持たせる）。
const int kMaxPhotoBytes = 900 * 1024;

/// 記録に付けた写真1枚。
class DevPhoto {
  final String id;
  final String username;
  final String day; // yyyy/MM/dd（記録と同じ形）
  final String time; // HH:mm
  final String emotionId; // 付けた記録のID
  final String emojiName;
  final Uint8List bytes;

  const DevPhoto({
    required this.id,
    required this.username,
    required this.day,
    required this.time,
    required this.emotionId,
    required this.emojiName,
    required this.bytes,
  });

  static DevPhoto? fromDoc(String id, Map<String, dynamic> data) {
    final image = data['image'];
    if (image is! Blob) return null;
    return DevPhoto(
      id: id,
      username: data['username'] as String? ?? '',
      day: data['day'] as String? ?? '',
      time: data['time'] as String? ?? '',
      emotionId: data['emotionId'] as String? ?? '',
      emojiName: data['emojiName'] as String? ?? '',
      bytes: image.bytes,
    );
  }
}

/// 写真を撮って保存した結果。
enum PhotoResult { saved, cancelled, tooLarge }

CollectionReference<Map<String, dynamic>> _photos(String dataKey) =>
    FirebaseFirestore.instance.collection('dev').doc(dataKey).collection('photos');

/// カメラを開く。撮り終わる（またはやめる）と結果が返る。
///
/// iPhone の Safari は「タップの直後」でないとカメラを開かせないので、
/// ボタンの処理の**最初に**呼ぶこと（前に await を挟まない）。
/// 結果は待たずに受け取っておき、記録の保存と並行して撮ってもらう。
Future<XFile?> startPhotoCapture() => ImagePicker().pickImage(
      source: ImageSource.camera,
      // 縮小のときに画像を作り直すので、写真に埋め込まれた位置情報(EXIF)も落ちる。
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 70,
    );

/// [startPhotoCapture] で撮った写真を、記録に付けて保存する。
Future<PhotoResult> savePhoto(
  Future<XFile?> capture, {
  required String dataKey,
  required String username,
  required String emotionId,
  required String day,
  required String time,
  required String emojiName,
}) async {
  final file = await capture;
  if (file == null) return PhotoResult.cancelled;

  final bytes = await file.readAsBytes();
  if (bytes.length > kMaxPhotoBytes) return PhotoResult.tooLarge;

  await ensureFirebase();
  await _photos(dataKey).add({
    'username': username,
    'day': day,
    'time': time,
    'emotionId': emotionId,
    'emojiName': emojiName,
    'image': Blob(bytes),
    'createdAt': FieldValue.serverTimestamp(),
  });
  return PhotoResult.saved;
}

/// その人のその日の写真（時刻順）。
Future<List<DevPhoto>> fetchPhotos({
  required String dataKey,
  required String username,
  required String day,
}) async {
  await ensureFirebase();
  final snap = await _photos(dataKey)
      .where('username', isEqualTo: username)
      .where('day', isEqualTo: day)
      .get();
  return [
    for (final d in snap.docs) ?DevPhoto.fromDoc(d.id, d.data()),
  ]..sort((a, b) => a.time.compareTo(b.time));
}

Future<void> deletePhoto({required String dataKey, required String id}) async {
  await ensureFirebase();
  await _photos(dataKey).doc(id).delete();
}

/// 試作用の日記（本番の日記 users/…/diaries とは別に保存する）。
DocumentReference<Map<String, dynamic>> devDiaryDoc({
  required String dataKey,
  required String username,
  required String docDay, // yyyy-MM-dd
}) =>
    FirebaseFirestore.instance
        .collection('dev')
        .doc(dataKey)
        .collection('diaries')
        .doc('${username}_$docDay');
