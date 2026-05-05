import 'package:flutter/material.dart';
import 'midi_service.dart';
import 'joystick_page.dart';

void main() {
  runApp(const SmartRetroHidApp());
}

class SmartRetroHidApp extends StatelessWidget {
  const SmartRetroHidApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'smart-retro-hid',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
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
  MidiDeviceInfo? _connectedDevice;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _midi.onDisconnect = () {
      if (mounted) {
        setState(() => _connectedDevice = null);
      }
    };
    // 起動時に自動スキャン
    Future.microtask(() => _scanDevices());
  }

  @override
  void dispose() {
    _midi.dispose();
    super.dispose();
  }

  Future<void> _scanDevices() async {
    setState(() => _scanning = true);
    final devices = await _midi.scanDevices();
    if (mounted) {
      setState(() {
        _devices = devices;
        _scanning = false;
      });
    }
  }

  Future<void> _connectDevice(MidiDeviceInfo device) async {
    final success = await _midi.connect(device);
    if (success && mounted) {
      setState(() => _connectedDevice = device);
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => JoystickPage(midi: _midi),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('smart-retro-hid')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              onPressed: _scanning ? null : _scanDevices,
              icon: _scanning
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search),
              label: Text(_scanning ? 'スキャン中...' : 'デバイスをスキャン'),
            ),
            const SizedBox(height: 16),
            if (_devices.isEmpty && !_scanning)
              const Center(
                child: Text(
                  'デバイスが見つかりません\nUSB-MIDIデバイスを接続してスキャンしてください',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            Expanded(
              child: ListView.builder(
                itemCount: _devices.length,
                itemBuilder: (context, index) {
                  final device = _devices[index];
                  final isConnected = _connectedDevice?.id == device.id;
                  return Card(
                    child: ListTile(
                      leading: Icon(
                        Icons.usb,
                        color: isConnected ? Colors.green : null,
                      ),
                      title: Text(device.name),
                      subtitle: Text(device.id),
                      trailing: isConnected
                          ? const Chip(label: Text('接続中'))
                          : ElevatedButton(
                              onPressed: () => _connectDevice(device),
                              child: const Text('接続'),
                            ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
