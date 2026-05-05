// ===================================================================================
// X68000 仮想キーボード画面
// ===================================================================================
// レイアウトは X68000 実機キーボードを参考にした JIS 配列。
// スキャンコードはプロトコル仕様 Appendix A 参照。
// ===================================================================================

import 'dart:async';
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

  // X68000 LED 制御コマンド (bit7=1) の各ビット → 対応キーのスキャンコード
  //   bit0: かな, bit1: ローマ字, bit2: コード入力, bit3: CAPS,
  //   bit4: INS,  bit5: ひらがな, bit6: 全角
  // X68000 のビット意味は「0=点灯, 1=消灯」
  static const List<int> _ledBitToScancode = [
    0x5A, // bit0 かな
    0x5B, // bit1 ローマ字
    0x5C, // bit2 コード入力
    0x5D, // bit3 CAPS
    0x5E, // bit4 INS
    0x5F, // bit5 ひらがな
    0x60, // bit6 全角
  ];
  // scancode → 点灯/消灯
  final Set<int> _ledOn = {};

  // ひらがな・全角は緑、それ以外 (かな/ローマ字/コード入力/CAPS/INS) は赤
  static const Set<int> _greenLedScancodes = {0x5F, 0x60};

  // X68000 JIS かな配列: かな LED 点灯時にこのラベルでキー表示を上書き
  static const Map<int, String> _kanaLabels = {
    0x02: 'ぬ', 0x03: 'ふ', 0x04: 'あ', 0x05: 'う', 0x06: 'え',
    0x07: 'お', 0x08: 'や', 0x09: 'ゆ', 0x0A: 'よ', 0x0B: 'わ',
    0x0C: 'ほ', 0x0D: 'へ', 0x0E: 'ー',
    0x11: 'た', 0x12: 'て', 0x13: 'い', 0x14: 'す', 0x15: 'か',
    0x16: 'ん', 0x17: 'な', 0x18: 'に', 0x19: 'ら', 0x1A: 'せ',
    0x1B: '゛', 0x1C: '゜',
    0x1E: 'ち', 0x1F: 'と', 0x20: 'し', 0x21: 'は', 0x22: 'き',
    0x23: 'く', 0x24: 'ま', 0x25: 'の', 0x26: 'り', 0x27: 'れ',
    0x28: 'け', 0x29: 'む',
    0x2A: 'つ', 0x2B: 'さ', 0x2C: 'そ', 0x2D: 'ひ', 0x2E: 'こ',
    0x2F: 'み', 0x30: 'も', 0x31: 'ね', 0x32: 'る', 0x33: 'め',
    0x34: 'ろ',
  };

  // キーリピート (X68000 の SET REPEAT START / RATE コマンドで可変)
  Timer? _repeatTimer;
  int? _repeatScancode;
  int _repeatDelayMs = 500;     // 0b0110dddd: 200 + dddd*100 ms (default dddd=3)
  int _repeatIntervalMs = 110;  // 0b0111rrrr: 30 + rrrr²*5 ms (default rrrr=4)

  // LED 輝度 (0b010101xx: xx=00 最も明るい, xx=11 最も暗い)
  // xx=00 → factor 1.0, xx=11 → factor 0.25
  int _ledBrightness = 0;
  static const List<double> _brightnessFactors = [1.0, 0.7, 0.45, 0.25];

  // ポップアップで使う基本ユニットサイズ (LayoutBuilder で更新)
  double _h = 0;

  // 元のハンドラを保持して dispose で復元
  void Function(int, int)? _prevTargetRxHandler;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    _prevTargetRxHandler = widget.midi.onTargetRx;
    widget.midi.onTargetRx = _handleTargetRx;
  }

  @override
  void dispose() {
    _repeatTimer?.cancel();
    widget.midi.onTargetRx = _prevTargetRxHandler;
    super.dispose();
  }

  // ターゲット機 (X68000) から届いた生バイトを解釈する
  void _handleTargetRx(int midiChannel, int byte) {
    if (midiChannel != widget.channel) return;

    if ((byte & 0x80) != 0) {
      // LED 制御コマンド: bit7=1, bit6..0 が各 LED 状態 (0=点灯, 1=消灯)
      setState(() {
        for (int i = 0; i < _ledBitToScancode.length; i++) {
          final lit = ((byte >> i) & 1) == 0;
          final sc = _ledBitToScancode[i];
          if (lit) {
            _ledOn.add(sc);
          } else {
            _ledOn.remove(sc);
          }
        }
      });
      return;
    }
    if ((byte & 0xF0) == 0x60) {
      // 0b0110dddd: キーリピート開始遅延 (200 + dddd × 100 ms)
      final n = byte & 0x0F;
      _repeatDelayMs = 200 + n * 100;
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
      setState(() {
        _ledBrightness = byte & 0x03;
      });
      return;
    }
  }

  void _press(int code) {
    if (_pressed.add(code)) {
      widget.midi.sendNoteOn(widget.channel, code, 127);
      HapticFeedback.lightImpact();
      _scheduleRepeat(code);
      setState(() {});
    }
  }

  void _release(int code) {
    if (_pressed.remove(code)) {
      if (_repeatScancode == code) {
        _repeatTimer?.cancel();
        _repeatScancode = null;
      }
      widget.midi.sendNoteOff(widget.channel, code);
      setState(() {});
    }
  }

  // 押下から _repeatDelayMs 経過したらリピート開始
  void _scheduleRepeat(int code) {
    _repeatTimer?.cancel();
    _repeatScancode = code;
    _repeatTimer = Timer(Duration(milliseconds: _repeatDelayMs), () {
      if (!_pressed.contains(code)) return;
      _startRepeating(code);
    });
  }

  // _repeatIntervalMs 間隔で Note On を撃ち続ける (firmware 側は make コードを再送)
  void _startRepeating(int code) {
    _repeatTimer = Timer.periodic(
      Duration(milliseconds: _repeatIntervalMs),
      (_) {
        if (!_pressed.contains(code)) {
          _repeatTimer?.cancel();
          _repeatScancode = null;
          return;
        }
        widget.midi.sendNoteOn(widget.channel, code, 127);
        // リピートのたびに軽い触覚フィードバック
        HapticFeedback.selectionClick();
      },
    );
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
    _h = h;  // ポップアップサイズ計算用に保存

    // 縦長キー (Return / numpad ENTER) を Stack で重ねるための位置計算
    // Y 位置: function row(h) + gap(0.15h) + 累積行
    final innerPad = 8.0;
    final fnRowH = h;
    final fnGap = h * 0.15;
    final yRow1 = innerPad + fnRowH + fnGap;
    final yRow2 = yRow1 + h;
    final yRow3 = yRow2 + h;
    final yRow4 = yRow3 + h;

    // X 位置: メインエリア内
    // 行 2 main: TAB(1.6) + Q-P(10) + @(1) + [(1) = 13.6u
    // 行 3 main: CTRL(1.6) + A-L(9) + ;:](3) = 13.6u
    // Return キーは 13.6u から 15.5u (BS の右端) まで → 幅 1.9u
    final xReturn = innerPad + u * 13.6;
    final returnW = 1.9;
    // 行 4-5 numpad ENTER は numpad 領域の最右
    final xNumpadEnter = innerPad + u * (_mainAreaW + _gap + _cursorAreaW + _gap + 3);

    // カーソル ←/→ をクロス配置で行 3-4 の中央に置く
    final xCursorAreaStart = innerPad + u * (_mainAreaW + _gap);
    final xLeftCursor = xCursorAreaStart;
    final xRightCursor = xCursorAreaStart + u * 2;
    final yLeftRightCursor = yRow3 + h * 0.5;  // ↑ と ↓ の中間

    return SingleChildScrollView(
      clipBehavior: Clip.none,  // ポップアップが上方向にはみ出るのを許可
      child: Stack(
        clipBehavior: Clip.none,
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
          // ←: カーソル列の左、行 3 と 4 の中間
          Positioned(
            left: xLeftCursor,
            top: yLeftRightCursor,
            child: SizedBox(
              width: u, height: h,
              child: _key('←', 0x3B, u, h),
            ),
          ),
          // →: カーソル列の右
          Positioned(
            left: xRightCursor,
            top: yLeftRightCursor,
            child: SizedBox(
              width: u, height: h,
              child: _key('→', 0x3D, u, h),
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
        _keyMulti(['記号', '入力'], 0x52, u, h),
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
        _key('INS', 0x5E, u, h),
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

  // CTRL ASDFGHJKL ; : ] (Return wrap は Stack) | (空) ↑ (空) | 4 5 6 =
  // ←/→ は行 3-4 の中央に Stack 配置するためここでは空欄を確保するだけ
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
        // ↑ を中央に、左右は ←/→ を Stack で重ねるため空欄
        SizedBox(width: u),
        _key('↑', 0x3C, u, h),
        SizedBox(width: u),
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
        // 0 (1u), , (1u), . (1u), ENTER 領域 (1u, Stack で覆う)
        _key('0', 0x4F, u, h),
        _key(',', 0x50, u, h),
        _key('.', 0x51, u, h),
        SizedBox(width: u),
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
    final ledOn = _ledOn.contains(scancode);
    final hasLed = _ledBitToScancode.contains(scancode);

    // かな LED 点灯時はキー表示を JIS かなに置き換える
    final kanaActive = _ledOn.contains(0x5A);
    final kanaLabel = kanaActive ? _kanaLabels[scancode] : null;
    final displayLabels = kanaLabel != null ? <String>[kanaLabel] : labels;

    // LED 色分け (緑: ひらがな/全角, 赤: それ以外)
    final isGreen = _greenLedScancodes.contains(scancode);
    final ledColor = isGreen ? const Color(0xFF66FF88) : const Color(0xFFFF5555);
    final ledColorDim = isGreen ? const Color(0xFF1a3a1a) : const Color(0xFF3a1414);
    final ledGlow = isGreen ? const Color(0x8866FF88) : const Color(0x88FF5555);

    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // キー本体
          Padding(
            padding: const EdgeInsets.all(1.5),
            child: GestureDetector(
              onTapDown: (_) => _press(scancode),
              onTapUp: (_) => _release(scancode),
              onTapCancel: () => _release(scancode),
              child: Stack(
                children: [
                  Container(
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
                        children: displayLabels
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
                  if (hasLed)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Center(
                        child: Container(
                          // キー下端にぴったり付いた LED バー (実機の LED 表示風)
                          width: width * 0.5,
                          height: 6,
                          decoration: BoxDecoration(
                            color: ledOn
                                ? _applyBrightness(ledColor, _ledBrightness)
                                : ledColorDim,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(1),
                              topRight: Radius.circular(1),
                            ),
                            boxShadow: ledOn
                                ? [
                                    BoxShadow(
                                      color: _applyBrightness(ledGlow, _ledBrightness),
                                      blurRadius: 5,
                                      spreadRadius: 0.5,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // 押下時のポップアップ吹き出し (指で隠れたキーを上に表示)
          if (pressed) _buildKeyPopup(displayLabels, width),
        ],
      ),
    );
  }

  // 吹き出しを Positioned で上に重ねる
  Widget _buildKeyPopup(List<String> labels, double keyWidth) {
    final popupH = (_h > 0 ? _h : 40) * 1.1;
    final popupW = keyWidth.clamp(popupH * 1.0, double.infinity) * 1.2;
    return Positioned(
      // キー中央を基準に水平センタリング
      left: (keyWidth - popupW) / 2,
      // キー上端からポップアップ高さ分 + 余白を上方向に
      top: -(popupH + 6),
      child: IgnorePointer(
        child: Container(
          width: popupW,
          height: popupH,
          decoration: BoxDecoration(
            color: const Color(0xFF3399FF),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white, width: 1.5),
            boxShadow: const [
              BoxShadow(color: Colors.black54, blurRadius: 6, offset: Offset(0, 3)),
            ],
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: labels
                  .map((s) => Text(
                        s,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: _autoFontSize(s, popupW, popupH) * 1.2,
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

  // 輝度レベル (0=最も明るい, 3=最も暗い) を RGB に乗算 (alpha は維持)
  Color _applyBrightness(Color base, int level) {
    final f = _brightnessFactors[level.clamp(0, _brightnessFactors.length - 1)];
    return base.withValues(
      red: (base.r * f).clamp(0.0, 1.0),
      green: (base.g * f).clamp(0.0, 1.0),
      blue: (base.b * f).clamp(0.0, 1.0),
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
