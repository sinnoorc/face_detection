import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class HomeController extends GetxController {
  List<Color> splashColors = [
    Colors.red,
    Colors.green,
    Colors.blue,
    Colors.yellow,
    Colors.purple,
    Colors.orange,
  ];

  Rx<Color> overlayColor = Colors.transparent.obs;
  int currentColorIndex = 0;

  late CameraController cameraController;

  late final FaceDetector faceDetector;
  RxBool isFaceDetected = false.obs;
  RxBool isFaceInsideBox = false.obs;
  RxString instructionText = 'Align your face within the frame'.obs;
  Rx<CameraImage?> currentImage = Rx<CameraImage?>(null);
  Rx<Rect?> adjustedBoundingBox = Rx<Rect?>(null);

  int frameSkipCount = 0; // Counter to skip frames

  @override
  void onInit() async {
    await initializeCamera();
    faceDetector = FaceDetector(options: FaceDetectorOptions(enableClassification: true));
    super.onInit();
  }

  Future<void> initializeCamera() async {
    final cameras = await availableCameras();
    final frontCamera = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );
    cameraController = CameraController(frontCamera, ResolutionPreset.medium);
    await cameraController.initialize();
    startImageStream();
    update();
  }

  void startImageStream() {
    cameraController.startImageStream((CameraImage image) {
      if (frameSkipCount >= 5) {
        // Process every 5th frame
        detectFaces(image);
        frameSkipCount = 0;
      } else {
        frameSkipCount++;
      }
    });
  }

  void detectFaces(CameraImage image) async {
    try {
      if (!cameraController.value.isInitialized) {
        return;
      }
      final WriteBuffer allBytes = WriteBuffer();
      for (Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final camera = cameraController.description;

      final Size imageSize = Size(image.width.toDouble(), image.height.toDouble());
      final InputImage inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: imageSize,
          rotation: InputImageRotationValue.fromRawValue(camera.sensorOrientation) ?? InputImageRotation.rotation0deg,
          format: InputImageFormatValue.fromRawValue(image.format.raw) ?? InputImageFormat.yuv420,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      );
      final screenSize = Get.size;

      final faces = await faceDetector.processImage(inputImage);
      isFaceDetected.value = faces.isNotEmpty;

      if (isFaceDetected.value) {
        final face = faces.first;
        adjustedBoundingBox.value = face.boundingBox;
        // Check if the face is within the desired area
        isFaceInsideBox.value = isFaceWithinBounds(
          face.boundingBox,
          screenSize,
          cameraController,
        );
        Get.log('Screen size: $screenSize');
        Get.log('Camera preview size: ${cameraController.value.previewSize}');
        Get.log('ScaleX: ${screenSize.width / cameraController.value.previewSize!.width}');
        Get.log('Overlay Rect: $screenSize');
        Get.log('Adjusted bounding box: ${face.boundingBox}');
        // Update instructions based on face position
        instructionText.value =
            isFaceInsideBox.value ? 'Face is aligned, please hold still' : 'Align your face within the frame';

        // Call AWS Rekognition for liveness detection if face is aligned
        if (isFaceInsideBox.value) {
          checkLiveness(image, face);
        }
      } else {
        instructionText.value = 'No face detected';
      }
    } catch (e) {
      // Handle face detection errors
      instructionText.value = 'Error detecting face: ${e.toString()}';
      Get.snackbar('Error detect', e.toString());
    }
  }

  bool isFaceWithinBounds(Rect boundingBox, Size screenSize, CameraController cameraController) {
    // Calculate the scale factors
    final previewSize = cameraController.value.previewSize!;

    // Calculate the overlay rectangle size to match the camera's aspect ratio
    final cameraAspectRatio = previewSize.height / previewSize.width;
    final overlayWidth = screenSize.width * 0.85; // for example
    final overlayHeight = overlayWidth / cameraAspectRatio;

    // Calculate the overlay rectangle position
    final overlayX = (screenSize.width - overlayWidth) / 2;
    final overlayY = (screenSize.height - overlayHeight) / 2;
    final Rect overlayRect = Rect.fromLTWH(overlayX, overlayY, overlayWidth, overlayHeight);
    final scaleX = screenSize.width / cameraController.value.previewSize!.width;
    final scaleY = screenSize.height / cameraController.value.previewSize!.height;

    final adjustedBoundingBox = Rect.fromLTWH(
      boundingBox.left * scaleX,
      boundingBox.top * scaleY,
      boundingBox.width * scaleX,
      boundingBox.height * scaleY,
    );

    // Set the adjustedBoundingBox value to be used in painting.
    this.adjustedBoundingBox.value = adjustedBoundingBox;

    // Check if the adjusted bounding box is entirely within the overlay rectangle.
    return overlayRect.overlaps(adjustedBoundingBox);
  }

  // Perform liveness detection with AWS Rekognition
  void checkLiveness(CameraImage image, Face face) {
    Get.log('Checking liveness');
    toggleOverlayColor();
  }

  void toggleOverlayColor() async {
    overlayColor.value = splashColors[currentColorIndex];
    currentColorIndex = (currentColorIndex + 1) % splashColors.length;
    Future.delayed(const Duration(seconds: 2), () {
      overlayColor.value = Colors.transparent;
    });
  }

  @override
  void onClose() {
    cameraController.stopImageStream().catchError((error) {
      Get.snackbar('Error', error.toString());
    });
    cameraController.dispose();
    super.onClose();
  }
}
