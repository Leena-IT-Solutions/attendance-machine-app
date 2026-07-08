import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:intl/intl.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../services/api_service.dart';
import '../services/device_auth_helper.dart';
import '../utils/image_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image/image.dart' as img;
import 'package:wakelock_plus/wakelock_plus.dart';

class FaceScannerScreen extends StatefulWidget {
  const FaceScannerScreen({super.key});

  @override
  State<FaceScannerScreen> createState() => _FaceScannerScreenState();
}

class _FaceScannerScreenState extends State<FaceScannerScreen> {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _selectedCameraIndex = 0;
  FaceDetector? _faceDetector;
  bool _isBusy = false;
  bool _isCameraInitialized = false;
  String _currentTime = '';
  Timer? _timer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  Map<String, dynamic>? _detectedEmployee;
  bool _isProcessingMatch = false;
  bool _hasBlinked = false;
  bool _isBlinking = false;

  // Battery saving state
  bool _isSleeping = false;
  int _pulseCounter = 0;
  bool _canExit = false;
  DateTime _lastFaceDetectedTime = DateTime.now();
  static const Duration _sleepTimeout = Duration(seconds: 30);
  DateTime _lastProcessedTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _initializeCamera();
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.accurate,
        enableClassification: true,
        minFaceSize:
            0.05, // Allows scanning faces from further away (5% of the frame instead of the default 10%)
      ),
    );
    _syncOfflineScans();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      if (results.any((r) => r != ConnectivityResult.none)) {
        _syncOfflineScans();
      }
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _currentTime = DateFormat(
            'dd MMM yyyy, hh:mm:ss a',
          ).format(DateTime.now());
        });
      }
    });
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        _showError('No cameras found on device');
        return;
      }

      // If first run, try to find front camera
      if (_controller == null) {
        final frontIdx = _cameras.indexWhere(
          (c) => c.lensDirection == CameraLensDirection.front,
        );
        _selectedCameraIndex = frontIdx != -1 ? frontIdx : 0;
      }
      // Always use high resolution for optimal face detection and recognition quality
      const preset = ResolutionPreset.high;

      _controller = CameraController(
        _cameras[_selectedCameraIndex],
        preset,
        enableAudio: false,
      );

      await _controller!.initialize();
      if (!mounted) return;

      _controller!.startImageStream(_processCameraImage);

      setState(() {
        _isCameraInitialized = true;
      });
    } catch (e) {
      debugPrint('Camera error: $e');
      _showError('Failed to initialize camera: $e');
    }
  }

  void _toggleCamera() async {
    if (_cameras.length < 2) return;

    setState(() {
      _isCameraInitialized = false;
      _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras.length;
    });

    await _controller?.dispose();
    _initializeCamera();
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
      // Don't close automatically so user can see error, but stop loading
      setState(() {
        _isCameraInitialized = false;
      });
    }
  }

  void _processCameraImage(CameraImage image) async {
    _pulseCounter++;
    if (_pulseCounter % 60 == 0) {
      debugPrint('--- SCANNER: Pulse Check (Stream is ALIVE!) ---');
    }

    if (!mounted) return;
    if (_isBusy || _isProcessingMatch) return;

    // Throttle ML Kit processing in sleep mode to save battery
    if (_isSleeping &&
        DateTime.now().difference(_lastProcessedTime) < const Duration(milliseconds: 1500)) {
      return;
    }
    _lastProcessedTime = DateTime.now();

    _isBusy = true;

    try {
      final inputImage = _inputImageFromCameraImage(image);
      if (inputImage == null) {
        _isBusy = false;
        return;
      }

      final faces = await _faceDetector!.processImage(inputImage);
      if (!mounted) return;

      if (faces.isNotEmpty) {
        _lastFaceDetectedTime = DateTime.now();
        if (_isSleeping) setState(() => _isSleeping = false);

        final face = faces.first;

        if (!mounted) return;
        final settings = context.read<SettingsProvider>();
        final livenessEnabled = settings.enableBlinkLiveness;
        final user = context.read<AuthProvider>().user;

        // --- LIVENESS & BLINK DETECTION ENGINE ---
        if (!livenessEnabled) {
          _hasBlinked = true;
        } else if (!_hasBlinked) {
          final leftOpen = face.leftEyeOpenProbability ?? 1.0;
          final rightOpen = face.rightEyeOpenProbability ?? 1.0;

          if (leftOpen < 0.18 && rightOpen < 0.18) {
            _isBlinking = true;
          } else if (_isBlinking && leftOpen > 0.65 && rightOpen > 0.65) {
            setState(() {
              _hasBlinked = true;
              _isBlinking = false;
            });
            debugPrint('--- LIVENESS SUCCESS: Blink Verified! ---');
          }
        }

        // Only proceed with face recognition if liveness check is completed!
        if (_hasBlinked) {
          _isProcessingMatch = true; // Lock scanning during network matching

          if (mounted) {
            setState(() {
              _detectedEmployee = {
                'name': 'Identifying...',
                'code': 'Uploading face crop...',
                'photo_url': null,
              };
            });
          }

          final sensorOrientation = _controller!.description.sensorOrientation;
          final isFrontCamera =
              _controller!.description.lensDirection ==
              CameraLensDirection.front;

          // Process the YUV-to-RGB conversion asynchronously in a background Isolate
          final croppedFace = await ImageUtils.convertAndCropYUV420Async(
            image,
            face.boundingBox,
            sensorOrientation: sensorOrientation,
            isFrontCamera: isFrontCamera,
          );
          if (!mounted) return;

          // Convert to JPEG and Base64
          final jpegBytes = Uint8List.fromList(img.encodeJpg(croppedFace, quality: 90));
          final base64Image = 'data:image/jpeg;base64,${base64Encode(jpegBytes)}';

          final now = DateTime.now();
          final scanDate = DateFormat('yyyy-MM-dd').format(now);
          final scanTime = DateFormat('HH:mm:ss').format(now);

          // Network check
          final connectivityResult = await Connectivity().checkConnectivity();
          if (!mounted) return;
          final isOnline = connectivityResult.any((r) => r != ConnectivityResult.none);

          if (isOnline) {
            // --- ONLINE CLOUD RECOGNITION FLOW ---
            try {
              if (!mounted) return;
              final result = await ApiService.recognizeFace(
                photoBase64: base64Image,
                scanDate: scanDate,
                scanTime: scanTime,
              );
              if (!mounted) return;

              debugPrint('--- AI Match Success: ${result['employee']['name']} ---');

              if (mounted) {
                setState(() {
                  _detectedEmployee = {
                    'name': result['employee']['name'],
                    'code': result['employee']['code'],
                    'photo_url': result['employee']['photo_url'] != null ? ApiService.fixUrl(result['employee']['photo_url']) : null,
                    'type': result['type']
                  };
                });
              }

              // Forward to custom API if configured
              try {
                if (user != null &&
                    user['attendance_api_url'] != null &&
                    user['attendance_api_url'].isNotEmpty) {
                  await ApiService.sendToExternalApi(
                    url: user['attendance_api_url'],
                    token: user['api_token'],
                    data: {
                      'employee_code': result['employee']['code'],
                      'p_date': scanDate,
                      'p_time': scanTime,
                    },
                  );
                }
              } catch (e) {
                debugPrint('External API error: $e');
              }

              if (!mounted) return;
              await Future.delayed(const Duration(seconds: 2));
            } catch (e) {
              debugPrint('Cloud face recognition mismatch or error: $e');
              if (mounted) {
                setState(() {
                  _detectedEmployee = {
                    'name': 'Access Denied',
                    'code': e.toString().contains('Face not recognized')
                        ? 'Face not recognized'
                        : 'Service temporarily down',
                    'photo_url': null,
                    'isError': true,
                  };
                });
              }
              if (!mounted) return;
              await Future.delayed(const Duration(milliseconds: 1500));
            }
          } else {
            // --- OFFLINE QUEUED FLOW ---
            try {
              final prefs = await SharedPreferences.getInstance();
              if (!mounted) return;
              final scansJson = prefs.getString('offline_face_scans');
              List<dynamic> scans = scansJson != null ? jsonDecode(scansJson) : [];
              
              scans.add({
                'photo_base64': base64Image,
                'scan_date': scanDate,
                'scan_time': scanTime,
              });
              
              await prefs.setString('offline_face_scans', jsonEncode(scans));
              debugPrint('--- AI: Saved offline check-in locally (Total queued: ${scans.length}) ---');

              if (mounted) {
                setState(() {
                  _detectedEmployee = {
                    'name': 'Offline Check-in',
                    'code': 'Scan saved locally. Synced when online.',
                    'photo_url': null,
                    'isOffline': true,
                  };
                });
              }
              if (!mounted) return;
              await Future.delayed(const Duration(seconds: 2));
            } catch (e) {
              debugPrint('Failed to save offline scan: $e');
            }
          }

          if (mounted) {
            setState(() {
              _detectedEmployee = null;
              _isProcessingMatch = false;
              _hasBlinked = false;
              _isBlinking = false;
            });
          }
        }
      } else {
        // Activate sleep mode after inactivity timeout
        if (!_isSleeping &&
            DateTime.now().difference(_lastFaceDetectedTime) > _sleepTimeout) {
          setState(() => _isSleeping = true);
        }
        // Reset blink states if no face is detected for 2 seconds
        if (DateTime.now().difference(_lastFaceDetectedTime).inSeconds > 2) {
          if (mounted) {
            setState(() {
              _hasBlinked = false;
              _isBlinking = false;
              if (_detectedEmployee != null &&
                  (_detectedEmployee!['name'] == 'Identifying...' ||
                      _detectedEmployee!['name'] == 'Access Denied')) {
                _detectedEmployee = null;
              }
            });
          }
        }
      }
    } catch (e) {
      debugPrint('--- SCANNER ERROR: $e ---');
      _isProcessingMatch = false;
      if (mounted) {
        setState(() {
          _detectedEmployee = null;
          _hasBlinked = false;
          _isBlinking = false;
        });
      }
    } finally {
      _isBusy = false;
    }
  }

  Future<void> _syncOfflineScans() async {
    if (!mounted) return;
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.any((r) => r == ConnectivityResult.none)) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final scansJson = prefs.getString('offline_face_scans');
    if (scansJson == null || scansJson.isEmpty) return;

    List<dynamic> scans = jsonDecode(scansJson);
    if (scans.isEmpty) return;

    debugPrint('--- AI: Syncing ${scans.length} offline scans ---');
    List<dynamic> remainingScans = [];

    for (var scan in scans) {
      if (!mounted) {
        remainingScans.add(scan);
        continue;
      }
      try {
        await ApiService.recognizeFace(
          photoBase64: scan['photo_base64'],
          scanDate: scan['scan_date'],
          scanTime: scan['scan_time'],
        );
        debugPrint('--- AI: Synced offline scan for date ${scan['scan_date']} time ${scan['scan_time']} ---');
      } catch (e) {
        debugPrint('--- AI ERROR: Failed to sync offline scan: $e ---');
        if (e.toString().contains('Face not recognized') || e.toString().contains('422') || e.toString().contains('404') || e.toString().contains('401')) {
          debugPrint('--- AI: Removing invalid scan from queue ---');
        } else {
          remainingScans.add(scan);
        }
      }
    }

    if (mounted) {
      await prefs.setString('offline_face_scans', jsonEncode(remainingScans));
    }
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    if (_controller == null) return null;

    final sensorOrientation = _controller!.description.sensorOrientation;
    final rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    if (rotation == null) return null;

    // Manual NV21 construction for maximum Android compatibility
    final planes = image.planes;
    final yPlane = planes[0];

    Uint8List bytes;
    if (planes.length == 3) {
      // Concatenate Y, V, and U planes for NV21
      final WriteBuffer allBytes = WriteBuffer();
      allBytes.putUint8List(yPlane.bytes);
      allBytes.putUint8List(planes[2].bytes); // V plane
      allBytes.putUint8List(planes[1].bytes); // U plane
      bytes = allBytes.done().buffer.asUint8List();
    } else if (planes.length == 2) {
      final WriteBuffer allBytes = WriteBuffer();
      allBytes.putUint8List(yPlane.bytes);
      allBytes.putUint8List(planes[1].bytes);
      bytes = allBytes.done().buffer.asUint8List();
    } else {
      bytes = yPlane.bytes; // Fallback
    }

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: Platform.isAndroid
            ? InputImageFormat.nv21
            : InputImageFormat.bgra8888,
        bytesPerRow: yPlane.bytesPerRow,
      ),
    );
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _timer?.cancel();
    _connectivitySubscription?.cancel();
    _controller?.dispose();
    _faceDetector?.close();
    super.dispose();
  }

  Future<void> _requestExit() async {
    final authenticated = await DeviceAuthHelper.authenticateWithFallback(
      context,
      reason: 'Please authenticate to exit the Face Scanner',
    );
    if (authenticated) {
      setState(() {
        _canExit = true;
      });
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _canExit,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        await _requestExit();
      },
      child: Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera Preview
          if (_isCameraInitialized &&
              _controller != null &&
              _controller!.value.isInitialized)
            Offstage(
              offstage: _isSleeping,
              child: Center(child: CameraPreview(_controller!)),
            )
          else
            const Center(
              child: CircularProgressIndicator(color: Colors.blueAccent),
            ),

          // 1. ELITE OVERLAY (Cutout & Focus)
          _buildEliteOverlay(),

          // 2. HEADER (Time & Controls)
          Positioned(
            top: 50,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _currentTime,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                    const Text(
                      "KIOSK MODE ACTIVE",
                      style: TextStyle(
                        color: Colors.blueAccent,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    if (_cameras.length > 1)
                      IconButton(
                        icon: const Icon(
                          Icons.flip_camera_ios,
                          color: Colors.white70,
                        ),
                        onPressed: _toggleCamera,
                      ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70),
                      onPressed: _requestExit,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 3. MATCHED RESULT BADGE
          if (_detectedEmployee != null) _buildMatchBadge(),

          // 4. POWER SAVING / SLEEP OVERLAY
          if (_isSleeping) _buildSleepMode(),
        ],
      ),
    ),);
  }

  Widget _buildEliteOverlay() {
    bool isOffline =
        _detectedEmployee != null && _detectedEmployee!['isOffline'] == true;
    bool isMatch =
        _detectedEmployee != null && _detectedEmployee!['isError'] != true && _detectedEmployee!['isOffline'] != true;
    bool isError =
        _detectedEmployee != null && _detectedEmployee!['isError'] == true;

    return Stack(
      children: [
        // Semi-transparent dark overlay with circular cutout
        ColorFiltered(
          colorFilter: ColorFilter.mode(
            Colors.black.withValues(alpha: 0.85),
            BlendMode.srcOut,
          ),
          child: Stack(
            children: [
              Container(
                decoration: const BoxDecoration(
                  color: Colors.black,
                  backgroundBlendMode: BlendMode.dstOut,
                ),
              ),
              Align(
                alignment: Alignment.center,
                child: Container(
                  height: 320,
                  width: 280,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(150),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Glowing Ring
        Align(
          alignment: Alignment.center,
          child: Container(
            width: 300,
            height: 340,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(150),
              border: Border.all(
                color: isMatch
                    ? Colors.greenAccent
                    : (isOffline
                        ? Colors.orangeAccent
                        : (isError
                              ? Colors.redAccent
                              : (!context
                                        .watch<SettingsProvider>()
                                        .enableBlinkLiveness
                                    ? (_hasBlinked
                                          ? Colors.blueAccent
                                          : Colors.white24)
                                    : (_hasBlinked
                                          ? Colors.blueAccent
                                          : (_isBlinking
                                                ? Colors.orangeAccent
                                                : Colors.white24))))),
                width: 4,
              ),
              boxShadow: [
                BoxShadow(
                  color:
                      (isMatch
                              ? Colors.greenAccent
                              : (isOffline
                                    ? Colors.orangeAccent
                                    : (isError
                                          ? Colors.redAccent
                                          : (_hasBlinked
                                                ? Colors.blueAccent
                                                : (_isBlinking
                                                      ? Colors.orangeAccent
                                                      : Colors.blueAccent)))))
                          .withValues(alpha: 0.2),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
          ),
        ),

        // Scanning & Liveness Text
        if (_detectedEmployee == null)
          Align(
            alignment: const Alignment(0, 0.45),
            child: Text(
              !context.watch<SettingsProvider>().enableBlinkLiveness
                  ? (_hasBlinked ? "IDENTIFYING..." : "ALIGN FACE TO SCAN")
                  : (_hasBlinked
                        ? "LIVENESS VERIFIED"
                        : "PLEASE BLINK TO VERIFY LIVENESS"),
              style: TextStyle(
                color: !context.watch<SettingsProvider>().enableBlinkLiveness
                    ? (_hasBlinked ? Colors.blueAccent : Colors.white54)
                    : (_hasBlinked ? Colors.greenAccent : Colors.orangeAccent),
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
          ),
        if (_detectedEmployee == null &&
            context.watch<SettingsProvider>().showMaskWarning)
          const Align(
            alignment: Alignment(0, 0.53),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.orangeAccent,
                  size: 14,
                ),
                SizedBox(width: 6),
                Text(
                  "REMOVE MASK/SUNGLASSES FOR ATTENDANCE",
                  style: TextStyle(
                    color: Colors.orangeAccent,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildMatchBadge() {
    bool isError = _detectedEmployee!['isError'] == true;
    bool isOffline = _detectedEmployee!['isOffline'] == true;

    Color statusColor = isError 
        ? Colors.redAccent 
        : (isOffline ? Colors.orangeAccent : Colors.greenAccent);

    String statusTitle = isError 
        ? "SCAN FAILED" 
        : (isOffline ? "OFFLINE QUEUED" : "ACCESS GRANTED");

    IconData statusIcon = isError 
        ? Icons.cancel 
        : (isOffline ? Icons.cloud_queue : Icons.check_circle);

    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 50, left: 25, right: 25),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(25),
            border: Border.all(
              color: statusColor.withValues(alpha: 0.5),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: statusColor,
                    width: 2,
                  ),
                  image: _detectedEmployee!['photo_url'] != null
                      ? DecorationImage(
                          image: NetworkImage(_detectedEmployee!['photo_url']),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: _detectedEmployee!['photo_url'] == null
                    ? Icon(
                        isError ? Icons.error_outline : (isOffline ? Icons.cloud_queue : Icons.person),
                        color: statusColor,
                      )
                    : null,
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      statusTitle,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                    Text(
                      _detectedEmployee!['name'] ?? "Unknown",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      isOffline 
                          ? (_detectedEmployee!['code'] ?? '---')
                          : "ID: ${_detectedEmployee!['code'] ?? '---'}",
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                statusIcon,
                color: statusColor,
                size: 40,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSleepMode() {
    return Container(
      color: Colors.black.withValues(alpha: 0.95),
      width: double.infinity,
      height: double.infinity,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.remove_red_eye_outlined,
              color: Colors.blueAccent,
              size: 80,
            ),
            const SizedBox(height: 30),
            const Text(
              "POWER SAVING MODE",
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              "Step in front of the kiosk to wake up",
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.3),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 50),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white10),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Text(
                _currentTime,
                style: const TextStyle(color: Colors.white24, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
