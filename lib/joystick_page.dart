import 'package:flutter/material.dart';
import 'midi_service.dart';

enum PadMode { atari, md6 }

class JoystickPage extends StatefulWidget {
  final MidiService midi;

  const JoystickPage({super.key, required this.midi});

  @override
  State<JoystickPage> createState() => _JoystickPageState();
}

class _JoystickPageState extends State<JoystickPage> {
  PadMode _mode = PadMode.atari;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Joystick'),
        actions: [
          SegmentedButton<PadMode>(
            segments: const [
              ButtonSegment(value: PadMode.atari, label: Text('ATARI')),
              ButtonSegment(value: PadMode.md6, label: Text('MD 6B')),
            ],
            selected: {_mode},
            onSelectionChanged: (v) {
              setState(() => _mode = v.first);
              widget.midi.setPadMode(_mode == PadMode.atari ? 0 : 1);
            },
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: _mode == PadMode.atari
          ? _AtariLayout(midi: widget.midi)
          : _Md6Layout(midi: widget.midi),
    );
  }
}

// ---------------------------------------------------------------------------
// スライド対応十字キー
// ---------------------------------------------------------------------------

class _DPad extends StatefulWidget {
  final MidiService midi;
  const _DPad({required this.midi});

  @override
  State<_DPad> createState() => _DPadState();
}

class _DPadState extends State<_DPad> {
  bool _up = false, _down = false, _left = false, _right = false;

  void _updateDirection(Offset? localPos, double size) {
    if (localPos == null) {
      _setAll(false, false, false, false);
      return;
    }
    final center = size / 2;
    final dx = localPos.dx - center;
    final dy = localPos.dy - center;
    final deadZone = size * 0.15;

    final newUp = dy < -deadZone;
    final newDown = dy > deadZone;
    final newLeft = dx < -deadZone;
    final newRight = dx > deadZone;
    _setAll(newUp, newDown, newLeft, newRight);
  }

  void _setAll(bool up, bool down, bool left, bool right) {
    if (up != _up) {
      _up = up;
      up ? widget.midi.joystickPress(MidiService.noteUp)
         : widget.midi.joystickRelease(MidiService.noteUp);
    }
    if (down != _down) {
      _down = down;
      down ? widget.midi.joystickPress(MidiService.noteDown)
           : widget.midi.joystickRelease(MidiService.noteDown);
    }
    if (left != _left) {
      _left = left;
      left ? widget.midi.joystickPress(MidiService.noteLeft)
           : widget.midi.joystickRelease(MidiService.noteLeft);
    }
    if (right != _right) {
      _right = right;
      right ? widget.midi.joystickPress(MidiService.noteRight)
            : widget.midi.joystickRelease(MidiService.noteRight);
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    const size = 200.0;
    return GestureDetector(
      onPanStart: (d) => _updateDirection(d.localPosition, size),
      onPanUpdate: (d) => _updateDirection(d.localPosition, size),
      onPanEnd: (_) => _updateDirection(null, size),
      onPanCancel: () => _updateDirection(null, size),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.grey.shade900,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Stack(
          children: [
            // 上
            Align(
              alignment: Alignment.topCenter,
              child: _DPadArrow(
                icon: Icons.arrow_drop_up,
                active: _up,
                width: 64,
                height: 60,
              ),
            ),
            // 下
            Align(
              alignment: Alignment.bottomCenter,
              child: _DPadArrow(
                icon: Icons.arrow_drop_down,
                active: _down,
                width: 64,
                height: 60,
              ),
            ),
            // 左
            Align(
              alignment: Alignment.centerLeft,
              child: _DPadArrow(
                icon: Icons.arrow_left,
                active: _left,
                width: 60,
                height: 64,
              ),
            ),
            // 右
            Align(
              alignment: Alignment.centerRight,
              child: _DPadArrow(
                icon: Icons.arrow_right,
                active: _right,
                width: 60,
                height: 64,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DPadArrow extends StatelessWidget {
  final IconData icon;
  final bool active;
  final double width;
  final double height;

  const _DPadArrow({
    required this.icon,
    required this.active,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: active ? Colors.white24 : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 40, color: active ? Colors.white : Colors.grey),
    );
  }
}

// ---------------------------------------------------------------------------
// ATARI レイアウト
// ---------------------------------------------------------------------------

class _AtariLayout extends StatelessWidget {
  final MidiService midi;
  const _AtariLayout({required this.midi});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FractionallySizedBox(
        widthFactor: 0.8,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _DPad(midi: midi),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ActionButton(midi: midi, note: MidiService.noteA, label: 'A', color: Colors.red, size: 80),
                const SizedBox(width: 24),
                _ActionButton(midi: midi, note: MidiService.noteB, label: 'B', color: Colors.blue, size: 80),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// MD 6ボタンレイアウト
// ---------------------------------------------------------------------------

class _Md6Layout extends StatelessWidget {
  final MidiService midi;
  const _Md6Layout({required this.midi});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Mode: 右上
        Positioned(
          top: 8,
          right: 16,
          child: _ActionButton(midi: midi, note: MidiService.noteMode, label: 'Mode', color: Colors.grey, size: 40, width: 72),
        ),
        // Start: 画面中央
        Align(
          alignment: Alignment.center,
          child: _ActionButton(midi: midi, note: MidiService.noteStart, label: 'Start', color: Colors.grey, size: 48, width: 88),
        ),
        // 十字キー (左) + ボタン (右)
        Center(
          child: FractionallySizedBox(
            widthFactor: 0.85,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _DPad(midi: midi),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 上段: X Y Z
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _ActionButton(midi: midi, note: MidiService.noteX, label: 'X', color: Colors.purple, size: 64),
                        const SizedBox(width: 12),
                        _ActionButton(midi: midi, note: MidiService.noteY, label: 'Y', color: Colors.purple, size: 64),
                        const SizedBox(width: 12),
                        _ActionButton(midi: midi, note: MidiService.noteZ, label: 'Z', color: Colors.purple, size: 64),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // 下段: A B C
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _ActionButton(midi: midi, note: MidiService.noteA, label: 'A', color: Colors.red, size: 64),
                        const SizedBox(width: 12),
                        _ActionButton(midi: midi, note: MidiService.noteB, label: 'B', color: Colors.blue, size: 64),
                        const SizedBox(width: 12),
                        _ActionButton(midi: midi, note: MidiService.noteC, label: 'C', color: Colors.green, size: 64),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 汎用アクションボタン
// ---------------------------------------------------------------------------

class _ActionButton extends StatefulWidget {
  final MidiService midi;
  final int note;
  final String label;
  final Color color;
  final double size;
  final double? width;

  const _ActionButton({
    required this.midi,
    required this.note,
    required this.label,
    required this.color,
    required this.size,
    this.width,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _pressed = false;

  void _onPress() {
    if (!_pressed) {
      setState(() => _pressed = true);
      widget.midi.joystickPress(widget.note);
    }
  }

  void _onRelease() {
    if (_pressed) {
      setState(() => _pressed = false);
      widget.midi.joystickRelease(widget.note);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _onPress(),
      onTapUp: (_) => _onRelease(),
      onTapCancel: () => _onRelease(),
      child: Container(
        width: widget.width ?? widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: _pressed ? widget.color.withValues(alpha: 0.9) : widget.color.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(widget.size > 60 ? 12 : 8),
          border: Border.all(
            color: _pressed ? Colors.white : Colors.grey,
            width: _pressed ? 3 : 1,
          ),
        ),
        child: Center(
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: widget.size > 60 ? 22 : 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}
