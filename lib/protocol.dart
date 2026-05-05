// ===================================================================================
// Mimic X プロトコル定数とパーサ
// ===================================================================================
// プロトコル仕様: smart-retro-hid-protocol v0.3.0
// ===================================================================================

class HidType {
  static const int unknown = 0x00;
  static const int keyboard = 0x01;
  static const int joystick = 0x02;
  static const int mouse = 0x03;
  static const int custom = 0x10;

  static String label(int v) {
    switch (v) {
      case keyboard: return 'Keyboard';
      case joystick: return 'Joystick';
      case mouse: return 'Mouse';
      case custom: return 'Custom';
      default: return 'Unknown(0x${v.toRadixString(16)})';
    }
  }
}

class TargetSystem {
  static const int generic = 0x00;
  static const int atari = 0x01;
  static const int x68000 = 0x02;
  static const int pc98 = 0x03;
  static const int msx = 0x04;
  static const int fmTowns = 0x05;
  static const int pc88 = 0x06;
  static const int apple2 = 0x07;
  static const int c64 = 0x08;
  static const int amiga = 0x09;
  static const int zx = 0x0A;
  static const int pcAt = 0x10;
  static const int pcXt = 0x11;
  static const int megaDrive = 0x40;

  static String label(int v) {
    switch (v) {
      case atari: return 'ATARI';
      case x68000: return 'X68000';
      case pc98: return 'PC-9801';
      case msx: return 'MSX';
      case fmTowns: return 'FM TOWNS';
      case pc88: return 'PC-8801';
      case apple2: return 'Apple II';
      case c64: return 'C64';
      case amiga: return 'Amiga';
      case zx: return 'ZX Spectrum';
      case pcAt: return 'IBM PC/AT';
      case pcXt: return 'IBM PC XT';
      case megaDrive: return 'Mega Drive';
      case generic: return 'Generic';
      default: return 'Unknown(0x${v.toRadixString(16)})';
    }
  }
}

/// 1 つの MIDI チャンネルに割り当てられた HID 機能
class ChannelAssignment {
  final int midiChannel;
  final int hidType;
  final int targetSystem;

  ChannelAssignment({
    required this.midiChannel,
    required this.hidType,
    required this.targetSystem,
  });

  String get hidTypeLabel => HidType.label(hidType);
  String get targetLabel => TargetSystem.label(targetSystem);

  @override
  String toString() =>
      'ch${midiChannel + 1}: $hidTypeLabel ($targetLabel)';
}

/// IDENTIFY_RESPONSE のパース結果
class DeviceIdentity {
  final int protocolMajor;
  final int protocolMinor;
  final int firmwareMajor;
  final int firmwareMinor;
  final int firmwarePatch;
  final List<ChannelAssignment> channels;
  final String deviceName;

  DeviceIdentity({
    required this.protocolMajor,
    required this.protocolMinor,
    required this.firmwareMajor,
    required this.firmwareMinor,
    required this.firmwarePatch,
    required this.channels,
    required this.deviceName,
  });

  String get protocolVersion => '$protocolMajor.$protocolMinor';
  String get firmwareVersion => '$firmwareMajor.$firmwareMinor.$firmwarePatch';

  /// IDENTIFY_RESPONSE を SysEx 全体 (F0..F7) からパース
  ///
  /// レイアウト:
  ///   F0 7D 01 02
  ///     <protocol_major> <protocol_minor>
  ///     <fw_major> <fw_minor> <fw_patch>
  ///     <num_channels>
  ///     <ch> <type> <target>  ... (num_channels 個)
  ///     <name ASCII...>
  ///   F7
  static DeviceIdentity? parse(List<int> sysex) {
    if (sysex.length < 11) return null;
    if (sysex.first != 0xF0 || sysex.last != 0xF7) return null;
    if (sysex[1] != 0x7D || sysex[2] != 0x01 || sysex[3] != 0x02) return null;

    int p = 4;
    final protoMaj = sysex[p++];
    final protoMin = sysex[p++];
    final fwMaj = sysex[p++];
    final fwMin = sysex[p++];
    final fwPatch = sysex[p++];
    final numCh = sysex[p++];

    final channels = <ChannelAssignment>[];
    for (int i = 0; i < numCh; i++) {
      if (p + 3 > sysex.length - 1) return null;
      channels.add(ChannelAssignment(
        midiChannel: sysex[p++],
        hidType: sysex[p++],
        targetSystem: sysex[p++],
      ));
    }

    final nameBytes = sysex.sublist(p, sysex.length - 1);
    final name = String.fromCharCodes(nameBytes);

    return DeviceIdentity(
      protocolMajor: protoMaj,
      protocolMinor: protoMin,
      firmwareMajor: fwMaj,
      firmwareMinor: fwMin,
      firmwarePatch: fwPatch,
      channels: channels,
      deviceName: name,
    );
  }
}

/// SysEx コマンドビルダ
class SysExBuilder {
  static const int mfrId = 0x7D;
  static const int subId = 0x01;
  static const int cmdIdentifyReq = 0x01;
  static const int cmdIdentifyRsp = 0x02;
  static const int cmdCapabilityReq = 0x03;
  static const int cmdCapabilityRsp = 0x04;
  static const int cmdTargetRx = 0x05;   // デバイス→ホスト: ターゲット機からの受信バイト
  static const int cmdSetConfig = 0x10;
  static const int cmdReset = 0x7F;

  static List<int> identifyRequest() =>
      [0xF0, mfrId, subId, cmdIdentifyReq, 0xF7];

  static List<int> capabilityRequest() =>
      [0xF0, mfrId, subId, cmdCapabilityReq, 0xF7];

  static List<int> setConfig(int key, int value) =>
      [0xF0, mfrId, subId, cmdSetConfig, key & 0x7F, value & 0x7F, 0xF7];

  static List<int> reset() =>
      [0xF0, mfrId, subId, cmdReset, 0xF7];
}
