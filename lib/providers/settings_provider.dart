import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/api_service.dart';

class SettingsProvider extends ChangeNotifier {
  double _matchThreshold = 0.80;
  bool _showMaskWarning = true;
  String _cameraResolution = 'medium';
  bool _enableBlinkLiveness = true;
  bool _isLoading = true;
  bool _requireScannerAuth = true;
  String _kioskPin = '';
  bool _hasPendingSync = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  double get matchThreshold => _matchThreshold;
  bool get showMaskWarning => _showMaskWarning;
  String get cameraResolution => _cameraResolution;
  bool get enableBlinkLiveness => _enableBlinkLiveness;
  bool get isLoading => _isLoading;
  bool get requireScannerAuth => _requireScannerAuth;
  String get kioskPin => _kioskPin;
  bool get hasPendingSync => _hasPendingSync;

  SettingsProvider() {
    _loadSettings();
    _setupConnectivityListener();
  }

  void _setupConnectivityListener() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      if (results.any((r) => r != ConnectivityResult.none)) {
        if (_hasPendingSync) {
          _uploadSettingsToServer();
        }
      }
    });
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _matchThreshold = prefs.getDouble('match_threshold') ?? 0.80;
      _showMaskWarning = prefs.getBool('show_mask_warning') ?? true;
      _cameraResolution = prefs.getString('camera_resolution') ?? 'medium';
      _enableBlinkLiveness = prefs.getBool('enable_blink_liveness') ?? true;
      _requireScannerAuth = prefs.getBool('require_scanner_auth') ?? true;
      _kioskPin = prefs.getString('kiosk_pin') ?? '';
      _hasPendingSync = prefs.getBool('settings_pending_sync') ?? false;

      // Asynchronously sync settings from server on boot if logged in
      final token = prefs.getString('token');
      if (token != null) {
        fetchSettingsFromServer();
      }
    } catch (e) {
      debugPrint('Error loading settings: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateSettingsFromMap(Map<String, dynamic> settingsMap, {bool saveLocally = true}) async {
    if (settingsMap.containsKey('match_threshold')) {
      final val = settingsMap['match_threshold'];
      if (val is num) {
        _matchThreshold = val.toDouble();
      }
    }
    if (settingsMap.containsKey('show_mask_warning')) {
      final val = settingsMap['show_mask_warning'];
      if (val is bool) {
        _showMaskWarning = val;
      } else if (val is int) {
        _showMaskWarning = val == 1;
      }
    }
    if (settingsMap.containsKey('camera_resolution')) {
      _cameraResolution = settingsMap['camera_resolution'] ?? 'medium';
    }
    if (settingsMap.containsKey('enable_blink_liveness')) {
      final val = settingsMap['enable_blink_liveness'];
      if (val is bool) {
        _enableBlinkLiveness = val;
      } else if (val is int) {
        _enableBlinkLiveness = val == 1;
      }
    }
    if (settingsMap.containsKey('require_scanner_auth')) {
      final val = settingsMap['require_scanner_auth'];
      if (val is bool) {
        _requireScannerAuth = val;
      } else if (val is int) {
        _requireScannerAuth = val == 1;
      }
    }
    if (settingsMap.containsKey('kiosk_pin')) {
      _kioskPin = settingsMap['kiosk_pin'] ?? '';
    }
    notifyListeners();

    if (saveLocally) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('match_threshold', _matchThreshold);
      await prefs.setBool('show_mask_warning', _showMaskWarning);
      await prefs.setString('camera_resolution', _cameraResolution);
      await prefs.setBool('enable_blink_liveness', _enableBlinkLiveness);
      await prefs.setBool('require_scanner_auth', _requireScannerAuth);
      await prefs.setString('kiosk_pin', _kioskPin);
    }
  }

  Future<void> _uploadSettingsToServer() async {
    final token = await ApiService.getToken();
    if (token == null) return; // Not logged in

    try {
      await ApiService.updateProfile({
        'match_threshold': _matchThreshold,
        'show_mask_warning': _showMaskWarning,
        'camera_resolution': _cameraResolution,
        'enable_blink_liveness': _enableBlinkLiveness,
        'require_scanner_auth': _requireScannerAuth,
        'kiosk_pin': _kioskPin,
      });
      _hasPendingSync = false;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('settings_pending_sync', false);
    } catch (e) {
      debugPrint('Failed to sync settings to server: $e');
      _hasPendingSync = true;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('settings_pending_sync', true);
    }
  }

  Future<void> fetchSettingsFromServer() async {
    final token = await ApiService.getToken();
    if (token == null) return; // Not logged in

    if (_hasPendingSync) {
      await _uploadSettingsToServer();
      return;
    }

    try {
      final data = await ApiService.syncEmployees();
      if (data.containsKey('settings')) {
        final serverSettings = data['settings'] as Map<String, dynamic>;
        await updateSettingsFromMap(serverSettings, saveLocally: true);
      }
    } catch (e) {
      debugPrint('Failed to fetch settings from server: $e');
    }
  }

  Future<void> setMatchThreshold(double value) async {
    _matchThreshold = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('match_threshold', value);
    await _uploadSettingsToServer();
  }

  Future<void> setShowMaskWarning(bool value) async {
    _showMaskWarning = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('show_mask_warning', value);
    await _uploadSettingsToServer();
  }

  Future<void> setCameraResolution(String value) async {
    _cameraResolution = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('camera_resolution', value);
    await _uploadSettingsToServer();
  }

  Future<void> setEnableBlinkLiveness(bool value) async {
    _enableBlinkLiveness = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('enable_blink_liveness', value);
    await _uploadSettingsToServer();
  }

  Future<void> setRequireScannerAuth(bool value) async {
    _requireScannerAuth = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('require_scanner_auth', value);
    await _uploadSettingsToServer();
  }

  Future<void> setKioskPin(String value) async {
    _kioskPin = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('kiosk_pin', value);
    await _uploadSettingsToServer();
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }
}
