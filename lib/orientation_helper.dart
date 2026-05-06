import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// 画面の向き切り替えヘルパー。
///
/// Flutter 標準の [SystemChrome.setPreferredOrientations] は Android 側で
/// `SCREEN_ORIENTATION_USER_LANDSCAPE` にマップされ、OS の自動回転ロックが
/// ON のときは片側 landscape で固定されてしまう (USB ケーブルの向きを変える
/// のに端末を 180° ひっくり返したい場面で困る)。
///
/// このヘルパーは Android のみ MethodChannel "mimicx/orientation" 経由で
/// `SCREEN_ORIENTATION_SENSOR_LANDSCAPE` を直接指定して自動回転ロックを無視
/// する。iOS / macOS / Web では従来どおり [SystemChrome] にフォールバック。
class OrientationHelper {
  static const MethodChannel _ch = MethodChannel('mimicx/orientation');

  /// 横画面 (landscapeLeft / landscapeRight どちらの向きも許容) に切り替える。
  static Future<void> landscape() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _ch.invokeMethod<void>('setSensorLandscape');
        return;
      } catch (_) {
        // ネイティブチャンネル未登録時 (旧バイナリ等) はフォールバック
      }
    }
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  /// 縦画面 (portraitUp 固定) に切り替える。
  static Future<void> portrait() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _ch.invokeMethod<void>('setPortrait');
        return;
      } catch (_) {
        // フォールバック
      }
    }
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
  }
}
