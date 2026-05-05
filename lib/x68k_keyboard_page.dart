// ===================================================================================
// X68000 仮想キーボード画面
// ===================================================================================
// レイアウトは X68000 実機キーボードを参考にした JIS 配列。
// スキャンコードはプロトコル仕様 Appendix A 参照。
// ===================================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'midi_service.dart';

class X68kKeyboardPage extends StatefulWidget {
  final MidiService midi;
  final int channel;

  const X68kKeyboardPage({
    super.key,
    required this.midi,
    this.channel = MidiService.chKeyboardDefault,
  });

  @override
  State<X68kKeyboardPage> createState() => _X68kKeyboardPageState();
}

class _X68kKeyboardPageState extends State<X68kKeyboardPage> {
  // 押下中のキー (重複送信防止用)
  final Set<int> _pressed = {};

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  void _press(int code) {
    if (_pressed.add(code)) {
      widget.midi.sendNoteOn(widget.channel, code, 127);
      setState(() {});
    }
  }

  void _release(int code) {
    if (_pressed.remove(code)) {
      widget.midi.sendNoteOff(widget.channel, code);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1a1a1a),
      appBar: AppBar(
        title: const Text('X68000 Keyboard'),
        backgroundColor: const Color(0xFF000000),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return _buildKeyboard(constraints);
          },
        ),
      ),
    );
  }

  Widget _buildKeyboard(BoxConstraints constraints) {
    // 標準ユニット幅を計算する: メインキー領域は 15 ユニット、テンキー領域は 4 ユニット、間隙含めて約 22 ユニット
    final unitWidth = (constraints.maxWidth - 16) / 22.0;
    final keyHeight = unitWidth * 0.95;

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildFunctionRow(unitWidth, keyHeight),
            SizedBox(height: keyHeight * 0.15),
            _buildMainAreaRow1(unitWidth, keyHeight),
            _buildMainAreaRow2(unitWidth, keyHeight),
            _buildMainAreaRow3(unitWidth, keyHeight),
            _buildMainAreaRow4(unitWidth, keyHeight),
            _buildBottomRow(unitWidth, keyHeight),
          ],
        ),
      ),
    );
  }

  // BREAK COPY F1-F10 + (かな ローマ字 コード入力) (CAPS 記号入力 登録 HELP)
  Widget _buildFunctionRow(double u, double h) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _key('BREAK', 0x61, u * 1.2, h),
        _key('COPY', 0x62, u * 1.2, h),
        SizedBox(width: u * 0.2),
        _key('F1', 0x63, u, h), _key('F2', 0x64, u, h), _key('F3', 0x65, u, h),
        _key('F4', 0x66, u, h), _key('F5', 0x67, u, h),
        SizedBox(width: u * 0.2),
        _key('F6', 0x68, u, h), _key('F7', 0x69, u, h), _key('F8', 0x6A, u, h),
        _key('F9', 0x6B, u, h), _key('F10', 0x6C, u, h),
        SizedBox(width: u * 0.2),
        _keyMulti(['かな'], 0x5A, u * 1.1, h),
        _keyMulti(['ローマ字'], 0x5B, u * 1.1, h),
        _keyMulti(['コード入力'], 0x5C, u * 1.1, h),
        SizedBox(width: u * 0.2),
        _key('CAPS', 0x5D, u, h),
        _keyMulti(['記号入力'], 0x52, u * 1.1, h),
        _keyMulti(['登録'], 0x53, u, h),
        _key('HELP', 0x54, u, h),
      ],
    );
  }

  // 数字行: ESC 1234567890-^¥ BS  | HOME INS DEL  | CLR / * -
  Widget _buildMainAreaRow1(double u, double h) {
    return Row(
      children: [
        _key('ESC', 0x01, u * 1.1, h),
        _key('1', 0x02, u, h), _key('2', 0x03, u, h), _key('3', 0x04, u, h),
        _key('4', 0x05, u, h), _key('5', 0x06, u, h), _key('6', 0x07, u, h),
        _key('7', 0x08, u, h), _key('8', 0x09, u, h), _key('9', 0x0A, u, h),
        _key('0', 0x0B, u, h),
        _key('-', 0x0C, u, h), _key('^', 0x0D, u, h), _key('¥', 0x0E, u, h),
        _key('BS', 0x0F, u * 1.4, h),
        SizedBox(width: u * 0.2),
        _key('HOME', 0x36, u, h),
        _keyMulti(['INS', 'Home'], 0x5E, u, h),
        _key('DEL', 0x37, u, h),
        SizedBox(width: u * 0.2),
        _key('CLR', 0x3F, u, h),
        _key('/', 0x40, u, h),
        _key('*', 0x41, u, h),
        _key('-', 0x42, u, h),
      ],
    );
  }

  // TAB QWERTYUIOP @ [ Enter | ROLL UP, ROLL DOWN, UNDO | 7 8 9 +
  Widget _buildMainAreaRow2(double u, double h) {
    return Row(
      children: [
        _key('TAB', 0x10, u * 1.5, h),
        _key('Q', 0x11, u, h), _key('W', 0x12, u, h), _key('E', 0x13, u, h),
        _key('R', 0x14, u, h), _key('T', 0x15, u, h), _key('Y', 0x16, u, h),
        _key('U', 0x17, u, h), _key('I', 0x18, u, h), _key('O', 0x19, u, h),
        _key('P', 0x1A, u, h),
        _key('@', 0x1B, u, h), _key('[', 0x1C, u, h),
        _key('↵', 0x1D, u * 1.0, h),
        SizedBox(width: u * 0.2),
        _keyMulti(['ROLL', 'UP'], 0x38, u, h),
        _keyMulti(['ROLL', 'DOWN'], 0x39, u, h),
        _key('UNDO', 0x3A, u, h),
        SizedBox(width: u * 0.2),
        _key('7', 0x43, u, h), _key('8', 0x44, u, h), _key('9', 0x45, u, h),
        _key('+', 0x46, u, h),
      ],
    );
  }

  // CTRL ASDFGHJKL ; : ] (Enter続き) | ← ↑ → | 4 5 6 =
  Widget _buildMainAreaRow3(double u, double h) {
    return Row(
      children: [
        _key('CTRL', 0x71, u * 1.6, h),
        _key('A', 0x1E, u, h), _key('S', 0x1F, u, h), _key('D', 0x20, u, h),
        _key('F', 0x21, u, h), _key('G', 0x22, u, h), _key('H', 0x23, u, h),
        _key('J', 0x24, u, h), _key('K', 0x25, u, h), _key('L', 0x26, u, h),
        _key(';', 0x27, u, h), _key(':', 0x28, u, h), _key(']', 0x29, u, h),
        SizedBox(width: u * 0.9),
        SizedBox(width: u * 0.2),
        _key('←', 0x3B, u, h),
        SizedBox(width: u * 0.05),
        SizedBox(width: u, child: Center(child: _key('↑', 0x3C, u * 0.95, h))),
        _key('→', 0x3D, u, h),
        SizedBox(width: u * 0.2),
        _key('4', 0x47, u, h), _key('5', 0x48, u, h), _key('6', 0x49, u, h),
        _key('=', 0x4A, u, h),
      ],
    );
  }

  // SHIFT ZXCVBNM , . / _ SHIFT | ↓ | 1 2 3 (ENTER tall)
  Widget _buildMainAreaRow4(double u, double h) {
    return Row(
      children: [
        _key('SHIFT', 0x70, u * 2.1, h),
        _key('Z', 0x2A, u, h), _key('X', 0x2B, u, h), _key('C', 0x2C, u, h),
        _key('V', 0x2D, u, h), _key('B', 0x2E, u, h), _key('N', 0x2F, u, h),
        _key('M', 0x30, u, h),
        _key(',', 0x31, u, h), _key('.', 0x32, u, h), _key('/', 0x33, u, h),
        _key('_', 0x34, u, h),
        _key('SHIFT', 0x70, u * 1.5, h),
        SizedBox(width: u * 0.2),
        SizedBox(width: u),
        SizedBox(width: u, child: Center(child: _key('↓', 0x3E, u * 0.95, h))),
        SizedBox(width: u),
        SizedBox(width: u * 0.2),
        _key('1', 0x4B, u, h), _key('2', 0x4C, u, h), _key('3', 0x4D, u, h),
        _key('ENTER', 0x4E, u, h),
      ],
    );
  }

  // CTRL ひらがな XF1 XF2 SPACE XF3 XF4 XF5 全角 CTRL | OPT.1 OPT.2 | 0 . , ENTER
  Widget _buildBottomRow(double u, double h) {
    return Row(
      children: [
        _key('CTRL', 0x71, u * 1.2, h),
        _keyMulti(['ひらがな'], 0x5F, u * 1.1, h),
        _key('XF1', 0x55, u, h),
        _key('XF2', 0x56, u, h),
        _key('SPACE', 0x35, u * 5.0, h),
        _key('XF3', 0x57, u, h),
        _key('XF4', 0x58, u, h),
        _key('XF5', 0x59, u, h),
        _keyMulti(['全角'], 0x60, u * 1.1, h),
        _key('CTRL', 0x71, u * 1.2, h),
        SizedBox(width: u * 0.2),
        _key('OPT.1', 0x72, u, h),
        _key('OPT.2', 0x73, u, h),
        SizedBox(width: u * 0.2),
        _key('0', 0x4F, u * 2, h),
        _key('.', 0x51, u, h),
        _key(',', 0x50, u, h),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Key widgets
  // ---------------------------------------------------------------------------

  Widget _key(String label, int scancode, double width, double height) {
    return _keyMulti([label], scancode, width, height);
  }

  Widget _keyMulti(List<String> labels, int scancode, double width, double height) {
    final pressed = _pressed.contains(scancode);
    return Padding(
      padding: const EdgeInsets.all(1.5),
      child: GestureDetector(
        onTapDown: (_) => _press(scancode),
        onTapUp: (_) => _release(scancode),
        onTapCancel: () => _release(scancode),
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: pressed ? const Color(0xFF505050) : const Color(0xFF222222),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: pressed ? Colors.white : const Color(0xFF555555),
              width: pressed ? 2 : 1,
            ),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: labels
                  .map((s) => Text(
                        s,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: pressed ? Colors.white : Colors.grey.shade300,
                          fontSize: _autoFontSize(s, width, height),
                          height: 1.0,
                        ),
                      ))
                  .toList(),
            ),
          ),
        ),
      ),
    );
  }

  double _autoFontSize(String label, double w, double h) {
    final size = w < h ? w : h;
    if (label.length <= 1) return size * 0.45;
    if (label.length <= 3) return size * 0.32;
    if (label.length <= 5) return size * 0.22;
    return size * 0.18;
  }
}
