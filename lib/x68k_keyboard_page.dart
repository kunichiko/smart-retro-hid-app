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

  // テンキーを表示するか (オフだとメインキーが大きく表示される)
  bool _numpadVisible = true;

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
        actions: [
          IconButton(
            tooltip: _numpadVisible ? 'テンキーを非表示' : 'テンキーを表示',
            icon: Icon(_numpadVisible ? Icons.dialpad : Icons.dialpad_outlined),
            onPressed: () => setState(() => _numpadVisible = !_numpadVisible),
          ),
        ],
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

  // レイアウト定数 (unit 単位)
  //   mainArea (16) + gap (0.3) + cursorArea (3) + gap (0.3) + numpadArea (4) = 23.6
  //   テンキー非表示時:  mainArea (16) + gap (0.3) + cursorArea (3)            = 19.3
  static const double _mainAreaW = 16.0;
  static const double _cursorAreaW = 3.0;
  static const double _numpadAreaW = 4.0;
  static const double _gap = 0.3;

  double get _totalW => _numpadVisible
      ? _mainAreaW + _gap + _cursorAreaW + _gap + _numpadAreaW
      : _mainAreaW + _gap + _cursorAreaW;

  Widget _buildKeyboard(BoxConstraints constraints) {
    // 各キーは declared width 内にパディングを内包するため、unit 計算は単純な分割で OK
    final outerPadding = 16.0;
    final available = constraints.maxWidth - outerPadding;
    final u = available / _totalW;
    final h = u * 0.95;

    // 縦長キー (Return / numpad ENTER) を Stack で重ねるための位置計算
    // Y 位置: function row(h) + gap(0.15h) + 累積行
    final innerPad = 8.0;
    final fnRowH = h;
    final fnGap = h * 0.15;
    final yRow1 = innerPad + fnRowH + fnGap;
    final yRow2 = yRow1 + h;
    final yRow3 = yRow2 + h;
    final yRow4 = yRow3 + h;
    final yRow5 = yRow4 + h;

    // X 位置: メインエリア内
    // 行 2 main: TAB(1.6) + Q-P(10) + @(1) + [(1) = 13.6u
    // 行 3 main: CTRL(1.6) + A-L(9) + ;:](3) = 13.6u
    // Return キーは 13.6u から 15.5u (BS の右端) まで → 幅 1.9u
    final xReturn = innerPad + u * 13.6;
    final returnW = 1.9;
    // 行 4-5 numpad ENTER は numpad 領域の最右
    final xNumpadEnter = innerPad + u * (_mainAreaW + _gap + _cursorAreaW + _gap + 3);

    return SingleChildScrollView(
      child: Stack(
        children: [
          Padding(
            padding: EdgeInsets.all(innerPad),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildFunctionRow(u, h),
                SizedBox(height: fnGap),
                _buildMainAreaRow1(u, h),
                _buildMainAreaRow2(u, h),
                _buildMainAreaRow3(u, h),
                _buildMainAreaRow4(u, h),
                _buildBottomRow(u, h),
              ],
            ),
          ),
          // Return キー (縦 2 段、幅 1.9u で BS と右端揃え)
          Positioned(
            left: xReturn,
            top: yRow2,
            child: SizedBox(
              width: u * returnW,
              height: h * 2,
              child: _keyMulti(['↵'], 0x1D, u * returnW, h * 2),
            ),
          ),
          // テンキー ENTER (縦 2 段) — テンキー表示時のみ
          if (_numpadVisible)
            Positioned(
              left: xNumpadEnter,
              top: yRow4,
              child: SizedBox(
                width: u,
                height: h * 2,
                child: _keyMulti(['ENTER'], 0x4E, u, h * 2),
              ),
            ),
        ],
      ),
    );
  }

  // BREAK COPY F1-F10 | かな ローマ字 コード入力 | CAPS 記号入力 登録 HELP
  Widget _buildFunctionRow(double u, double h) {
    // main = 12.8u (BREAK + COPY + gap*2 + F1-F10)
    // cursor = 3u (かな + ローマ字 + コード入力)
    // numpad = 4u (CAPS + 記号入力 + 登録 + HELP)
    return _row3(
      u: u, h: h,
      main: [
        _key('BREAK', 0x61, u * 1.2, h),
        _key('COPY', 0x62, u * 1.2, h),
        SizedBox(width: u * 0.2),
        _key('F1', 0x63, u, h), _key('F2', 0x64, u, h), _key('F3', 0x65, u, h),
        _key('F4', 0x66, u, h), _key('F5', 0x67, u, h),
        SizedBox(width: u * 0.2),
        _key('F6', 0x68, u, h), _key('F7', 0x69, u, h), _key('F8', 0x6A, u, h),
        _key('F9', 0x6B, u, h), _key('F10', 0x6C, u, h),
      ],
      mainSumU: 1.2 + 1.2 + 0.2 + 5 + 0.2 + 5,
      cursor: [
        _keyMulti(['かな'], 0x5A, u, h),
        _keyMulti(['ローマ字'], 0x5B, u, h),
        _keyMulti(['コード入力'], 0x5C, u, h),
      ],
      cursorSumU: 3,
      numpad: [
        _key('CAPS', 0x5D, u, h),
        _keyMulti(['記号入力'], 0x52, u, h),
        _keyMulti(['登録'], 0x53, u, h),
        _key('HELP', 0x54, u, h),
      ],
      numpadSumU: 4,
    );
  }

  // 行を「main + gap + cursor + gap + numpad」形式で組み立てる
  // _numpadVisible=false のときは numpad 部分を完全に省略する
  Widget _row3({
    required double u,
    required double h,
    required List<Widget> main,
    required double mainSumU,    // main 内のキー幅合計 (unit)
    required List<Widget> cursor,
    required double cursorSumU,  // cursor 内のキー幅合計 (unit)
    required List<Widget> numpad,
    required double numpadSumU,
  }) {
    return Row(
      children: [
        ...main,
        SizedBox(width: u * (_mainAreaW - mainSumU)),
        SizedBox(width: u * _gap),
        ...cursor,
        SizedBox(width: u * (_cursorAreaW - cursorSumU)),
        if (_numpadVisible) ...[
          SizedBox(width: u * _gap),
          ...numpad,
          SizedBox(width: u * (_numpadAreaW - numpadSumU)),
        ],
      ],
    );
  }

  // 数字行: ESC 1234567890-^¥ BS  | HOME INS DEL  | CLR / * -
  Widget _buildMainAreaRow1(double u, double h) {
    return _row3(
      u: u, h: h,
      main: [
        _key('ESC', 0x01, u * 1.1, h),
        _key('1', 0x02, u, h), _key('2', 0x03, u, h), _key('3', 0x04, u, h),
        _key('4', 0x05, u, h), _key('5', 0x06, u, h), _key('6', 0x07, u, h),
        _key('7', 0x08, u, h), _key('8', 0x09, u, h), _key('9', 0x0A, u, h),
        _key('0', 0x0B, u, h),
        _key('-', 0x0C, u, h), _key('^', 0x0D, u, h), _key('¥', 0x0E, u, h),
        _key('BS', 0x0F, u * 1.4, h),
      ],
      mainSumU: 1.1 + 13 + 1.4,
      cursor: [
        _key('HOME', 0x36, u, h),
        _keyMulti(['INS', 'Home'], 0x5E, u, h),
        _key('DEL', 0x37, u, h),
      ],
      cursorSumU: 3,
      numpad: [
        _key('CLR', 0x3F, u, h),
        _key('/', 0x40, u, h),
        _key('*', 0x41, u, h),
        _key('-', 0x42, u, h),
      ],
      numpadSumU: 4,
    );
  }

  // TAB QWERTYUIOP @ [ + (Return は Stack で 2段) | ROLL UP, ROLL DOWN, UNDO | 7 8 9 +
  Widget _buildMainAreaRow2(double u, double h) {
    return _row3(
      u: u, h: h,
      main: [
        _key('TAB', 0x10, u * 1.6, h),
        _key('Q', 0x11, u, h), _key('W', 0x12, u, h), _key('E', 0x13, u, h),
        _key('R', 0x14, u, h), _key('T', 0x15, u, h), _key('Y', 0x16, u, h),
        _key('U', 0x17, u, h), _key('I', 0x18, u, h), _key('O', 0x19, u, h),
        _key('P', 0x1A, u, h),
        _key('@', 0x1B, u, h), _key('[', 0x1C, u, h),
        // Return キーは Stack で重ねる (位置 13.6u, 幅 1.9u, 縦 2 段)
        SizedBox(width: u * 1.9),
      ],
      mainSumU: 1.6 + 10 + 1 + 1 + 1.9,
      cursor: [
        _keyMulti(['ROLL', 'UP'], 0x38, u, h),
        _keyMulti(['ROLL', 'DOWN'], 0x39, u, h),
        _key('UNDO', 0x3A, u, h),
      ],
      cursorSumU: 3,
      numpad: [
        _key('7', 0x43, u, h), _key('8', 0x44, u, h), _key('9', 0x45, u, h),
        _key('+', 0x46, u, h),
      ],
      numpadSumU: 4,
    );
  }

  // CTRL ASDFGHJKL ; : ] (Return wrap は Stack) | ← ↑ → | 4 5 6 =
  Widget _buildMainAreaRow3(double u, double h) {
    return _row3(
      u: u, h: h,
      main: [
        _key('CTRL', 0x71, u * 1.6, h),
        _key('A', 0x1E, u, h), _key('S', 0x1F, u, h), _key('D', 0x20, u, h),
        _key('F', 0x21, u, h), _key('G', 0x22, u, h), _key('H', 0x23, u, h),
        _key('J', 0x24, u, h), _key('K', 0x25, u, h), _key('L', 0x26, u, h),
        _key(';', 0x27, u, h), _key(':', 0x28, u, h), _key(']', 0x29, u, h),
        // Return が Stack で覆う領域 (1.9u 分)
        SizedBox(width: u * 1.9),
      ],
      mainSumU: 1.6 + 9 + 3 + 1.9,
      cursor: [
        _key('←', 0x3B, u, h),
        _key('↑', 0x3C, u, h),
        _key('→', 0x3D, u, h),
      ],
      cursorSumU: 3,
      numpad: [
        _key('4', 0x47, u, h), _key('5', 0x48, u, h), _key('6', 0x49, u, h),
        _key('=', 0x4A, u, h),
      ],
      numpadSumU: 4,
    );
  }

  // SHIFT ZXCVBNM , . / _ SHIFT | (空) ↓ (空) | 1 2 3 (ENTER は Stack で 2段)
  Widget _buildMainAreaRow4(double u, double h) {
    return _row3(
      u: u, h: h,
      main: [
        _key('SHIFT', 0x70, u * 2.1, h),
        _key('Z', 0x2A, u, h), _key('X', 0x2B, u, h), _key('C', 0x2C, u, h),
        _key('V', 0x2D, u, h), _key('B', 0x2E, u, h), _key('N', 0x2F, u, h),
        _key('M', 0x30, u, h),
        _key(',', 0x31, u, h), _key('.', 0x32, u, h), _key('/', 0x33, u, h),
        _key('_', 0x34, u, h),
        _key('SHIFT', 0x70, u * 2.4, h),
      ],
      mainSumU: 2.1 + 7 + 4 + 2.4,
      cursor: [
        // ↓ を中央に
        SizedBox(width: u),
        _key('↓', 0x3E, u, h),
        SizedBox(width: u),
      ],
      cursorSumU: 3,
      numpad: [
        _key('1', 0x4B, u, h), _key('2', 0x4C, u, h), _key('3', 0x4D, u, h),
        // ENTER は Stack で重ねる
        SizedBox(width: u),
      ],
      numpadSumU: 4,
    );
  }

  // ひらがな XF1 XF2 SPACE XF3 XF4 XF5 全角 | OPT.1(1.5u) OPT.2(1.5u) | 0(2u) , . (ENTER は Stack)
  Widget _buildBottomRow(double u, double h) {
    return _row3(
      u: u, h: h,
      main: [
        _keyMulti(['ひらがな'], 0x5F, u * 1.5, h),
        _key('XF1', 0x55, u, h),
        _key('XF2', 0x56, u, h),
        _key('SPACE', 0x35, u * 7.0, h),
        _key('XF3', 0x57, u, h),
        _key('XF4', 0x58, u, h),
        _key('XF5', 0x59, u, h),
        _keyMulti(['全角'], 0x60, u * 1.5, h),
      ],
      mainSumU: 1.5 + 1 + 1 + 7 + 1 + 1 + 1 + 1.5,
      cursor: [
        _key('OPT.1', 0x72, u * 1.5, h),
        _key('OPT.2', 0x73, u * 1.5, h),
      ],
      cursorSumU: 3,
      numpad: [
        // 0 (2u), . (visible), , (ENTER に隠れる)
        _key('0', 0x4F, u * 2, h),
        _key('.', 0x51, u, h),
        _key(',', 0x50, u, h),
      ],
      numpadSumU: 4,
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
    // 宣言幅 width にパディング (1.5px × 2) を内包させる
    return SizedBox(
      width: width,
      height: height,
      child: Padding(
        padding: const EdgeInsets.all(1.5),
        child: GestureDetector(
          onTapDown: (_) => _press(scancode),
          onTapUp: (_) => _release(scancode),
          onTapCancel: () => _release(scancode),
          child: Container(
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
