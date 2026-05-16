// ===================================================================================
// X68000 キーボード共有ステート
//
// X68000 から TARGET_RX で届く以下の状態を、Standard / LineInput など複数モード
// 間で共有する目的のコンテナ。これまで body / mode 個別に持っていたため、
// モード切替で LED 状態がリセットされてしまっていた。
//
// 持っている状態:
//   - LED 各キー (かな / ローマ字 / コード入力 / CAPS / INS / ひらがな / 全角)
//     の点灯状態
//   - LED 輝度 (0=最も明るい, 3=最も暗い)
//   - キーリピート開始遅延 / 間隔 (X68000 が SET REPEAT で配ってくる)
//
// X68kKeyboardPage の State が 1 つ生成し、TARGET_RX ハンドラを page 自身が
// 持って handleTargetRxByte に流す。各モードは constructor 経由でこのインスタンスを
// 受け取り、参照する。ChangeNotifier なので body 側は addListener で再描画フックを掛ける。
// ===================================================================================

import 'package:flutter/foundation.dart';

class X68kKeyboardSharedState extends ChangeNotifier {
  /// LED bit (0..6) → 対応 scancode
  static const List<int> ledBitToScancode = [
    0x5A, // bit0 かな
    0x5B, // bit1 ローマ字
    0x5C, // bit2 コード入力
    0x5D, // bit3 CAPS
    0x5E, // bit4 INS
    0x5F, // bit5 ひらがな
    0x60, // bit6 全角
  ];

  final Set<int> _ledOn = {};
  int _ledBrightness = 0;
  int _repeatDelayMs = 500;
  int _repeatIntervalMs = 110;

  Set<int> get ledOn => Set.unmodifiable(_ledOn);
  int get ledBrightness => _ledBrightness;
  int get repeatDelayMs => _repeatDelayMs;
  int get repeatIntervalMs => _repeatIntervalMs;

  bool isLedOn(int scancode) => _ledOn.contains(scancode);

  /// X68000 から届いた 1 バイトを解釈して state を更新する。
  /// 解釈不能なバイトは握りつぶす。
  void handleTargetRxByte(int byte) {
    if ((byte & 0x80) != 0) {
      // LED 制御: bit7=1, bit6..0 が各 LED 状態 (0=点灯, 1=消灯)
      bool changed = false;
      for (int i = 0; i < ledBitToScancode.length; i++) {
        final lit = ((byte >> i) & 1) == 0;
        final sc = ledBitToScancode[i];
        if (lit) {
          if (_ledOn.add(sc)) changed = true;
        } else {
          if (_ledOn.remove(sc)) changed = true;
        }
      }
      if (changed) notifyListeners();
      return;
    }
    if ((byte & 0xF0) == 0x60) {
      // 0b0110dddd: キーリピート開始遅延 (200 + dddd × 100 ms)
      _repeatDelayMs = 200 + (byte & 0x0F) * 100;
      return;
    }
    if ((byte & 0xF0) == 0x70) {
      // 0b0111rrrr: キーリピート間隔 (30 + rrrr² × 5 ms)
      final n = byte & 0x0F;
      _repeatIntervalMs = 30 + n * n * 5;
      return;
    }
    if ((byte & 0xFC) == 0x54) {
      // 0b010101xx: LED 輝度 (xx=00 最も明るい, xx=11 最も暗い)
      _ledBrightness = byte & 0x03;
      notifyListeners();
      return;
    }
  }
}
