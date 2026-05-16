// ===================================================================================
// SJIS Encoder
//
// Unicode コードポイント → Shift-JIS のコード (1 or 2 バイトを 16-bit に詰めたもの)
// を返す。X68000 のキーボード「コード入力」モードに 4 桁 hex を送るために使う。
//
// charset パッケージの組み込み ShiftJISEncoder には実装バグがあり、Unicode→SJIS の
// 方向が壊れている (内部テーブルを逆引きしようとして失敗する)。一方で内部の
// shiftJisToUtfTable (SJIS→UTF8 バイト列のマップ) は正しいので、それを 1 回だけ
// スキャンして codepoint → SJIS の逆引きマップを構築する。
//
// charset の src/ を直接 import している点は package の私的領域への依存になるので、
// charset のバージョンが上がってファイル構成が変わったらここを直す必要がある。
// ===================================================================================

import 'dart:convert';
// ignore: implementation_imports
import 'package:charset/src/shift_jis_table.dart' show shiftJisToUtfTable;

class SjisEncoder {
  static Map<int, int>? _cache;

  static Map<int, int> _buildReverseMap() {
    final map = <int, int>{};
    for (final entry in shiftJisToUtfTable.entries) {
      final sjis = entry.key;
      final utf8Bytes = entry.value;
      try {
        final decoded = utf8.decode(utf8Bytes);
        if (decoded.isEmpty) continue;
        final cp = decoded.runes.first;
        if (cp == 0xFFFD) continue; // replacement character は除外
        // 同じコードポイントが複数の SJIS コードに対応する場合があるので、最初の
        // 出現を採用する (テーブル順は SJIS 値の小さい方が先)。
        map.putIfAbsent(cp, () => sjis);
      } catch (_) {
        // 壊れた UTF-8 シーケンスは無視
      }
    }
    return map;
  }

  /// Unicode コードポイント → SJIS の 16-bit 値 (1-byte SJIS の場合は 0x00-0xFF、
  /// 2-byte SJIS は 0x8000-0xFFFF など)。SJIS にマップ不可なら null。
  static int? encode(int codepoint) {
    _cache ??= _buildReverseMap();
    return _cache![codepoint];
  }
}
