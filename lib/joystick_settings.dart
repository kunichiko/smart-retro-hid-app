import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ジョイスティック画面の操作設定。
///
/// アプリ起動時に [JoystickSettings.instance.load] を一度だけ await して初期化
/// する。値の変更は [setDeadZoneRatio] / [setExtraHitRadius] で行い、
/// SharedPreferences に永続化される。ChangeNotifier を継承しているので
/// 画面側は addListener で再描画フックできる。
class JoystickSettings extends ChangeNotifier {
  static final JoystickSettings instance = JoystickSettings._();
  JoystickSettings._();

  static const String _kDeadZoneRatio = 'js_dead_zone_ratio';
  static const String _kExtraHitRadius = 'js_extra_hit_radius';

  /// 不感エリア半径のデフォルト (D-pad サイズに対する比率, 0.0〜0.4)
  static const double defaultDeadZoneRatio = 0.15;

  /// ボタンヒット判定半径への加算量のデフォルト (px, 0〜40)
  /// 大きくすると隣接ボタンとオーバーラップして同時押し / スライド遷移ができる。
  static const double defaultExtraHitRadius = 20.0;

  double _deadZoneRatio = defaultDeadZoneRatio;
  double _extraHitRadius = defaultExtraHitRadius;

  double get deadZoneRatio => _deadZoneRatio;
  double get extraHitRadius => _extraHitRadius;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _deadZoneRatio = prefs.getDouble(_kDeadZoneRatio) ?? defaultDeadZoneRatio;
    _extraHitRadius = prefs.getDouble(_kExtraHitRadius) ?? defaultExtraHitRadius;
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
}
