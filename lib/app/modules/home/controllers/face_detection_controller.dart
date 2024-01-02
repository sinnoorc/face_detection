import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class FaceDetectionController extends GetxController with GetTickerProviderStateMixin {
  late AnimationController animationController;
  CameraController? cameraController;
  late Animation<Color?> colorAnimation;
  late FaceDetector faceDetector;
  Timer? facePositionTimer;
  Timer? countdownTimer;
  int frameSkipCount = 0;
  Timer? noFaceDetectedTimer;

  Rx<Color> overlayColor = Colors.transparent.obs;
  int currentColorIndex = 0;

  final List<Color> _splashColors = [
    Colors.red,
    Colors.green,
    Colors.blue,
    Colors.yellow,
    Colors.purple,
    Colors.orange,
  ];

  final Rx<Rect?> _adjustedBoundingBox = Rx<Rect?>(null);
  final Rx<CameraImage?> _currentImage = Rx<CameraImage?>(null);
  final RxString _instructionText = 'Align your face within the frame'.obs;
  final RxBool _isFaceDetected = false.obs;
  final RxBool _isFaceInsideBox = false.obs;
  final RxBool _isCameraInitialized = false.obs;

  RxBool showRetryButton = false.obs;

  bool isCountdownStarted = false;

  bool get isFaceDetected => _isFaceDetected.value;
  bool get isFaceInsideBox => _isFaceInsideBox.value;
  bool get isCameraInitialized => _isCameraInitialized.value;

  String get instructionText => _instructionText.value;
  CameraImage? get currentImage => _currentImage.value;
  Rect? get adjustedBoundingBox => _adjustedBoundingBox.value;

  Future<void> _initializeCamera() async {
    final cameras = await availableCameras();
    final frontCamera = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );
    cameraController = CameraController(frontCamera, ResolutionPreset.high);

    await cameraController?.initialize().then((_) {
      _isCameraInitialized.value = true;
    }).catchError((error) {
      _isCameraInitialized.value = false;
    });
    if (_isCameraInitialized.value) {
      _startImageStream();
    }
    update();
  }

  Future<void> _initializeFaceDetector() async {
    faceDetector = FaceDetector(
      options: FaceDetectorOptions(enableClassification: true, enableTracking: true),
    );
  }

  _startImageStream() {
    if (cameraController!.value.isStreamingImages) return;
    return cameraController?.startImageStream((CameraImage image) {
      if (frameSkipCount >= 5) {
        _detectFaces(image);
        frameSkipCount = 0;
      } else {
        frameSkipCount++;
      }
    });
  }

  _setupAnimation() {
    // Assuming you want to animate between the first and second color initially
    colorAnimation = ColorTween(
      begin: _splashColors[0],
      end: _splashColors[1],
    ).animate(animationController)
      ..addListener(() {
        // This will be called each time the animation value changes
        overlayColor.value = colorAnimation.value!;
        update(); // This will trigger the GetBuilder to rebuild the UI
      })
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          // Reset to initial value and change to the next color
          animationController.reset();
          _startNextColorAnimation();
        }
      });
  }

  void _startNextColorAnimation() {
    // This will cycle through your colors
    currentColorIndex = (currentColorIndex + 1) % _splashColors.length;
    final nextColorIndex = (currentColorIndex + 1) % _splashColors.length;
    colorAnimation = ColorTween(
      begin: _splashColors[currentColorIndex],
      end: _splashColors[nextColorIndex],
    ).animate(animationController);

    animationController.forward();
  }

  Future<void> initialize() async {
    await Future.wait([
      _initializeCamera(),
      _initializeFaceDetector(),
    ]);
    _setupAnimation();
    _setupNoFaceDetectedTimer();
  }

  void _setupNoFaceDetectedTimer() {
    noFaceDetectedTimer = Timer(const Duration(seconds: 10), () {
      _instructionText.value = 'No face detected, please try again.';
      // Logic to show retry button
    });
  }

  void _startFacePositionTimer() {
    facePositionTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (_isFaceInsideBox.value) {
        // Face is still in the correct position
      } else {
        _instructionText.value = 'Face moved, please try again.';
        timer.cancel();
        // Logic to show retry button
      }
    });
  }

  void _startCountdownAnimation() {
    if (!isCountdownStarted) {
      isCountdownStarted = true; // Set the flag to true to prevent re-triggering
      int countdown = 3;
      _instructionText.value = 'Hold face position during countdown: $countdown';
      countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (countdown > 0) {
          _instructionText.value = 'Hold face position during countdown: $countdown';
          countdown--;
        } else {
          timer.cancel();
          _instructionText.value = 'Hold still';
          _startSplashColorAnimation();
        }
      });
    }
  }

  void retryDetection() {
    // Reset all states and timers
    showRetryButton.value = false;
    isCountdownStarted = false;
    _isFaceDetected.value = false;
    _isFaceInsideBox.value = false;
    overlayColor.value = Colors.transparent;
    animationController.reset();

    // Restart face detection
    _startImageStream();
    _setupNoFaceDetectedTimer();
    update();
  }

  void _startSplashColorAnimation() {
    animationController.forward();
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

    final newAdjustedBoundingBox = Rect.fromLTWH(
      boundingBox.left * scaleX,
      boundingBox.top * scaleY,
      boundingBox.width * scaleX,
      boundingBox.height * scaleY,
    );

    // Set the adjustedBoundingBox value to be used in painting.
    _adjustedBoundingBox.value = newAdjustedBoundingBox;

    // Check if the adjusted bounding box is entirely within the overlay rectangle.
    return overlayRect.overlaps(newAdjustedBoundingBox);
  }

  Future<void> _detectFaces(CameraImage image) async {
    if (!cameraController!.value.isInitialized) return;
    final WriteBuffer allBytes = WriteBuffer();
    for (Plane plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();

    final camera = cameraController!.description;

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
    _isFaceDetected.value = faces.isNotEmpty;
    Get.log('Face detected: $_isFaceDetected');

    if (_isFaceDetected.value) {
      final face = faces.first;
      _adjustedBoundingBox.value = face.boundingBox;
      // Check if the face is within the desired area
      _isFaceInsideBox.value = isFaceWithinBounds(
        face.boundingBox,
        screenSize,
        cameraController!,
      );
      Get.log('Screen size: $screenSize');
      Get.log('Camera preview size: ${cameraController!.value.previewSize}');
      Get.log('ScaleX: ${screenSize.width / cameraController!.value.previewSize!.width}');
      Get.log('Overlay Rect: $screenSize');
      Get.log('Adjusted bounding box: ${face.boundingBox}');
      // Update instructions based on face position
      _instructionText.value =
          _isFaceInsideBox.value ? 'Face is aligned, please hold still' : 'Align your face within the frame';

      // Call AWS Rekognition for liveness detection if face is aligned
      if (_isFaceInsideBox.value) {
        // Only start the countdown if it has not already been started.
        if (!isCountdownStarted) {
          noFaceDetectedTimer?.cancel(); // Stop the no face detected timer.
          _startCountdownAnimation();
        }
      } else {
        // If the face leaves the bounding box, reset the countdown.
        _resetCountdown();
        resetDetection();
      }
    } else {
      // If no face is detected, reset the countdown.
      _resetCountdown();
      resetDetection();
    }
  }

  void _resetCountdown() {
    // Reset the flag
    isCountdownStarted = false;
    // Cancel any existing timers
    countdownTimer?.cancel();
    facePositionTimer?.cancel();
    // Reset the animation
    animationController.reset();
    // Update UI if needed
    _instructionText.value = 'Align your face within the frame';
    // Consider setting up the no face detected timer again if needed
    _setupNoFaceDetectedTimer();
  }

  void resetDetection() {
    // Reset all states and flags
    showRetryButton.value = false;
    _isFaceDetected.value = false;
    _isFaceInsideBox.value = false;
    isCountdownStarted = false;
    overlayColor.value = Colors.transparent;

    // Reset the animation
    animationController.reset();

    // Cancel and clear timers
    countdownTimer?.cancel();
    facePositionTimer?.cancel();
    noFaceDetectedTimer?.cancel();

    // Setup timers again if needed, or start a new detection phase
    _setupNoFaceDetectedTimer();
    _startImageStream();

    update();
  }

  @override
  void onClose() {
    facePositionTimer?.cancel();
    noFaceDetectedTimer?.cancel();
    countdownTimer?.cancel();
    isCountdownStarted = false;

    animationController.dispose();
    cameraController?.dispose();
    super.onClose();
  }

  @override
  void onInit() {
    initialize();
    super.onInit();
  }
}
