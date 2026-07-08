import 'dart:io';
import 'dart:isolate';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Parameter class to pass necessary data to the background isolate.
/// Since `CameraImage` has platform-specific references and cannot easily
/// cross isolate boundaries on all systems, we extract the raw bytes and dimensions.
class YUVConversionParams {
  final int width;
  final int height;
  final List<Uint8List> planeBytes;
  final List<int> planeBytesPerRow;
  final List<int?> planeBytesPerPixel;
  final double boundingBoxLeft;
  final double boundingBoxTop;
  final double boundingBoxRight;
  final double boundingBoxBottom;
  final int sensorOrientation;
  final bool isFrontCamera;
  final bool isIOS;

  YUVConversionParams({
    required this.width,
    required this.height,
    required this.planeBytes,
    required this.planeBytesPerRow,
    required this.planeBytesPerPixel,
    required this.boundingBoxLeft,
    required this.boundingBoxTop,
    required this.boundingBoxRight,
    required this.boundingBoxBottom,
    required this.sensorOrientation,
    required this.isFrontCamera,
    required this.isIOS,
  });
}

class ImageUtils {
  /// Converts a [CameraImage] in YUV420 format and crops the face bounding box
  /// asynchronously using a background [Isolate].
  static Future<img.Image> convertAndCropYUV420Async(
    CameraImage image,
    dynamic boundingBox, {
    int sensorOrientation = 90,
    bool isFrontCamera = false,
  }) async {
    final params = YUVConversionParams(
      width: image.width,
      height: image.height,
      planeBytes: image.planes.map((p) => p.bytes).toList(),
      planeBytesPerRow: image.planes.map((p) => p.bytesPerRow).toList(),
      planeBytesPerPixel: image.planes.map((p) => p.bytesPerPixel).toList(),
      boundingBoxLeft: boundingBox.left.toDouble(),
      boundingBoxTop: boundingBox.top.toDouble(),
      boundingBoxRight: boundingBox.right.toDouble(),
      boundingBoxBottom: boundingBox.bottom.toDouble(),
      sensorOrientation: sensorOrientation,
      isFrontCamera: isFrontCamera,
      isIOS: Platform.isIOS,
    );

    return Isolate.run(() => _convertAndCropYUV420Isolate(params));
  }

  /// Synchronous fallback helper for YUV-to-RGB conversion and cropping.
  /// Also updated to fix the iOS NV12 color channel swap bug.
  static img.Image convertAndCropYUV420(
    CameraImage image,
    dynamic boundingBox, {
    int sensorOrientation = 90,
    bool isFrontCamera = false,
  }) {
    final params = YUVConversionParams(
      width: image.width,
      height: image.height,
      planeBytes: image.planes.map((p) => p.bytes).toList(),
      planeBytesPerRow: image.planes.map((p) => p.bytesPerRow).toList(),
      planeBytesPerPixel: image.planes.map((p) => p.bytesPerPixel).toList(),
      boundingBoxLeft: boundingBox.left.toDouble(),
      boundingBoxTop: boundingBox.top.toDouble(),
      boundingBoxRight: boundingBox.right.toDouble(),
      boundingBoxBottom: boundingBox.bottom.toDouble(),
      sensorOrientation: sensorOrientation,
      isFrontCamera: isFrontCamera,
      isIOS: Platform.isIOS,
    );

    return _convertAndCropYUV420Isolate(params);
  }

  /// The internal pixel processing logic that runs inside the isolate.
  static img.Image _convertAndCropYUV420Isolate(YUVConversionParams params) {
    final int width = params.width;
    final int height = params.height;

    int rawLeft = params.boundingBoxLeft.toInt();
    int rawTop = params.boundingBoxTop.toInt();
    int rawRight = params.boundingBoxRight.toInt();
    int rawBottom = params.boundingBoxBottom.toInt();

    // Map bounding box from rotated (upright) space back to raw landscape coordinate space
    if (params.sensorOrientation == 90) {
      rawLeft = params.boundingBoxTop.toInt();
      rawRight = params.boundingBoxBottom.toInt();
      rawTop = height - 1 - params.boundingBoxRight.toInt();
      rawBottom = height - 1 - params.boundingBoxLeft.toInt();
    } else if (params.sensorOrientation == 270) {
      rawLeft = width - 1 - params.boundingBoxBottom.toInt();
      rawRight = width - 1 - params.boundingBoxTop.toInt();
      rawTop = params.boundingBoxLeft.toInt();
      rawBottom = params.boundingBoxRight.toInt();
    } else if (params.sensorOrientation == 180) {
      rawLeft = width - 1 - params.boundingBoxRight.toInt();
      rawRight = width - 1 - params.boundingBoxLeft.toInt();
      rawTop = height - 1 - params.boundingBoxBottom.toInt();
      rawBottom = height - 1 - params.boundingBoxTop.toInt();
    }

    int rawWidth = rawRight - rawLeft;
    int rawHeight = rawBottom - rawTop;

    // Add 10% padding on all sides to avoid extremely tight cuts and match training data
    int paddingX = (rawWidth * 0.10).toInt();
    int paddingY = (rawHeight * 0.10).toInt();

    int left = (rawLeft - paddingX).clamp(0, width - 1);
    int top = (rawTop - paddingY).clamp(0, height - 1);
    int right = (rawRight + paddingX).clamp(0, width - 1);
    int bottom = (rawBottom + paddingY).clamp(0, height - 1);

    int cropWidth = right - left;
    int cropHeight = bottom - top;

    if (cropWidth <= 0 || cropHeight <= 0) {
      return img.Image(width: 1, height: 1);
    }

    final planes = params.planeBytes;
    final int numPlanes = planes.length;

    if (numPlanes < 2) {
      debugPrint('--- AI WARNING: Camera sent only 1 plane. ---');
      return img.Image(width: cropWidth, height: cropHeight);
    }

    final yPlane = planes[0];
    final Uint8List uPlane;
    final Uint8List vPlane;

    if (numPlanes == 3) {
      uPlane = planes[1];
      vPlane = planes[2];
    } else {
      // NV21/NV12: both U and V interleaved in plane 1
      uPlane = planes[1];
      vPlane = planes[1];
    }

    final int yRowStride = params.planeBytesPerRow[0];
    final int uvRowStride = params.planeBytesPerRow[1];
    final int uvPixelStride = params.planeBytesPerPixel[1] ?? 1;

    final croppedImage = img.Image(width: cropWidth, height: cropHeight);

    for (int y = 0; y < cropHeight; y++) {
      final int actualY = top + y;
      final int uvRowOffset = (actualY >> 1) * uvRowStride;
      final int yRowOffset = actualY * yRowStride;

      for (int x = 0; x < cropWidth; x++) {
        final int actualX = left + x;
        
        final int yIndex = (yRowOffset + actualX).clamp(0, yPlane.length - 1);
        final int uvIndex = (uvRowOffset + (actualX >> 1) * uvPixelStride).clamp(0, uPlane.length - 1);

        final int yp = yPlane[yIndex];

        int up, vp;
        if (numPlanes == 3) {
          up = uPlane[uvIndex];
          vp = vPlane[uvIndex < vPlane.length ? uvIndex : vPlane.length - 1];
        } else {
          // NV21 or NV12
          final bytes = planes[1];
          if (params.isIOS) {
            // NV12 format on iOS: plane 1 is U, V, U, V...
            up = bytes[uvIndex.clamp(0, bytes.length - 1)];
            vp = bytes[(uvIndex + 1).clamp(0, bytes.length - 1)];
          } else {
            // NV21 format: plane 1 is V, U, V, U...
            vp = bytes[uvIndex.clamp(0, bytes.length - 1)];
            up = bytes[(uvIndex + 1).clamp(0, bytes.length - 1)];
          }
        }

        // Standard YUV to RGB integer shift formula
        int r = (yp + (vp * 1436 >> 10) - 179).toInt().clamp(0, 255);
        int g = (yp - (up * 352 >> 10) - (vp * 731 >> 10) + 135).toInt().clamp(0, 255);
        int b = (yp + (up * 1814 >> 10) - 227).toInt().clamp(0, 255);

        croppedImage.setPixelRgb(x, y, r, g, b);
      }
    }

    img.Image rotated = croppedImage;
    if (params.sensorOrientation == 90) {
      rotated = img.copyRotate(croppedImage, angle: 90);
    } else if (params.sensorOrientation == 180) {
      rotated = img.copyRotate(croppedImage, angle: 180);
    } else if (params.sensorOrientation == 270) {
      rotated = img.copyRotate(croppedImage, angle: 270);
    }

    if (params.isFrontCamera) {
      rotated = img.copyFlip(rotated, direction: img.FlipDirection.horizontal);
    }

    return rotated;
  }
}
