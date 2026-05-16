// ===================================================================================
// SJIS Encoder
//
// Unicode 文字 → Shift-JIS のコード (1 or 2 バイトを 16-bit に詰めたもの) を返す。
// X68000 のキーボード「コード入力」モードに 4 桁 hex を送るために使う。
//
// 内部では charset パッケージの `shiftJis` codec を利用する。
// この package のテーブル名 (shiftJisToUtfTable / utfToShiftJisTable) は意図と
// 逆さに名付けられていて紛らわしいが、実際の encoder は内部の table を使って
// UTF-8 → SJIS の変換を正しく行う。マップ不可な文字は内部で 0xFFFD を 1 要素
// 返す挙動なので、ここで検出して null を返す。
// ===================================================================================

import 'package:charset/charset.dart' show shiftJis;

class SjisEncoder {
  /// Unicode コードポイント → SJIS の 16-bit 値 (1-byte SJIS の場合は 0x00-0xFF、
  /// 2-byte SJIS は例: 0x8ABF=漢)。SJIS にマップ不可なら null。
  static int? encode(int codepoint) {
    final String char;
    try {
      char = String.fromCharCode(codepoint);
    } catch (_) {
      return null;
    }
    final List<int> bytes;
    try {
      bytes = shiftJis.encode(char);
    } catch (_) {
      return null;
    }
    // unmappable は [0xFFFD] (16-bit 値) を 1 要素として返す挙動
    if (bytes.length == 1 && bytes[0] == 0xFFFD) return null;
    if (bytes.length == 1) return bytes[0];
    if (bytes.length == 2) return (bytes[0] << 8) | bytes[1];
    return null;
  }
}
