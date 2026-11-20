import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../l10n/l10n.dart';
import '../theme/app_theme.dart';

/// Full-screen QR scanner for clinic check-in.
///
/// Pops with the scanned QR token string when a barcode is detected.
/// Pops with null when the user closes without scanning.
///
/// Never logs the raw token value.
class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  MobileScannerController? _controller;
  bool _hasScanned = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasScanned) return;

    final barcode = capture.barcodes.firstOrNull;
    if (barcode?.rawValue == null) return;

    _hasScanned = true;
    // Never log the raw token
    debugPrint('[QrScannerScreen] QR barcode detected (token hidden).');
    Navigator.of(context).pop(barcode!.rawValue);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        key: const Key('qr_scanner_app_bar'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          l10n.scanQrTitle,
          style: const TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: l10n.closeButton,
          onPressed: () => Navigator.of(context).pop(null),
        ),
        actions: [
          IconButton(
            key: const Key('qr_scanner_torch_button'),
            icon: const Icon(Icons.flash_on),
            tooltip: 'Flash',
            onPressed: () => _controller?.toggleTorch(),
          ),
          IconButton(
            key: const Key('qr_scanner_flip_button'),
            icon: const Icon(Icons.flip_camera_ios),
            tooltip: 'Flip camera',
            onPressed: () => _controller?.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          // --- Scanner Viewport ---
          MobileScanner(
            key: const Key('qr_scanner_viewport'),
            controller: _controller,
            onDetect: _onDetect,
          ),

          // --- Overlay with instructions ---
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black87, Colors.transparent],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.qr_code_scanner_rounded,
                    color: AppTheme.accent,
                    size: 40,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.scanQrInstructions,
                    key: const Key('qr_scanner_instructions_text'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // --- Viewfinder frame ---
          Center(
            child: Container(
              width: 248,
              height: 248,
              decoration: BoxDecoration(
                border: Border.all(
                  color: AppTheme.accent,
                  width: 3,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.accent.withValues(alpha: 0.2),
                    blurRadius: 24,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
