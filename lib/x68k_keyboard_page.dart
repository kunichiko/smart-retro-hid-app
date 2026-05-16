// ===================================================================================
// X68000 仮想キーボード画面
// ===================================================================================
// レイアウトは X68000 実機キーボードを参考にした JIS 配列。
// スキャンコードはプロトコル仕様 Appendix A 参照。
// ===================================================================================

import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'channel_mode.dart';
import 'l10n/app_localizations.dart';
import 'midi_service.dart';
import 'mode_scaffold.dart';
import 'orientation_helper.dart';

// ===========================================================================
// X68kKeyboardPage 本体
// 当面はモードが 1 つ (StandardX68kMode) だけだが、将来フリック入力モード等を
// 増やす想定で ModeScaffold に乗せている。1 モードならドロップダウンは非表示。
// ===========================================================================

class X68kKeyboardPage extends StatefulWidget {
  final MidiService midi;
  final int channel;

  /// 同一デバイスがマウス機能も持つときの MIDI チャンネル。null ならトラックパッド非表示。
  final int? mouseChannel;

  const X68kKeyboardPage({
    super.key,
    required this.midi,
    this.channel = MidiService.chKeyboardDefault,
    this.mouseChannel,
  });

  @override
  State<X68kKeyboardPage> createState() => _X68kKeyboardPageState();
}

class _X68kKeyboardPageState extends State<X68kKeyboardPage> {
  late final List<ChannelMode> _modes;

  @override
  void initState() {
    super.initState();
    OrientationHelper.landscape();
    _modes = [
      StandardX68kMode(
        channel: widget.channel,
        mouseChannel: widget.mouseChannel,
      ),
    ];
  }

  @override
  void dispose() {
    for (final m in _modes) {
      m.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ModeScaffold(
      title: AppLocalizations.of(context)!.x68kKeyboardTitle,
      midi: widget.midi,
      modes: _modes,
    );
  }
}

// ===========================================================================
// X68000 標準キーボードモード
// テンキー / トラックパッドの表示トグルはこのモードの状態として保持し、
// AppBar アクションとして提供する。
// ===========================================================================

class StandardX68kMode extends ChannelMode {
  final int channel;
  final int? mouseChannel;

  bool _numpadVisible = true;
  bool _trackpadVisible = true;

  /// デスクトップ環境で複数キー同時押し相当を実現するための sticky 状態。
  /// 本体 (_X68kKeyboardBody) が読み書きし、AppBar の "全解除" ボタンも
  /// このコントローラを購読することで表示可否を切り替える。
  final StickyKeyController stickyController = StickyKeyController();

  StandardX68kMode({required this.channel, this.mouseChannel});

  @override
  String get id => 'x68k_keyboard.standard';

  @override
  String label(BuildContext context) =>
      AppLocalizations.of(context)!.x68kKeyboardTitle;

  void _toggleNumpad() {
    _numpadVisible = !_numpadVisible;
    notifyListeners();
  }

  void _toggleTrackpad() {
    _trackpadVisible = !_trackpadVisible;
    notifyListeners();
  }

  @override
  Widget buildBody(BuildContext context, MidiService midi) {
    return _X68kKeyboardBody(
      midi: midi,
      channel: channel,
      mouseChannel: mouseChannel,
      numpadVisible: _numpadVisible,
      trackpadVisible: _trackpadVisible,
      stickyController: stickyController,
    );
  }

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      // Sticky 全解除: stuck キーが 1 つ以上あるときだけ表示。
      ListenableBuilder(
        listenable: stickyController,
        builder: (_, __) {
          if (!stickyController.hasStuck) return const SizedBox.shrink();
          return IconButton(
            tooltip: 'Sticky を全て解除',
            icon: const Icon(Icons.lock_open),
            onPressed: stickyController.onReleaseAllRequested,
          );
        },
      ),
      if (mouseChannel != null)
        IconButton(
          tooltip: _trackpadVisible ? 'トラックパッドを非表示' : 'トラックパッドを表示',
          icon: Icon(
              _trackpadVisible ? Icons.touch_app : Icons.touch_app_outlined),
          onPressed: _toggleTrackpad,
        ),
      IconButton(
        tooltip: _numpadVisible ? 'テンキーを非表示' : 'テンキーを表示',
        icon: Icon(_numpadVisible ? Icons.dialpad : Icons.dialpad_outlined),
        onPressed: _toggleNumpad,
      ),
    ];
  }

  @override
  void dispose() {
    stickyController.dispose();
    super.dispose();
  }
}

// ===========================================================================
// 複数キー同時押し用 sticky 状態の共有コントローラ
//
// マウスクリック (= デスクトップ) では指 1 本ぶんしか押せないため、
//   - 左クリック (左タップ): Modifier キー (SHIFT/CTRL/OPT/XF) は自動 sticky、
//                          すでに stuck のキーは 1 クリックで解除
//   - 右クリック        : 任意キーの sticky を toggle
// という UX を提供する。タッチ入力 (kind != mouse) では従来通り押下中だけ
// 反応する。AppBar の "全解除" ボタンと本体側で状態を共有するためにこの
// ChangeNotifier 経由でやり取りする。
// ===========================================================================

class StickyKeyController extends ChangeNotifier {
  final Set<int> _stuck = {};

  Set<int> get stuck => Set.unmodifiable(_stuck);
  bool get hasStuck => _stuck.isNotEmpty;
  bool isStuck(int code) => _stuck.contains(code);

  bool add(int code) {
    final added = _stuck.add(code);
    if (added) notifyListeners();
    return added;
  }

  bool remove(int code) {
    final removed = _stuck.remove(code);
    if (removed) notifyListeners();
    return removed;
  }

  void clear() {
    if (_stuck.isEmpty) return;
    _stuck.clear();
    notifyListeners();
  }

  /// body 側が initState で登録する「全 stuck 解除」コールバック。
  /// AppBar の解除ボタンはこの参照を経由して body の処理を呼ぶ。
  VoidCallback? onReleaseAllRequested;
}

/// 左クリック (kind == mouse) で自動 sticky する Modifier 系スキャンコード。
/// LED 系 (かな/CAPS/INS 等) は X68k 側で push 1 回でトグルする仕様なので、
/// sticky 化しなくてもデスクトップから操作可能。
const Set<int> _stickyModifierScancodes = {
  0x55, // XF1
  0x56, // XF2
  0x57, // XF3
  0x58, // XF4
  0x59, // XF5
  0x70, // SHIFT
  0x71, // CTRL
  0x72, // OPT.1
  0x73, // OPT.2
};

// ===========================================================================
// キーボード本体 Widget。AppBar 以外のすべての本体ロジック
// (キー押下/リリース、リピート、ポップアップ、LED 状態、レイアウト等) を担う。
// ===========================================================================

class _X68kKeyboardBody extends StatefulWidget {
  final MidiService midi;
  final int channel;
  final int? mouseChannel;
  final bool numpadVisible;
  final bool trackpadVisible;
  final StickyKeyController stickyController;

  const _X68kKeyboardBody({
    required this.midi,
    required this.channel,
    required this.mouseChannel,
    required this.numpadVisible,
    required this.trackpadVisible,
    required this.stickyController,
  });

  @override
  State<_X68kKeyboardBody> createState() => _X68kKeyboardBodyState();
}

class _X68kKeyboardBodyState extends State<_X68kKeyboardBody> {
  // 押下中のキー (重複送信防止用)
  final Set<int> _pressed = {};

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

  // X68000 JIS かな配列: かな ON + ひらがな ON のとき表示
  static const Map<int, String> _hiraganaLabels = {
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

  // かな ON + ひらがな OFF のとき表示するカタカナラベル
  static const Map<int, String> _katakanaLabels = {
    0x02: 'ヌ', 0x03: 'フ', 0x04: 'ア', 0x05: 'ウ', 0x06: 'エ',
    0x07: 'オ', 0x08: 'ヤ', 0x09: 'ユ', 0x0A: 'ヨ', 0x0B: 'ワ',
    0x0C: 'ホ', 0x0D: 'ヘ', 0x0E: 'ー',
    0x11: 'タ', 0x12: 'テ', 0x13: 'イ', 0x14: 'ス', 0x15: 'カ',
    0x16: 'ン', 0x17: 'ナ', 0x18: 'ニ', 0x19: 'ラ', 0x1A: 'セ',
    0x1B: '゛', 0x1C: '゜',
    0x1E: 'チ', 0x1F: 'ト', 0x20: 'シ', 0x21: 'ハ', 0x22: 'キ',
    0x23: 'ク', 0x24: 'マ', 0x25: 'ノ', 0x26: 'リ', 0x27: 'レ',
    0x28: 'ケ', 0x29: 'ム',
    0x2A: 'ツ', 0x2B: 'サ', 0x2C: 'ソ', 0x2D: 'ヒ', 0x2E: 'コ',
    0x2F: 'ミ', 0x30: 'モ', 0x31: 'ネ', 0x32: 'ル', 0x33: 'メ',
    0x34: 'ロ',
  };

  // かな OFF + SHIFT 押下時に表示する記号 (X68000 JIS 配列)
  static const Map<int, String> _shiftLabels = {
    0x02: '!',  0x03: '"',  0x04: '#',  0x05: '\$', 0x06: '%',
    0x07: '&',  0x08: '\'', 0x09: '(',  0x0A: ')',
    0x0C: '=',  0x0D: '~',  0x0E: '|',
    0x31: '<',  0x32: '>',  0x33: '?',
  };

  // キーリピート (X68000 の SET REPEAT START / RATE コマンドで可変)
  Timer? _repeatTimer;
  int? _repeatScancode;
  int _repeatDelayMs = 500;     // 0b0110dddd: 200 + dddd*100 ms (default dddd=3)
  int _repeatIntervalMs = 110;  // 0b0111rrrr: 30 + rrrr²*5 ms (default rrrr=4)

  // リピートさせないキー (モディファイア / LED トグル系)
  //   0x5A: かな        0x5B: ローマ字    0x5C: コード入力
  //   0x5D: CAPS        0x5E: INS         0x5F: ひらがな   0x60: 全角
  //   0x70: SHIFT       0x71: CTRL        0x72: OPT.1      0x73: OPT.2
  static const Set<int> _noRepeatScancodes = {
    0x5A, 0x5B, 0x5C, 0x5D, 0x5E, 0x5F, 0x60,
    0x70, 0x71, 0x72, 0x73,
  };

  // 押下ポップアップの表示制御。短いタップでも一定時間は表示しておく
  static const Duration _popupMinShow = Duration(milliseconds: 250);
  // 連打時に「一旦消えて再表示」して視覚的にカウントできるようにするための短い間
  static const Duration _popupBlinkGap = Duration(milliseconds: 30);
  final Map<int, Timer> _popupHideTimers = {};
  Timer? _popupShowTimer;
  // ポップアップは Overlay にエントリを差し込んで AppBar 含む最上層に描画する
  final Map<int, OverlayEntry> _popupOverlays = {};

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
    // 横向き固定は外側の X68kKeyboardPage で済ませてある。
    _prevTargetRxHandler = widget.midi.onTargetRx;
    widget.midi.onTargetRx = _handleTargetRx;

    // AppBar の "全解除" ボタンから呼ばれるコールバックを登録。
    widget.stickyController.onReleaseAllRequested = _releaseAllStuck;
    // sticky 状態が変わったらキー描画を更新する。
    widget.stickyController.addListener(_onStickyChanged);

    // デスクトップ / 外付け物理キーボードからのキーイベントを購読する。
    // Focus を介さない全域ハンドラなので AppBar 操作中でもキーが拾える。
    HardwareKeyboard.instance.addHandler(_handlePhysicalKey);
  }

  void _onStickyChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _repeatTimer?.cancel();
    _popupShowTimer?.cancel();
    for (final t in _popupHideTimers.values) {
      t.cancel();
    }
    _popupHideTimers.clear();
    for (final entry in _popupOverlays.values) {
      entry.remove();
    }
    _popupOverlays.clear();
    widget.midi.onTargetRx = _prevTargetRxHandler;
    // 退場時に sticky で残っている分を全て NoteOff してから controller を切る。
    _releaseAllStuck();
    widget.stickyController.removeListener(_onStickyChanged);
    widget.stickyController.onReleaseAllRequested = null;
    HardwareKeyboard.instance.removeHandler(_handlePhysicalKey);
    super.dispose();
  }

  // ===========================================================================
  // Sticky (押しっぱなし) ロジック — デスクトップで複数キー同時押し相当を実現
  // ===========================================================================

  /// 指定キーを sticky にする (まだなければ press 状態も併せて作る)。
  void _stickKey(int code) {
    if (widget.stickyController.isStuck(code)) return;
    widget.stickyController.add(code);
    if (!_pressed.contains(code)) {
      _pressed.add(code);
      widget.midi.sendNoteOn(widget.channel, code, 127);
      HapticFeedback.lightImpact();
    }
    if (mounted) setState(() {});
  }

  /// 指定キーの sticky を解除して NoteOff も送る。
  void _unstickKey(int code) {
    if (!widget.stickyController.isStuck(code)) return;
    widget.stickyController.remove(code);
    if (_pressed.remove(code)) {
      widget.midi.sendNoteOff(widget.channel, code);
    }
    if (mounted) setState(() {});
  }

  /// AppBar の "全解除" から呼ばれる。
  void _releaseAllStuck() {
    final stuck = widget.stickyController.stuck;
    if (stuck.isEmpty) return;
    for (final code in stuck) {
      if (_pressed.remove(code)) {
        widget.midi.sendNoteOff(widget.channel, code);
      }
    }
    widget.stickyController.clear();
    if (mounted) setState(() {});
  }

  /// 左クリック / タップ時の振り分け。
  ///   - kind == mouse かつ stuck   : 解除のみ (押下は発生させない)
  ///   - kind == mouse かつ sticky 対象 modifier : 自動 sticky
  ///   - それ以外 : 通常の momentary press (タッチ動作互換)
  /// 「sticky 化または解除されたのでこのタップは release を発火させない」場合
  /// に true を返す。
  bool _handleKeyDown(int code, TapDownDetails details, BuildContext keyCtx,
      List<String> labels) {
    if (details.kind == PointerDeviceKind.mouse) {
      if (widget.stickyController.isStuck(code)) {
        _unstickKey(code);
        return true;
      }
      if (_stickyModifierScancodes.contains(code)) {
        _stickKey(code);
        return true;
      }
    }
    _press(code, keyCtx, labels);
    return false;
  }

  /// 右クリック (二次タップ) は任意キーの sticky を toggle する。
  void _handleSecondaryTap(int code) {
    if (widget.stickyController.isStuck(code)) {
      _unstickKey(code);
    } else {
      _stickKey(code);
    }
  }

  // ===========================================================================
  // 物理キーボード直接入力
  // ===========================================================================
  //
  // LogicalKeyboardKey → X68000 スキャンコード のマッピング。
  // 基本的に JIS 配列前提でレイアウトしてある (X68000 自体が JIS)。
  // 記号系の一部は US 配列だと別の物理キー位置になるが、X68k のレイアウトを
  // 真とする方針なので「ホストで打った文字 = X68k 側のキー」と捉えて欲しい。
  static final Map<LogicalKeyboardKey, int> _physicalKeyMap = {
    // 文字キー
    LogicalKeyboardKey.keyA: 0x1E, LogicalKeyboardKey.keyB: 0x2E,
    LogicalKeyboardKey.keyC: 0x2C, LogicalKeyboardKey.keyD: 0x20,
    LogicalKeyboardKey.keyE: 0x13, LogicalKeyboardKey.keyF: 0x21,
    LogicalKeyboardKey.keyG: 0x22, LogicalKeyboardKey.keyH: 0x23,
    LogicalKeyboardKey.keyI: 0x18, LogicalKeyboardKey.keyJ: 0x24,
    LogicalKeyboardKey.keyK: 0x25, LogicalKeyboardKey.keyL: 0x26,
    LogicalKeyboardKey.keyM: 0x30, LogicalKeyboardKey.keyN: 0x2F,
    LogicalKeyboardKey.keyO: 0x19, LogicalKeyboardKey.keyP: 0x1A,
    LogicalKeyboardKey.keyQ: 0x11, LogicalKeyboardKey.keyR: 0x14,
    LogicalKeyboardKey.keyS: 0x1F, LogicalKeyboardKey.keyT: 0x15,
    LogicalKeyboardKey.keyU: 0x17, LogicalKeyboardKey.keyV: 0x2D,
    LogicalKeyboardKey.keyW: 0x12, LogicalKeyboardKey.keyX: 0x2B,
    LogicalKeyboardKey.keyY: 0x16, LogicalKeyboardKey.keyZ: 0x2A,
    // 数字キー
    LogicalKeyboardKey.digit1: 0x02, LogicalKeyboardKey.digit2: 0x03,
    LogicalKeyboardKey.digit3: 0x04, LogicalKeyboardKey.digit4: 0x05,
    LogicalKeyboardKey.digit5: 0x06, LogicalKeyboardKey.digit6: 0x07,
    LogicalKeyboardKey.digit7: 0x08, LogicalKeyboardKey.digit8: 0x09,
    LogicalKeyboardKey.digit9: 0x0A, LogicalKeyboardKey.digit0: 0x0B,
    // 制御キー
    LogicalKeyboardKey.escape: 0x01,
    LogicalKeyboardKey.backspace: 0x0F,
    LogicalKeyboardKey.tab: 0x10,
    LogicalKeyboardKey.enter: 0x1D,
    LogicalKeyboardKey.space: 0x35,
    // 矢印
    LogicalKeyboardKey.arrowUp: 0x3C,
    LogicalKeyboardKey.arrowDown: 0x3E,
    LogicalKeyboardKey.arrowLeft: 0x3B,
    LogicalKeyboardKey.arrowRight: 0x3D,
    // モディファイア (左右どちらも同じ X68k キーに割り当て)
    LogicalKeyboardKey.shiftLeft: 0x70,
    LogicalKeyboardKey.shiftRight: 0x70,
    LogicalKeyboardKey.controlLeft: 0x71,
    LogicalKeyboardKey.controlRight: 0x71,
    LogicalKeyboardKey.altLeft: 0x72,  // OPT.1
    LogicalKeyboardKey.altRight: 0x73, // OPT.2
    // ファンクションキー
    LogicalKeyboardKey.f1: 0x63, LogicalKeyboardKey.f2: 0x64,
    LogicalKeyboardKey.f3: 0x65, LogicalKeyboardKey.f4: 0x66,
    LogicalKeyboardKey.f5: 0x67, LogicalKeyboardKey.f6: 0x68,
    LogicalKeyboardKey.f7: 0x69, LogicalKeyboardKey.f8: 0x6A,
    LogicalKeyboardKey.f9: 0x6B, LogicalKeyboardKey.f10: 0x6C,
    // 編集 / ナビゲーション
    LogicalKeyboardKey.home: 0x36,
    LogicalKeyboardKey.delete: 0x37,
    LogicalKeyboardKey.insert: 0x5E,
    LogicalKeyboardKey.pageUp: 0x38,    // ROLL UP
    LogicalKeyboardKey.pageDown: 0x39,  // ROLL DOWN
    LogicalKeyboardKey.capsLock: 0x5D,
    // 記号 (US/JIS 共通)
    LogicalKeyboardKey.minus: 0x0C,
    LogicalKeyboardKey.comma: 0x31,
    LogicalKeyboardKey.period: 0x32,
    LogicalKeyboardKey.slash: 0x33,
    LogicalKeyboardKey.semicolon: 0x27,
    // 記号系の追加マッピング。LogicalKeyboardKey は USASCII 文字基準の命名なので、
    // 「produced character = JIS のキー」と読めば素直に対応する。
    // JIS 配列で専用キーがあるもの (caret / at / colon / yen / ro) と、US/JIS で
    // 同一文字を出すブラケット記号、US 配列固有の backslash まで網羅する。
    LogicalKeyboardKey.caret: 0x0D,         // ^
    LogicalKeyboardKey.intlYen: 0x0E,       // ¥
    LogicalKeyboardKey.at: 0x1B,            // @ (JIS 専用キー)
    LogicalKeyboardKey.bracketLeft: 0x1C,   // [
    LogicalKeyboardKey.colon: 0x28,         // : (JIS 専用キー)
    LogicalKeyboardKey.bracketRight: 0x29,  // ]
    LogicalKeyboardKey.intlRo: 0x34,        // _ (JIS 専用キーの素押し)
    LogicalKeyboardKey.underscore: 0x34,    // _ (OS 側で shift 解決される場合)
    LogicalKeyboardKey.backslash: 0x0E,     // \ (US 専用キー → JIS ¥ と等価)
    // テンキー (numpad)。OS は NumLock 状態に依らず logical key を出す。
    LogicalKeyboardKey.numpad0: 0x4F,
    LogicalKeyboardKey.numpad1: 0x4B,
    LogicalKeyboardKey.numpad2: 0x4C,
    LogicalKeyboardKey.numpad3: 0x4D,
    LogicalKeyboardKey.numpad4: 0x47,
    LogicalKeyboardKey.numpad5: 0x48,
    LogicalKeyboardKey.numpad6: 0x49,
    LogicalKeyboardKey.numpad7: 0x43,
    LogicalKeyboardKey.numpad8: 0x44,
    LogicalKeyboardKey.numpad9: 0x45,
    LogicalKeyboardKey.numpadDecimal: 0x51,
    LogicalKeyboardKey.numpadComma: 0x50,
    LogicalKeyboardKey.numpadEnter: 0x4E,
    LogicalKeyboardKey.numpadAdd: 0x46,
    LogicalKeyboardKey.numpadSubtract: 0x42,
    LogicalKeyboardKey.numpadMultiply: 0x41,
    LogicalKeyboardKey.numpadDivide: 0x40,
    LogicalKeyboardKey.numpadEqual: 0x4A,
  };

  /// HardwareKeyboard コールバック。マップにあるキーだけハンドルし、それ以外は
  /// false を返して他のリスナ (OS ショートカット等) に処理を委譲する。
  bool _handlePhysicalKey(KeyEvent event) {
    final scancode = _physicalKeyMap[event.logicalKey];
    if (scancode == null) return false;

    if (event is KeyDownEvent) {
      _physicalKeyDown(scancode);
      return true;
    }
    if (event is KeyUpEvent) {
      _physicalKeyUp(scancode);
      return true;
    }
    // OS のオートリピートはファームが repeat 管理するため NoteOn 重発は不要。
    // ただし return false にすると macOS が「未処理キー」と見なして NSBeep を
    // 鳴らすので、イベント自体は consume (return true) して握りつぶす。
    if (event is KeyRepeatEvent) {
      return true;
    }
    return false;
  }

  void _physicalKeyDown(int code) {
    // 既に押されている (sticky 等) なら二重 NoteOn を避ける
    if (_pressed.contains(code)) return;
    _pressed.add(code);
    widget.midi.sendNoteOn(widget.channel, code, 127);
    // 物理キーボードはホスト OS が自前でオートリピート (KeyRepeatEvent) を
    // 発行するので、アプリ側で _scheduleRepeat する必要はない。OS の repeat
    // イベントは _handlePhysicalKey で握りつぶしてあるため、結局 NoteOn は
    // 1 回だけ送られ、X68k 側のリピートロジックに委ねる形になる。
    if (mounted) setState(() {});
  }

  void _physicalKeyUp(int code) {
    // sticky 中は物理キーの release で解除しない (画面上の sticky を尊重)
    if (widget.stickyController.isStuck(code)) return;
    if (_pressed.remove(code)) {
      if (_repeatScancode == code) {
        _repeatTimer?.cancel();
        _repeatScancode = null;
      }
      widget.midi.sendNoteOff(widget.channel, code);
      if (mounted) setState(() {});
    }
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

  void _press(int code, BuildContext keyCtx, List<String> labels) {
    if (_pressed.add(code)) {
      widget.midi.sendNoteOn(widget.channel, code, 127);
      HapticFeedback.lightImpact();
      if (!_noRepeatScancodes.contains(code)) {
        _scheduleRepeat(code);
      }
    }
    // 別キー/同キーのいずれの再押下でも、まず既存ポップアップを即時消す
    // (連打時に "ポン・ポン" と分かれて見えるように)
    _popupShowTimer?.cancel();
    for (final t in _popupHideTimers.values) {
      t.cancel();
    }
    _popupHideTimers.clear();
    _hideAllPopupOverlays();
    setState(() {});

    // ごく短い間ブランクにしてから今回の押下キーを表示
    _popupShowTimer = Timer(_popupBlinkGap, () {
      if (!mounted) return;
      _showPopupOverlay(code, keyCtx, labels);
    });
  }

  void _release(int code) {
    // sticky 中のキーは指を離しても release しない (押しっぱなしを維持)。
    if (widget.stickyController.isStuck(code)) {
      return;
    }
    if (_pressed.remove(code)) {
      if (_repeatScancode == code) {
        _repeatTimer?.cancel();
        _repeatScancode = null;
      }
      widget.midi.sendNoteOff(widget.channel, code);
    }
    // 短いタップでも吹き出しが視認できるよう、最低表示時間後に消す
    _popupHideTimers.remove(code)?.cancel();
    _popupHideTimers[code] = Timer(_popupMinShow, () {
      if (!mounted) return;
      _popupOverlays.remove(code)?.remove();
      _popupHideTimers.remove(code);
    });
    setState(() {});
  }

  void _hideAllPopupOverlays() {
    for (final entry in _popupOverlays.values) {
      entry.remove();
    }
    _popupOverlays.clear();
  }

  // OverlayEntry を挿入してキー上方に吹き出しを描画する。
  // Overlay は Scaffold (AppBar 含む) の上に描画されるので、最上段キーでも隠れない。
  void _showPopupOverlay(int scancode, BuildContext keyCtx, List<String> labels) {
    if (!mounted) return;
    final box = keyCtx.findRenderObject();
    if (box is! RenderBox || !box.attached) return;

    final origin = box.localToGlobal(Offset.zero);
    final keySize = box.size;

    final popupH = (_h > 0 ? _h : 40) * 1.1;
    final popupW = (keySize.width * 1.2).clamp(popupH, double.infinity);

    final left = origin.dx + (keySize.width - popupW) / 2;
    final top = origin.dy - popupH - 6;

    final entry = OverlayEntry(
      builder: (ctx) => Positioned(
        left: left,
        top: top,
        width: popupW,
        height: popupH,
        child: IgnorePointer(child: _popupContent(labels, popupW, popupH)),
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(entry);
    _popupOverlays[scancode] = entry;
  }

  Widget _popupContent(List<String> labels, double w, double h) {
    return Container(
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
                      fontSize: _autoFontSize(s, w, h) * 1.2,
                      height: 1.0,
                    ),
                  ))
              .toList(),
        ),
      ),
    );
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
    final hasMouse = widget.mouseChannel != null;
    // 背景色は ModeScaffold ではなく body 側で持つ (キーボードページの黒地)。
    return Container(
      color: const Color(0xFF1a1a1a),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final showTrackpad = hasMouse && widget.trackpadVisible;
            if (!showTrackpad) {
              return _buildKeyboard(constraints);
            }
            // トラックパッドの最小高 (これ以上は確保する)
            const trackpadMinH = 100.0;
            // キーボードに与えられる最大高さ
            final maxKbH =
                (constraints.maxHeight - trackpadMinH).clamp(0.0, double.infinity);
            // キーボードは幅でも高さでもはみ出さないよう u を計算
            final keyboard = _buildKeyboard(BoxConstraints(
              maxWidth: constraints.maxWidth,
              maxHeight: maxKbH,
            ));
            return Column(
              children: [
                keyboard,
                Expanded(
                  child: _TrackpadArea(
                    midi: widget.midi,
                    channel: widget.mouseChannel!,
                  ),
                ),
              ],
            );
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

  double get _totalW => widget.numpadVisible
      ? _mainAreaW + _gap + _cursorAreaW + _gap + _numpadAreaW
      : _mainAreaW + _gap + _cursorAreaW;

  // キーボードの行構成: function row + 4 main rows + bottom row = 6 行 + fnGap(=0.15h)
  // 合計コンテンツ高 = 6.15 * h = 6.15 * 0.95 * u = ~5.8425 * u
  // パディング (innerPad * 2 = 16) を加えて keyboardH = 5.8425*u + 16
  static const double _rowsPerH = 6.15;
  static const double _hPerU = 0.95;

  Widget _buildKeyboard(BoxConstraints constraints) {
    // 各キーは declared width 内にパディングを内包するため、unit 計算は単純な分割で OK
    final outerPadding = 16.0;
    final innerPad = 8.0;
    final innerPadTotal = innerPad * 2;

    final availableW = constraints.maxWidth - outerPadding;
    final uByWidth = availableW / _totalW;
    // 高さ制約があれば、それを超えないように u を制限する
    double u = uByWidth;
    if (constraints.maxHeight.isFinite) {
      final availableH = constraints.maxHeight - innerPadTotal;
      if (availableH > 0) {
        final uByHeight = availableH / (_rowsPerH * _hPerU);
        if (uByHeight < u) u = uByHeight;
      }
    }
    final h = u * _hPerU;
    _h = h;  // ポップアップサイズ計算用に保存

    // 縦長キー (Return / numpad ENTER) を Stack で重ねるための位置計算
    // Y 位置: function row(h) + gap(0.15h) + 累積行
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

    return Stack(
      clipBehavior: Clip.none,
      children: [
          Padding(
            padding: EdgeInsets.all(innerPad),
            child: Column(
              mainAxisSize: MainAxisSize.min,
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
          if (widget.numpadVisible)
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
  // widget.numpadVisible=false のときは numpad 部分を完全に省略する
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
        if (widget.numpadVisible) ...[
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
    final stuck = widget.stickyController.isStuck(scancode);
    final ledOn = _ledOn.contains(scancode);
    final hasLed = _ledBitToScancode.contains(scancode);

    // 表示ラベル切替:
    //   かな ON + ひらがな ON  → ひらがな
    //   かな ON + ひらがな OFF → カタカナ
    //   かな OFF + SHIFT       → JIS 記号 (1-0 段、,./)
    //   それ以外               → 通常の英数記号
    final kanaActive = _ledOn.contains(0x5A);
    final hiraganaActive = _ledOn.contains(0x5F);
    final shiftPressed = _pressed.contains(0x70);
    String? overrideLabel;
    if (kanaActive) {
      overrideLabel = hiraganaActive
          ? _hiraganaLabels[scancode]
          : _katakanaLabels[scancode];
    } else if (shiftPressed) {
      overrideLabel = _shiftLabels[scancode];
    }
    final displayLabels =
        overrideLabel != null ? <String>[overrideLabel] : labels;

    // LED 色分け (緑: ひらがな/全角, 赤: それ以外)
    final isGreen = _greenLedScancodes.contains(scancode);
    final ledColor = isGreen ? const Color(0xFF66FF88) : const Color(0xFFFF5555);
    final ledColorDim = isGreen ? const Color(0xFF1a3a1a) : const Color(0xFF3a1414);
    final ledGlow = isGreen ? const Color(0x8866FF88) : const Color(0x88FF5555);

    // ポップアップは Overlay で描画するため、各キーの BuildContext を Builder で確保
    return Builder(
      builder: (keyCtx) => SizedBox(
        width: width,
        height: height,
        child: Padding(
          padding: const EdgeInsets.all(1.5),
          child: GestureDetector(
            onTapDown: (d) => _handleKeyDown(scancode, d, keyCtx, displayLabels),
            onTapUp: (_) => _release(scancode),
            onTapCancel: () => _release(scancode),
            // 右クリック / 二次タップ: 任意キーを sticky toggle
            onSecondaryTap: () => _handleSecondaryTap(scancode),
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    // sticky 中はオレンジで塗り、押下中 (sticky 含む) は明色背景にする。
                    color: pressed
                        ? const Color(0xFF505050)
                        : const Color(0xFF222222),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: stuck
                          ? const Color(0xFFFFB300) // amber (sticky)
                          : pressed
                              ? Colors.white
                              : const Color(0xFF555555),
                      width: (stuck || pressed) ? 2 : 1,
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

// =============================================================================
// マウス トラックパッド + 左右ボタン
// =============================================================================
// プロトコル仕様 §4.3 準拠:
//   Note On/Off ch=mouse, note=0(L)/1(R)
//   CC ch=mouse, control=0x30(dX)/0x31(dY), value=64+delta (-64..+63)
// =============================================================================

class _TrackpadArea extends StatelessWidget {
  final MidiService midi;
  final int channel;
  const _TrackpadArea({required this.midi, required this.channel});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Row(
        children: [
          _MouseButton(
            midi: midi, channel: channel, note: 0,  // 左ボタン
            label: 'L',
          ),
          const SizedBox(width: 6),
          Expanded(child: _TrackpadSurface(midi: midi, channel: channel)),
          const SizedBox(width: 6),
          _MouseButton(
            midi: midi, channel: channel, note: 1,  // 右ボタン
            label: 'R',
          ),
        ],
      ),
    );
  }
}

class _MouseButton extends StatefulWidget {
  final MidiService midi;
  final int channel;
  final int note;
  final String label;
  const _MouseButton({
    required this.midi,
    required this.channel,
    required this.note,
    required this.label,
  });
  @override
  State<_MouseButton> createState() => _MouseButtonState();
}

class _MouseButtonState extends State<_MouseButton> {
  bool _pressed = false;

  void _down() {
    if (_pressed) return;
    setState(() => _pressed = true);
    widget.midi.sendNoteOn(widget.channel, widget.note, 127);
    HapticFeedback.lightImpact();
  }

  void _up() {
    if (!_pressed) return;
    setState(() => _pressed = false);
    widget.midi.sendNoteOff(widget.channel, widget.note);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _down(),
      onTapUp: (_) => _up(),
      onTapCancel: () => _up(),
      child: Container(
        width: 56,
        decoration: BoxDecoration(
          color: _pressed ? const Color(0xFF505050) : const Color(0xFF222222),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: _pressed ? Colors.white : const Color(0xFF555555),
            width: _pressed ? 2 : 1,
          ),
        ),
        child: Center(
          child: Text(
            widget.label,
            style: TextStyle(
              color: _pressed ? Colors.white : Colors.grey.shade300,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}

class _TrackpadSurface extends StatefulWidget {
  final MidiService midi;
  final int channel;
  const _TrackpadSurface({required this.midi, required this.channel});
  @override
  State<_TrackpadSurface> createState() => _TrackpadSurfaceState();
}

class _TrackpadSurfaceState extends State<_TrackpadSurface> {
  static const int _ccDx = 0x30;
  static const int _ccDy = 0x31;
  static const int _noteLeft = 0;
  // 1 ピクセル = 何マウスカウントか。実機の感度に合わせて軽く調整可
  static const double _sensitivity = 1.0;
  static const Duration _flushPeriod = Duration(milliseconds: 16);

  double _accumDx = 0;
  double _accumDy = 0;
  Timer? _flushTimer;

  // 各 pan 開始時の指の位置を覚えておき、ここからの相対量を取る
  // (DragUpdateDetails.delta が pan 境界をまたぐ際に変な値になるケース対策)
  Offset? _lastPos;

  @override
  void initState() {
    super.initState();
    _flushTimer = Timer.periodic(_flushPeriod, (_) => _flush());
  }

  @override
  void dispose() {
    _flushTimer?.cancel();
    super.dispose();
  }

  void _flush() {
    var dx = _accumDx.round();
    var dy = _accumDy.round();
    if (dx == 0 && dy == 0) return;
    _accumDx -= dx;
    _accumDy -= dy;

    // CC は 7 bit (-64..+63) なので、超える分は連続送信して累積させる (§4.3.3)
    while (dx != 0) {
      final chunk = dx.clamp(-63, 63);
      widget.midi.sendCC(widget.channel, _ccDx, 64 + chunk);
      dx -= chunk;
    }
    while (dy != 0) {
      final chunk = dy.clamp(-63, 63);
      widget.midi.sendCC(widget.channel, _ccDy, 64 + chunk);
      dy -= chunk;
    }
  }

  void _onPanStart(DragStartDetails d) {
    _lastPos = d.localPosition;
  }

  void _onPanUpdate(DragUpdateDetails d) {
    final last = _lastPos;
    if (last == null) {
      // onPanStart を経由しない場合の保険
      _lastPos = d.localPosition;
      return;
    }
    final dx = d.localPosition.dx - last.dx;
    final dy = d.localPosition.dy - last.dy;
    _lastPos = d.localPosition;
    _accumDx += dx * _sensitivity;
    _accumDy += dy * _sensitivity;
  }

  void _onPanEnd(DragEndDetails d) {
    _lastPos = null;
  }

  void _onPanCancel() {
    _lastPos = null;
  }

  // タップ = 左クリック (Note On → 短い遅延 → Note Off)
  void _onTap() {
    HapticFeedback.lightImpact();
    widget.midi.sendNoteOn(widget.channel, _noteLeft, 127);
    Future.delayed(const Duration(milliseconds: 40), () {
      widget.midi.sendNoteOff(widget.channel, _noteLeft);
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: _onPanStart,
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      onPanCancel: _onPanCancel,
      onTap: _onTap,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1a1f24),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF555555)),
        ),
        child: const Center(
          child: Text(
            'TRACKPAD',
            style: TextStyle(
              color: Color(0xFF444444),
              fontSize: 14,
              letterSpacing: 4,
            ),
          ),
        ),
      ),
    );
  }
}
