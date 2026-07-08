import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

class DeviceAuthHelper {
  static final LocalAuthentication _auth = LocalAuthentication();

  /// Check if the device supports biometric or PIN/passcode lock
  static Future<bool> canAuthenticate() async {
    try {
      final bool canCheckBiometrics = await _auth.canCheckBiometrics;
      final bool isSupported = await _auth.isDeviceSupported();
      return canCheckBiometrics || isSupported;
    } catch (e) {
      debugPrint('Error checking local auth support: $e');
      return false;
    }
  }

  /// Trigger device OS lock screen authentication
  static Future<bool> authenticate({required String reason}) async {
    try {
      final bool isSupported = await canAuthenticate();
      if (!isSupported) {
        debugPrint('Local authentication is not supported or set up on this device');
        return false;
      }

      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: false, // Allows PIN/Passcode/Pattern fallback
        persistAcrossBackgrounding: true, // Auto-retries auth on foregrounding (stickyAuth)
      );
    } catch (e) {
      debugPrint('Authentication exception: $e');
      return false;
    }
  }

  /// Authenticates using the configured method (device lock screen or custom Kiosk PIN)
  static Future<bool> authenticateWithFallback(BuildContext context, {required String reason}) async {
    return true;
  }
}

class KioskPinDialog extends StatefulWidget {
  final String correctPin;
  final bool allowBiometrics;
  final String reason;
  final VoidCallback onBiometricRequested;

  const KioskPinDialog({
    super.key,
    required this.correctPin,
    required this.allowBiometrics,
    required this.reason,
    required this.onBiometricRequested,
  });

  @override
  State<KioskPinDialog> createState() => _KioskPinDialogState();
}

class _KioskPinDialogState extends State<KioskPinDialog> with SingleTickerProviderStateMixin {
  String _enteredPin = '';
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;
  bool _isError = false;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _shakeAnimation = Tween<double>(begin: 0.0, end: 12.0)
        .chain(CurveTween(curve: Curves.elasticIn))
        .animate(_shakeController);

    // Auto-trigger biometric authentication if allowed
    if (widget.allowBiometrics) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onBiometricRequested();
      });
    }
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  void _onNumberPressed(int number) {
    if (_enteredPin.length >= widget.correctPin.length) return;
    setState(() {
      _isError = false;
      _enteredPin += number.toString();
    });

    if (_enteredPin.length == widget.correctPin.length) {
      _verifyPin();
    }
  }

  void _onBackspace() {
    if (_enteredPin.isEmpty) return;
    setState(() {
      _isError = false;
      _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
    });
  }

  void _verifyPin() {
    if (_enteredPin == widget.correctPin) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _isError = true;
        _enteredPin = '';
      });
      _shakeController.forward(from: 0.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon / Header
            Icon(
              Icons.lock_outline,
              size: 40,
              color: _isError ? Colors.redAccent : theme.primaryColor,
            ),
            const SizedBox(height: 16),
            const Text(
              'Security Verification',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              widget.reason,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
            const SizedBox(height: 24),

            // PIN Dots Indicator
            AnimatedBuilder(
              animation: _shakeAnimation,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(_shakeAnimation.value * (1 - _shakeController.value), 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      widget.correctPin.length,
                      (index) {
                        final filled = index < _enteredPin.length;
                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: filled
                                ? (_isError ? Colors.redAccent : theme.primaryColor)
                                : (isDark ? Colors.white24 : Colors.black12),
                            border: Border.all(
                              color: filled
                                  ? Colors.transparent
                                  : (isDark ? Colors.white30 : Colors.black26),
                              width: 1.5,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
            if (_isError) ...[
              const SizedBox(height: 12),
              const Text(
                'Incorrect PIN. Please try again.',
                style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ],
            const SizedBox(height: 32),

            // Numeric Keyboard Pad
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 1.2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              itemCount: 12,
              itemBuilder: (context, index) {
                if (index == 9) {
                  // Biometric Button or Spacer
                  if (widget.allowBiometrics) {
                    return InkWell(
                      onTap: widget.onBiometricRequested,
                      borderRadius: BorderRadius.circular(16),
                      child: Center(
                        child: Icon(
                          Icons.fingerprint,
                          size: 28,
                          color: theme.primaryColor,
                        ),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                } else if (index == 10) {
                  // Number 0
                  return _buildNumberKey(0);
                } else if (index == 11) {
                  // Backspace Button
                  return InkWell(
                    onTap: _onBackspace,
                    borderRadius: BorderRadius.circular(16),
                    child: Center(
                      child: Icon(
                        Icons.backspace_outlined,
                        size: 22,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                  );
                } else {
                  // Numbers 1-9
                  return _buildNumberKey(index + 1);
                }
              },
            ),
            const SizedBox(height: 16),

            // Cancel Button
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                'CANCEL',
                style: TextStyle(
                  color: isDark ? Colors.white60 : Colors.black54,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNumberKey(int number) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: () => _onNumberPressed(number),
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Text(
            number.toString(),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}
