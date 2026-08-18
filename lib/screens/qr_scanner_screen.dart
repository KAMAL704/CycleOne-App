import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final MobileScannerController _cameraController = MobileScannerController();
  bool _isProcessing = false;
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void dispose() {
    _cameraController.dispose();
    super.dispose();
  }

  // Scan QR from gallery using mobile_scanner
  Future<void> _scanFromGallery() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      final XFile? image = await _imagePicker.pickImage(source: ImageSource.gallery);
      if (image == null) {
        setState(() => _isProcessing = false);
        return;
      }
      await _cameraController.start();
      await Future.delayed(const Duration(milliseconds:  500));


      final File imageFile = File(image.path);
      final String imagePath = imageFile.path;
      // Use mobile_scanner to decode QR from image file
      final BarcodeCapture? capture = await _cameraController.analyzeImage(imagePath);
      if (capture != null && capture.barcodes.isNotEmpty) {
        final String? rawValue = capture.barcodes.first.rawValue;
        if (rawValue != null && rawValue.isNotEmpty) {
          if (mounted){
            await _cameraController.stop();
            Navigator.pop(context, rawValue);
    }
          return;
        }
      }
      // No QR found
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No QR code found in the selected image')),
        );
      }
      setState(() => _isProcessing = false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error reading image: $e')),
        );
      }
      setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan QR Code'),
        actions: [
          IconButton(
            icon: const Icon(Icons.photo_library),
            onPressed: _scanFromGallery,
            tooltip: 'Choose from gallery',
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _cameraController,
            onDetect: (capture) async {
              if (_isProcessing) return;
              final barcodes = capture.barcodes;
              for (final barcode in barcodes) {
                final rawValue = barcode.rawValue;
                if (rawValue != null && rawValue.isNotEmpty) {
                  setState(() => _isProcessing = true);
                  await _cameraController.stop();
                  if (mounted) Navigator.pop(context, rawValue);
                  return;
                }
              }
            },
          ),
          Positioned(
            bottom: 32,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: const Text(
                  'Align QR code inside the frame\nor tap 📷 to pick from gallery',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _cameraController.toggleTorch(),
        child: const Icon(Icons.flash_on),
      ),
    );
  }
}