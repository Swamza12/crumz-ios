import SwiftUI
import AVFoundation
import UIKit

/// Full-screen camera QR code scanner modal matching Android's ML Kit `GmsBarcodeScanning` experience.
/// Automatically detects QR codes (`AVMetadataObject.ObjectType.qr`), supports torch toggle,
/// and gracefully notifies if running on iOS Simulator without a hardware camera.
struct QRCodeScannerModalView: View {
    let onCodeScanned: (String) -> Void
    let onUnavailable: (String) -> Void
    let onCancel: () -> Void

    @State private var isTorchOn: Bool = false

    var body: some View {
        ZStack {
            Color.crumzDarkBlue.ignoresSafeArea()

            CameraQRScannerRepresentable(
                isTorchOn: $isTorchOn,
                onCodeScanned: { code in
                    onCodeScanned(code)
                },
                onCameraUnavailable: { reason in
                    onUnavailable(reason)
                }
            )
            .ignoresSafeArea()

            // Darkened framing overlay + gold corners
            VStack {
                HStack {
                    Button(action: onCancel) {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .bold))
                            Text("Close")
                                .font(.system(size: 14, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.55))
                        .clipShape(Capsule())
                    }

                    Spacer()

                    Button(action: { isTorchOn.toggle() }) {
                        Image(systemName: isTorchOn ? "bolt.fill" : "bolt.slash.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(isTorchOn ? .crumzGold : .white)
                            .frame(width: 42, height: 42)
                            .background(Color.black.opacity(0.55))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                Spacer()

                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.crumzGold, lineWidth: 3)
                        .frame(width: 260, height: 260)
                        .shadow(color: Color.crumzGold.opacity(0.45), radius: 12)
                }

                Spacer().frame(height: 24)

                Text("Align the vendor's Crumz QR code inside the frame")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.55))
                    .clipShape(Capsule())

                Spacer()
            }
        }
    }
}

private struct CameraQRScannerRepresentable: UIViewControllerRepresentable {
    @Binding var isTorchOn: Bool
    let onCodeScanned: (String) -> Void
    let onCameraUnavailable: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerViewController {
        let vc = ScannerViewController()
        vc.onCodeScanned = onCodeScanned
        vc.onCameraUnavailable = onCameraUnavailable
        return vc
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {
        uiViewController.setTorch(enabled: isTorchOn)
    }
}

final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCodeScanned: ((String) -> Void)?
    var onCameraUnavailable: ((String) -> Void)?

    private let captureSession = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var didFinishScan = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .crumzDarkBlue
        checkPermissionAndConfigure()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.layer.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if captureSession.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.captureSession.stopRunning()
            }
        }
    }

    func setTorch(enabled: Bool) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = enabled ? .on : .off
            device.unlockForConfiguration()
        } catch {}
    }

    private func checkPermissionAndConfigure() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.configureSession()
                    } else {
                        self?.onCameraUnavailable?("Camera permission denied — allow Camera in Settings or tap a live bill below.")
                    }
                }
            }
        default:
            DispatchQueue.main.async { [weak self] in
                self?.onCameraUnavailable?("Camera permission denied — allow Camera in Settings or tap a live bill below.")
            }
        }
    }

    private func configureSession() {
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
            onCameraUnavailable?("Camera scanner unavailable on Simulator — tap the live vendor bill below!")
            return
        }

        do {
            let videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
            if captureSession.canAddInput(videoInput) {
                captureSession.addInput(videoInput)
            } else {
                onCameraUnavailable?("Camera scanner unavailable on Simulator — tap the live vendor bill below!")
                return
            }

            if videoCaptureDevice.isAutoFocusRangeRestrictionSupported {
                try? videoCaptureDevice.lockForConfiguration()
                videoCaptureDevice.autoFocusRangeRestriction = .near
                videoCaptureDevice.unlockForConfiguration()
            }
        } catch {
            onCameraUnavailable?("Camera scanner unavailable (\(error.localizedDescription)) — tap the live vendor bill below!")
            return
        }

        let metadataOutput = AVCaptureMetadataOutput()
        if captureSession.canAddOutput(metadataOutput) {
            captureSession.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr]
        } else {
            onCameraUnavailable?("Could not configure QR scanner — tap the live vendor bill below!")
            return
        }

        let preview = AVCaptureVideoPreviewLayer(session: captureSession)
        preview.frame = view.layer.bounds
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)
        previewLayer = preview

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.startRunning()
        }
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !didFinishScan,
              let readable = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let stringValue = readable.stringValue,
              !stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }

        didFinishScan = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        captureSession.stopRunning()
        onCodeScanned?(stringValue)
    }
}
