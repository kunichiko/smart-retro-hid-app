import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'about_page.dart';
import 'l10n/app_localizations.dart';
import 'midi_service.dart';
import 'protocol.dart';
import 'joystick_page.dart';
import 'joystick_settings.dart';
import 'orientation_helper.dart';
import 'x68k_keyboard_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await JoystickSettings.instance.load();
  runApp(const SmartRetroHidApp());
}

class SmartRetroHidApp extends StatelessWidget {
  const SmartRetroHidApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (ctx) => AppLocalizations.of(ctx)!.appTitle,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      // 端末ロケールが ja なら日本語、それ以外はデフォルトの英語にフォールバック。
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final MidiService _midi = MidiService();
  List<MidiDeviceInfo> _devices = [];
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    // ホーム画面はポートレート固定
    OrientationHelper.portrait();

    _midi.onDisconnect = () {
      if (mounted) setState(() {});
    };
    // 起動時に自動スキャン
    Future.microtask(_scanAndIdentify);
  }

  @override
  void dispose() {
    _midi.dispose();
    super.dispose();
  }

  Future<void> _scanAndIdentify() async {
    setState(() => _scanning = true);
    final devices = await _midi.scanDevices();

    // 各デバイスに対して接続 → IDENTIFY → 切断 を順次実行
    for (final dev in devices) {
      final ok = await _midi.connect(dev);
      if (!ok) continue;
      try {
        dev.identity = await _midi.identifyDevice(
          timeout: const Duration(milliseconds: 500),
        );
      } catch (_) {
        // 識別失敗は無視 (Mimic X 以外のデバイスかも)
      }
      _midi.disconnect();
    }

    if (mounted) {
      setState(() {
        _devices = devices;
        _scanning = false;
      });
    }
  }

  Future<void> _openDevice(MidiDeviceInfo device) async {
    final success = await _midi.connect(device);
    if (!success || !mounted) return;

    // 既存の identity がなければ識別を試みる
    device.identity ??= await _midi.identifyDevice();
    if (!mounted) return;

    final identity = device.identity;
    final l = AppLocalizations.of(context)!;
    if (identity == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.deviceNotResponding)),
      );
      _midi.disconnect();
      return;
    }

    if (identity.channels.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.noChannelsAvailable)),
      );
      _midi.disconnect();
      return;
    }

    // X68000 のキーボード+マウス両方が割り当て済みなら統合ビュー直行
    final x68kKb = identity.channels
        .cast<ChannelAssignment?>()
        .firstWhere(
          (c) => c!.hidType == HidType.keyboard && c.targetSystem == TargetSystem.x68000,
          orElse: () => null,
        );
    final x68kMouse = identity.channels
        .cast<ChannelAssignment?>()
        .firstWhere(
          (c) => c!.hidType == HidType.mouse && c.targetSystem == TargetSystem.x68000,
          orElse: () => null,
        );
    final isX68kCombo = x68kKb != null &&
        x68kMouse != null &&
        identity.channels.length == 2;

    if (isX68kCombo) {
      _routeToChannel(device, x68kKb);
    } else if (identity.channels.length == 1) {
      _routeToChannel(device, identity.channels.first);
    } else {
      _showChannelPicker(device, identity);
    }
  }

  void _routeToChannel(MidiDeviceInfo device, ChannelAssignment ch) async {
    Widget? page;
    if (ch.hidType == HidType.joystick) {
      page = JoystickPage(midi: _midi, channel: ch.midiChannel);
    } else if (ch.hidType == HidType.keyboard && ch.targetSystem == TargetSystem.x68000) {
      // 同じデバイスに X68000 マウスもあれば mouseChannel を渡してトラックパッド表示
      final mouseCh = device.identity?.channels
          .cast<ChannelAssignment?>()
          .firstWhere(
            (c) => c!.hidType == HidType.mouse && c.targetSystem == TargetSystem.x68000,
            orElse: () => null,
          );
      page = X68kKeyboardPage(
        midi: _midi,
        channel: ch.midiChannel,
        mouseChannel: mouseCh?.midiChannel,
      );
    }

    if (page == null) {
      final l = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.unsupportedFunction(ch.hidTypeLabel, ch.targetLabel))),
      );
      _midi.disconnect();
      return;
    }

    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page!));
    // 戻ってきたら切断 + ポートレート復帰
    _midi.disconnect();
    OrientationHelper.portrait();
  }

  void _showChannelPicker(MidiDeviceInfo device, DeviceIdentity identity) {
    final l = AppLocalizations.of(context)!;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(l.selectFunction, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            for (final ch in identity.channels)
              ListTile(
                leading: Icon(_iconForType(ch.hidType)),
                title: Text(ch.hidTypeLabel),
                subtitle: Text(l.homeChannelLabel(ch.midiChannel + 1, ch.targetLabel)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _routeToChannel(device, ch);
                },
              ),
          ],
        ),
      ),
    );
  }

  IconData _iconForType(int hidType) {
    switch (hidType) {
      case HidType.keyboard: return Icons.keyboard;
      case HidType.joystick: return Icons.gamepad;
      case HidType.mouse: return Icons.mouse;
      default: return Icons.device_unknown;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.appTitle),
        actions: [
          IconButton(
            icon: _scanning
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            tooltip: l.homeRescanTooltip,
            onPressed: _scanning ? null : _scanAndIdentify,
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: l.homeAboutTooltip,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AboutPage()),
            ),
          ),
        ],
      ),
      body: _devices.isEmpty
          ? Center(
              child: _scanning
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(l.homeSearching),
                      ],
                    )
                  : Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        '${l.homeNoDevicesTitle}\n\n${l.homeNoDevicesHint}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ),
            )
          : ListView.builder(
              itemCount: _devices.length,
              itemBuilder: (context, index) {
                final device = _devices[index];
                final identity = device.identity;
                final isMimicX = identity != null;
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: InkWell(
                    onTap: isMimicX ? () => _openDevice(device) : null,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(
                            isMimicX ? Icons.check_circle : Icons.usb,
                            color: isMimicX ? Colors.green : Colors.grey,
                            size: 32,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  device.name,
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                                if (identity != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    l.homeFirmwareVersion(
                                      identity.firmwareVersion,
                                      identity.protocolVersion,
                                    ),
                                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                                  ),
                                  const SizedBox(height: 4),
                                  Wrap(
                                    spacing: 4,
                                    runSpacing: 2,
                                    children: identity.channels
                                        .map((ch) => Chip(
                                              label: Text(
                                                '${ch.hidTypeLabel}/${ch.targetLabel}',
                                                style: const TextStyle(fontSize: 11),
                                              ),
                                              padding: EdgeInsets.zero,
                                              materialTapTargetSize:
                                                  MaterialTapTargetSize.shrinkWrap,
                                            ))
                                        .toList(),
                                  ),
                                ] else ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    l.homeIncompatibleNote,
                                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (isMimicX) const Icon(Icons.chevron_right),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
