import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show VoidCallback;
import 'package:flutter_midi_command/flutter_midi_command.dart';

class MidiDeviceInfo {
  final String name;
  final String id;
  final MidiDevice _device;

  MidiDeviceInfo({required this.name, required this.id, required MidiDevice device})
      : _device = device;

  MidiDevice get device => _device;
}

class MidiService {
  final MidiCommand _midiCommand = MidiCommand();
  StreamSubscription<MidiPacket>? _rxSubscription;
  VoidCallback? onDisconnect;

  // MIDI チャンネル (プロトコル仕様 v0.1.0)
  static const int chJoystick = 0;

  // ジョイスティック Note 番号 (D-SUB 9pin 対応)
  // 方向キー
  static const int noteUp = 1;
  static const int noteDown = 2;
  static const int noteLeft = 3;
  static const int noteRight = 4;
  // ATARI / MD 共通ボタン
  static const int noteA = 6;      // ATARI: TRIG-A / MD: A
  static const int noteB = 7;      // ATARI: TRIG-B / MD: B
  // MD 6ボタン拡張
  static const int noteC = 9;
  static const int noteStart = 10;
  static const int noteX = 11;
  static const int noteY = 12;
  static const int noteZ = 13;
  static const int noteMode = 14;

  Future<List<MidiDeviceInfo>> scanDevices() async {
    final devices = await _midiCommand.devices ?? [];
    return devices.map((d) => MidiDeviceInfo(
      name: d.name,
      id: d.id,
      device: d,
    )).toList();
  }

  Future<bool> connect(MidiDeviceInfo deviceInfo) async {
    try {
      await _midiCommand.connectToDevice(deviceInfo.device);
      _rxSubscription = _midiCommand.onMidiDataReceived?.listen(_onMidiReceived);
      return true;
    } catch (e) {
      return false;
    }
  }

  void _onMidiReceived(MidiPacket packet) {
    // デバイス→ホストのメッセージ処理 (LED通知など)
    // 将来的にコールバックで通知する
  }

  void disconnect() {
    _rxSubscription?.cancel();
    _rxSubscription = null;
    _midiCommand.teardown();
  }

  // Note On 送信
  void sendNoteOn(int channel, int note, int velocity) {
    final data = Uint8List.fromList([0x90 | (channel & 0x0F), note & 0x7F, velocity & 0x7F]);
    _midiCommand.sendData(data);
  }

  // Note Off 送信
  void sendNoteOff(int channel, int note) {
    final data = Uint8List.fromList([0x80 | (channel & 0x0F), note & 0x7F, 0x00]);
    _midiCommand.sendData(data);
  }

  // ジョイスティック ボタン押下
  void joystickPress(int note) {
    sendNoteOn(chJoystick, note, 127);
  }

  // ジョイスティック ボタン解放
  void joystickRelease(int note) {
    sendNoteOff(chJoystick, note);
  }

  // SysEx 送信
  void sendSysEx(List<int> data) {
    _midiCommand.sendData(Uint8List.fromList(data));
  }

  // パッドモード設定 (SysEx SET_CONFIG)
  // 0 = ATARI, 1 = MD 6B
  void setPadMode(int mode) {
    sendSysEx([0xF0, 0x7D, 0x01, 0x10, 0x03, mode & 0x7F, 0xF7]);
  }

  void dispose() {
    disconnect();
  }
}
