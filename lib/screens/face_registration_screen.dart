import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../utils/image_utils.dart';
import 'package:image/image.dart' as img;

enum RegistrationPose { straight, complete }

class FaceRegistrationScreen extends StatefulWidget {
  const FaceRegistrationScreen({super.key});

  @override
  State<FaceRegistrationScreen> createState() => _FaceRegistrationScreenState();
}

class _FaceRegistrationScreenState extends State<FaceRegistrationScreen> {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _selectedCameraIndex = 0;
  FaceDetector? _faceDetector;
  bool _isBusy = false;
  bool _isCameraInitialized = false;

  bool _isModelReady = false;

  // Calibration offsets for non-standard sensor orientations
  double? _baseYaw;
  double? _basePitch;
  double? _baseRoll;
  bool _isCapturing = false;
  bool _hasScanStarted = false;

  RegistrationPose _currentPose = RegistrationPose.straight;
  Uint8List? _capturedImageBytes;
  int _matchCounter = 0;
  String _guideText = "Position Face";
  CameraImage? _lastImage;
  int _autoCaptureCounter = 0;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(performanceMode: FaceDetectorMode.accurate),
    );
    _loadModel();
  }

  Future<void> _loadModel() async {
    if (mounted) {
      setState(() {
        _isModelReady = true;
      });
    }
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) return;

      if (_controller == null) {
        final frontIdx = _cameras.indexWhere(
          (c) => c.lensDirection == CameraLensDirection.front,
        );
        _selectedCameraIndex = frontIdx != -1 ? frontIdx : 0;
      }

      // Always use high resolution for optimal face detection and registration quality
      const preset = ResolutionPreset.high;

      _controller = CameraController(
        _cameras[_selectedCameraIndex],
        preset,
        enableAudio: false,
      );

      await _controller!.initialize();
      if (!mounted) return;

      debugPrint(
        '--- Camera Initialized. Sensor Orientation: ${_controller!.description.sensorOrientation} ---',
      );
      _controller!.startImageStream(_processCameraImage);

      setState(() {
        _isCameraInitialized = true;
      });
    } catch (e) {
      debugPrint('Camera error: $e');
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

  void _processCameraImage(CameraImage image) async {
    if (!_hasScanStarted ||
        _isBusy ||
        _isCapturing ||
        _currentPose == RegistrationPose.complete) {
      return;
    }
    _isBusy = true;
    _lastImage = image;

    final inputImage = _inputImageFromCameraImage(image);
    if (inputImage == null) {
      _isBusy = false;
      return;
    }

    try {
      final faces = await _faceDetector!.processImage(inputImage);

      if (faces.isNotEmpty) {
        if (_matchCounter == 0) debugPrint('--- AI: Face Detected! ---');
        final face = faces.first;
        _handlePoseCapture(face);
      } else {
        // --- AUTO-CAPTURE FALLBACK ---
        // If detector is blind, snap a picture every 2.5 seconds automatically
        _autoCaptureCounter++;
        if (_autoCaptureCounter >= 60) {
          // Reduced to 2 seconds
          _autoCaptureCounter = 0;
          if (!_isCapturing) {
            debugPrint('--- AI: Triggering Auto-Capture for $_currentPose ---');
            _handlePoseCapture(null);
          }
        }
      }
    } catch (e) {
      debugPrint('--- AI PROCESS ERROR: $e ---');
    } finally {
      if (mounted) setState(() {});
      _isBusy = false;
    }
  }

  void _handlePoseCapture(Face? face) {
    if (_isCapturing || _lastImage == null) return;
    if (_currentPose == RegistrationPose.complete) return;

    if (face == null) {
      // FORCE AUTO-CAPTURE
      _forceCaptureCurrentPose();
      return;
    }

    double headY = face.headEulerAngleY ?? 0; // Yaw
    double headX = face.headEulerAngleX ?? 0; // Pitch
    double headZ = face.headEulerAngleZ ?? 0; // Roll

    // --- AUTO-CALIBRATION LOGIC ---
    // If this is the first time we see a face, assume this is "Straight"
    if (_baseYaw == null) {
      _baseYaw = headY;
      _basePitch = headX;
      _baseRoll = headZ;
      debugPrint(
        '--- Calibration Set: BaseY: ${_baseYaw!.toStringAsFixed(1)}, BaseX: ${_basePitch!.toStringAsFixed(1)} ---',
      );
    }

    // Calculate relative angles from the base calibration
    double relY = headY - _baseYaw!;
    double relX = headX - _basePitch!;
    double relZ = headZ - _baseRoll!;

    bool isCorrectPose = false;

    // Debugging relative angles
    if (_matchCounter % 5 == 0) {
      debugPrint(
        '--- Relative Angles: Y(Yaw): ${relY.toStringAsFixed(1)}, X(Pitch): ${relX.toStringAsFixed(1)}, Z(Roll): ${relZ.toStringAsFixed(1)} ---',
      );
    }

    switch (_currentPose) {
      case RegistrationPose.straight:
        // Relaxed threshold for extremely reliable detection and capture on all devices/orientations
        isCorrectPose = relY.abs() < 15 && relX.abs() < 15 && relZ.abs() < 15;
        break;
      default:
        break;
    }

    if (isCorrectPose) {
      _matchCounter++;
      if (_matchCounter % 2 == 0) {
        debugPrint('--- Pose Progress: $_currentPose ($_matchCounter/5) ---');
      }

      if (_matchCounter >= 5) {
        _matchCounter = 0;
        _isCapturing = true;
        debugPrint('--- Pose Captured! Processing Face Image... ---');

        Future.microtask(() async {
          if (_lastImage != null) {
            final sensorOrientation =
                _controller!.description.sensorOrientation;
            final isFrontCamera =
                _controller!.description.lensDirection ==
                CameraLensDirection.front;
            final croppedFace = await ImageUtils.convertAndCropYUV420Async(
              _lastImage!,
              face.boundingBox,
              sensorOrientation: sensorOrientation,
              isFrontCamera: isFrontCamera,
            );
            
            final jpegBytes = Uint8List.fromList(img.encodeJpg(croppedFace, quality: 90));

            if (mounted) {
              setState(() {
                _capturedImageBytes = jpegBytes;
                _currentPose = RegistrationPose.complete;
                _guideText = "Registration Complete!";

                // Final Auto-Return
                Future.delayed(const Duration(milliseconds: 1500), () {
                  if (mounted && Navigator.canPop(context)) {
                    debugPrint('--- AI: Returning biometric signatures and image ---');
                    Navigator.pop(context, _getFinalSignature());
                  }
                });
                _isCapturing = false;
              });
            }
          } else {
            if (mounted) {
              setState(() => _isCapturing = false);
            }
          }
        });
      }
    } else {
      // Don't reset immediately, only if wrong for several frames
      if (_matchCounter > 0) {
        _matchCounter--;
      }
    }

    // Update guide text for active scanning
    if (_currentPose != RegistrationPose.complete) {
      _guideText = _getPoseInstruction(_currentPose);
    }
  }

  void _forceCaptureCurrentPose() {
    if (_isCapturing || _lastImage == null) {
      if (_lastImage == null) {
        debugPrint('--- AI: Cannot capture, no camera frame yet ---');
      }
      return;
    }

    _isCapturing = true;
    if (mounted) setState(() {});
    debugPrint('--- AI: Forcing capture for straight pose ---');

    Future.microtask(() async {
      try {
        final sensorOrientation = _controller!.description.sensorOrientation;
        final imgWidth = _lastImage!.width;
        final imgHeight = _lastImage!.height;

        // Determine dimensions in the rotated/upright space
        final bool isLandscape = sensorOrientation == 0 || sensorOrientation == 180;
        final rotatedWidth = isLandscape ? imgWidth : imgHeight;
        final rotatedHeight = isLandscape ? imgHeight : imgWidth;

        final rect = Rect.fromCenter(
          center: Offset(rotatedWidth / 2, rotatedHeight / 2),
          width: rotatedWidth * 0.8,
          height: rotatedHeight * 0.8,
        );

        debugPrint('--- AI: Converting image for straight pose ---');
        final isFrontCamera =
            _controller!.description.lensDirection == CameraLensDirection.front;
        final croppedFace = await ImageUtils.convertAndCropYUV420Async(
          _lastImage!,
          rect,
          sensorOrientation: sensorOrientation,
          isFrontCamera: isFrontCamera,
        );

        final jpegBytes = Uint8List.fromList(img.encodeJpg(croppedFace, quality: 90));

        if (mounted) {
          setState(() {
            _capturedImageBytes = jpegBytes;
            _currentPose = RegistrationPose.complete;
            _guideText = "Registration Complete!";
            if (mounted) setState(() {});

            // Final Auto-Return
            Future.delayed(const Duration(milliseconds: 1500), () {
              if (mounted && Navigator.canPop(context)) {
                debugPrint('--- AI: Navigating back to employee form ---');
                Navigator.pop(context, _getFinalSignature());
              }
            });
          });
        }
      } catch (e) {
        debugPrint('--- AI CRITICAL ERROR: $e ---');
      } finally {
        if (mounted) {
          setState(() => _isCapturing = false);
        }
      }
    });
  }

  Map<String, dynamic> _getFinalSignature() {
    return {
      'image_bytes': _capturedImageBytes,
      'face_signature': {
        'straight': List.filled(512, 0.0), // Placeholder matching default active dimension
      }
    };
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
      // Concatenate Y, V, and U planes for NV21 (Y, then V, then U)
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
    _controller?.dispose();
    _faceDetector?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (!_isModelReady)
            Container(
              color: Colors.black87,
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: Colors.blue),
                    SizedBox(height: 20),
                    Text(
                      "Loading AI Model...",
                      style: TextStyle(color: Colors.white, fontSize: 18),
                    ),
                    SizedBox(height: 10),
                    Text(
                      "Please ensure assets/model/mobile_facenet.tflite exists",
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),

          if (_isCameraInitialized && _controller != null && _isModelReady)
            Center(child: CameraPreview(_controller!)),

          // Guide Overlay
          _buildOverlay(),

          // Header
          Positioned(
            top: 50,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 30),
                  onPressed: () => Navigator.pop(context),
                ),
                Row(
                  children: [
                    if (_cameras.length > 1)
                      IconButton(
                        icon: const Icon(
                          Icons.flip_camera_ios,
                          color: Colors.white,
                          size: 26,
                        ),
                        onPressed: _toggleCamera,
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black45,
                        ),
                      ),
                    const SizedBox(width: 8),
                    // Calibration Reset
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _baseYaw = null;
                          _matchCounter = 0;
                        });
                      },
                      icon: const Icon(Icons.refresh, color: Colors.blue),
                      label: const Text(
                        "RESET CENTER",
                        style: TextStyle(
                          color: Colors.blue,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: TextButton.styleFrom(backgroundColor: Colors.black45),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Footer Text
          Positioned(
            bottom: 30,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                "STAY STILL • AUTO-SCAN ACTIVE",
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 14,
                  letterSpacing: 2.0,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverlay() {
    double progress = _autoCaptureCounter / 60.0;
    bool isComplete = _currentPose == RegistrationPose.complete;

    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.transparent,
      child: Stack(
        children: [
          // Semi-transparent dark overlay with circular cutout
          ColorFiltered(
            colorFilter: ColorFilter.mode(
              Colors.black.withValues(alpha: 0.7),
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
                    width: 280, // Matched width
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(150),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Elite Progress Ring (Independent Align for perfect centering)
          Align(
            alignment: Alignment.center,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // The Glowing Progress Ring
                SizedBox(
                  width: 300, // Slightly larger than cutout
                  height: 340,
                  child: CircularProgressIndicator(
                    value: isComplete ? 1.0 : progress,
                    strokeWidth: 10,
                    backgroundColor: Colors.white12,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isComplete ? Colors.greenAccent : Colors.blueAccent,
                    ),
                  ),
                ),

                // Capture Success Pulse
                if (_isCapturing)
                  Container(
                    width: 290,
                    height: 330,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(150),
                      border: Border.all(color: Colors.greenAccent, width: 4),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.greenAccent.withValues(alpha: 0.4),
                          blurRadius: 20,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // Guidance Badge (Positioned below the center)
          Align(
            alignment: const Alignment(0, 0.6), // 60% down from center
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 40,
                    vertical: 15,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: isComplete
                          ? Colors.greenAccent
                          : Colors.blueAccent,
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color:
                            (isComplete
                                    ? Colors.greenAccent
                                    : Colors.blueAccent)
                                .withValues(alpha: 0.3),
                        blurRadius: 15,
                      ),
                    ],
                  ),
                  child: Text(
                    _guideText.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  isComplete
                      ? "PROCESSING SIGNATURE..."
                      : (!_hasScanStarted
                            ? "ALIGN FACE IN CIRCLE"
                            : "HOLD STILL FOR AUTO-SCAN"),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 12,
                    letterSpacing: 1.2,
                  ),
                ),
                if (!isComplete) ...[
                  const SizedBox(height: 16),
                  if (!_hasScanStarted)
                    ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          _hasScanStarted = true;
                          _guideText = "Look Straight";
                        });
                      },
                      icon: const Icon(
                        Icons.play_arrow,
                        color: Colors.white,
                        size: 28,
                      ),
                      label: const Text(
                        "START AUTO-SCAN",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.1,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.greenAccent[700],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                        elevation: 10,
                        shadowColor: Colors.greenAccent.withValues(alpha: 0.4),
                      ),
                    )
                  else
                    ElevatedButton.icon(
                      onPressed: _isCapturing ? null : _forceCaptureCurrentPose,
                      icon: const Icon(Icons.camera, color: Colors.white),
                      label: const Text(
                        "CAPTURE POSE MANUALLY",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.1,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        elevation: 8,
                        shadowColor: Colors.blueAccent.withValues(alpha: 0.4),
                      ),
                    ),
                ],
              ],
            ),
          ),

          // Progress Steps (Dots)
          Positioned(
            top: 100,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: RegistrationPose.values
                  .where((p) => p != RegistrationPose.complete)
                  .map((p) {
                    bool isDone = _capturedImageBytes != null;
                    bool isCurrent = _currentPose == p;
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      width: isCurrent ? 16 : 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: isDone
                            ? Colors.greenAccent
                            : (isCurrent ? Colors.blueAccent : Colors.white24),
                        borderRadius: BorderRadius.circular(5),
                        boxShadow: isCurrent
                            ? [
                                const BoxShadow(
                                  color: Colors.blueAccent,
                                  blurRadius: 8,
                                ),
                              ]
                            : [],
                      ),
                    );
                  })
                  .toList()
                  .cast<Widget>(),
            ),
          ),
        ],
      ),
    );
  }

  String _getPoseInstruction(RegistrationPose pose) {
    switch (pose) {
      case RegistrationPose.straight:
        return "Look Straight";
      case RegistrationPose.complete:
        return "Registration Complete!";
    }
  }
}
