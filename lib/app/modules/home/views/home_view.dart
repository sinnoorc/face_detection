import 'package:camera/camera.dart';
import 'package:face_detection/app/modules/home/controllers/face_detection_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class HomeView extends GetView<FaceDetectionController> {
  const HomeView({Key? key}) : super(key: key);

  @override
  FaceDetectionController get controller => Get.put(FaceDetectionController());

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        appBar: AppBar(title: const Text('Selfie Verification')),
        body: GetBuilder<FaceDetectionController>(
          init: controller,
          builder: (controller) {
            return controller.isCameraInitialized
                ? Obx(() => buildCameraStack(context, controller))
                : const Center(child: CircularProgressIndicator());
          },
        ),
      ),
    );
  }

  Widget buildCameraStack(BuildContext context, FaceDetectionController controller) {
    return Stack(
      alignment: Alignment.center,
      children: <Widget>[
        CameraPreview(controller.cameraController!),
        AnimatedBuilder(
          animation: controller.colorAnimation,
          builder: (_, __) => Container(
            // color: controller.overlayColor.value.withOpacity(0.7),
            color: controller.colorAnimation.value == Colors.transparent
                ? null
                : controller.colorAnimation.value!.withOpacity(0.7),
          ),
        ),
        Align(
          alignment: Alignment.center,
          child: CustomPaint(
            size: Size(MediaQuery.of(context).size.width, MediaQuery.of(context).size.height),
            painter: FaceBoundsPainter(
              controller.isFaceInsideBox,
              controller.cameraController!,
            ),
          ),
        ),
        Positioned(
          bottom: 50.0,
          child: Text(
            controller.instructionText,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18.0,
            ),
          ),
        ),
      ],
    );
  }
}

class FaceBoundsPainter extends CustomPainter {
  final bool isFaceInsideBox;
  final CameraController cameraController;

  FaceBoundsPainter(this.isFaceInsideBox, this.cameraController);

  @override
  void paint(Canvas canvas, Size size) {
    // Check if the controller is initialized.
    if (!cameraController.value.isInitialized) {
      return;
    }

    // Define the color of the rectangle based on whether the face is inside the box.
    final paint = Paint()
      ..color = isFaceInsideBox ? Colors.green : Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    // Calculate the overlay rectangle size to match the camera's aspect ratio.
    final overlayWidth = size.width * 0.85; // For example, 85% of screen width.
    final overlayHeight = size.height * 0.50; // For example, 50% of screen height.

    // Calculate the overlay rectangle position.
    final overlayX = (size.width - overlayWidth) / 2;
    final overlayY = (size.height - overlayHeight) / 2;

    // Create the fixed overlay rectangle.
    final Rect overlayRect = Rect.fromLTWH(overlayX, overlayY, overlayWidth, overlayHeight);

    // Draw the overlay rectangle.
    canvas.drawRect(overlayRect, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}
