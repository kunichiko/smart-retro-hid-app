import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ジョイスティック画面の操作設定。
///
/// アプリ起動時に [JoystickSettings.instance.load] を一度だけ await して初期化
/// する。値の変更は set* メソッドで行い、SharedPreferences に永続化される。
/// ChangeNotifier を継承しているので画面側は addListener で再描画フックできる。
class JoystickSettings extends ChangeNotifier {
  static final JoystickSettings instance = JoystickSettings._();
  JoystickSettings._();

  static const String _kDeadZoneRatio = 'js_dead_zone_ratio';
  static const String _kExtraHitRadius = 'js_extra_hit_radius';
  static const String _kTurboNotes = 'js_turbo_notes';
  static const String _kTurboRate = 'js_turbo_rate';

  /// 不感エリア半径のデフォルト (D-pad サイズに対する比率, 0.0〜0.4)
  static const double defaultDeadZoneRatio = 0.15;

  /// ボタンヒット判定半径への加算量のデフォルト (px, 0〜40)
  /// 大きくすると隣接ボタンとオーバーラップして同時押し / スライド遷移ができる。
  static const double defaultExtraHitRadius = 20.0;

  /// 連射速度のデフォルト (Hz, 1.0〜30.0)。1 Hz = 1 秒間に 1 回 press。
  static const double defaultTurboRate = 10.0;

  double _deadZoneRatio = defaultDeadZoneRatio;
  double _extraHitRadius = defaultExtraHitRadius;
  Set<int> _turboNotes = const <int>{};
  double _turboRate = defaultTurboRate;

  double get deadZoneRatio => _deadZoneRatio;
  double get extraHitRadius => _extraHitRadius;

  /// 連射が有効になっている note 番号の集合 (読み取り専用ビュー)。
  Set<int> get turboNotes => Set.unmodifiable(_turboNotes);
  bool isTurbo(int note) => _turboNotes.contains(note);

  /// 連射速度 (Hz, 全ボタン共通)。
  double get turboRate => _turboRate;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _deadZoneRatio = prefs.getDouble(_kDeadZoneRatio) ?? defaultDeadZoneRatio;
    _extraHitRadius = prefs.getDouble(_kExtraHitRadius) ?? defaultExtraHitRadius;
    final list = prefs.getStringList(_kTurboNotes) ?? const <String>[];
    _turboNotes = list.map(int.parse).toSet();
    _turboRate = prefs.getDouble(_kTurboRate) ?? defaultTurboRate;
    notifyListeners();
  }

  Future<void> setDeadZoneRatio(double v) async {
    if (_deadZoneRatio == v) return;
    _deadZoneRatio = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kDeadZoneRatio, v);
  }

  Future<void> setExtraHitRadius(double v) async {
    if (_extraHitRadius == v) return;
    _extraHitRadius = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kExtraHitRadius, v);
  }

  Future<void> setTurbo(int note, bool enabled) async {
    final next = Set<int>.from(_turboNotes);
    if (enabled) {
      if (!next.add(note)) return;
    } else {
      if (!next.remove(note)) return;
    }
    _turboNotes = next;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _kTurboNotes,
      _turboNotes.map((e) => e.toString()).toList(),
    );
  }

  Future<void> setTurboRate(double v) async {
    if (_turboRate == v) return;
    _turboRate = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kTurboRate, v);
  }
}
