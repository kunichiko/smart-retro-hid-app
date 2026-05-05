import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show VoidCallback;
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'protocol.dart';

class MidiDeviceInfo {
  final String name;
  final String id;
  final MidiDevice _device;

  /// IDENTIFY_RESPONSE のパース結果 (識別前は null)
  DeviceIdentity? identity;

  MidiDeviceInfo({required this.name, required this.id, required MidiDevice device})
      : _device = device;

  MidiDevice get device => _device;
}

class MidiService {
  final MidiCommand _midiCommand = MidiCommand();
  StreamSubscription<MidiPacket>? _rxSubscription;
  VoidCallback? onDisconnect;

  // チャンネル割り当てを SysEx で受信したら通知
  void Function(DeviceIdentity)? onIdentifyResponse;

  // SysEx 受信用バッファ
  final List<int> _sysexBuf = [];
  bool _sysexReceiving = false;

  // ジョイスティック Note 番号 (D-SUB 9pin 対応)
  static const int chJoystickDefault = 0;
  static const int chKeyboardDefault = 1;
  static const int chMouseDefault = 2;

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

  /// IDENTIFY_REQUEST を送信し、レスポンスを待つ。タイムアウト付き。
  Future<DeviceIdentity?> identifyDevice({Duration timeout = const Duration(seconds: 1)}) async {
    final completer = Completer<DeviceIdentity?>();
    final prevHandler = onIdentifyResponse;
    onIdentifyResponse = (id) {
      if (!completer.isCompleted) completer.complete(id);
    };
    sendSysEx(SysExBuilder.identifyRequest());

    final result = await completer.future.timeout(
      timeout,
      onTimeout: () => null,
    );
    onIdentifyResponse = prevHandler;
    return result;
  }

  void _onMidiReceived(MidiPacket packet) {
    final data = packet.data;
    for (final byte in data) {
      if (byte == 0xF0) {
        _sysexBuf.clear();
        _sysexBuf.add(byte);
        _sysexReceiving = true;
      } else if (_sysexReceiving) {
        _sysexBuf.add(byte);
        if (byte == 0xF7) {
          _processSysEx(List.unmodifiable(_sysexBuf));
          _sysexBuf.clear();
          _sysexReceiving = false;
        }
      }
    }
  }

  void _processSysEx(List<int> sysex) {
    if (sysex.length < 5) return;
    if (sysex[1] != 0x7D || sysex[2] != 0x01) return;
    final cmd = sysex[3];
    if (cmd == SysExBuilder.cmdIdentifyRsp) {
      final id = DeviceIdentity.parse(sysex);
      if (id != null) onIdentifyResponse?.call(id);
    }
    // TODO: capability response, status notifications
  }

  void disconnect() {
    _rxSubscription?.cancel();
    _rxSubscription = null;
    _midiCommand.teardown();
  }

  // ---------------------------------------------------------------------------
  // 送信ヘルパー
  // ---------------------------------------------------------------------------

  void sendNoteOn(int channel, int note, int velocity) {
    final data = Uint8List.fromList([0x90 | (channel & 0x0F), note & 0x7F, velocity & 0x7F]);
    _midiCommand.sendData(data);
  }

  void sendNoteOff(int channel, int note) {
    final data = Uint8List.fromList([0x80 | (channel & 0x0F), note & 0x7F, 0x00]);
    _midiCommand.sendData(data);
  }

  void sendCC(int channel, int cc, int value) {
    final data = Uint8List.fromList([0xB0 | (channel & 0x0F), cc & 0x7F, value & 0x7F]);
    _midiCommand.sendData(data);
  }

  void sendSysEx(List<int> data) {
    _midiCommand.sendData(Uint8List.fromList(data));
  }

  // パッドモード設定 (SysEx SET_CONFIG)
  // 0 = ATARI, 1 = MD 6B
  void setPadMode(int mode) {
    sendSysEx(SysExBuilder.setConfig(0x03, mode));
  }

  // 任意 channel への送信ヘルパー (互換)
  void joystickPress(int note, {int channel = chJoystickDefault}) =>
      sendNoteOn(channel, note, 127);
  void joystickRelease(int note, {int channel = chJoystickDefault}) =>
      sendNoteOff(channel, note);

  void dispose() {
    disconnect();
  }
}
