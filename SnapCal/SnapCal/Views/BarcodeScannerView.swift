import AVFoundation
import SwiftUI
import UIKit

// AVFoundation-backed barcode capture. Returns the first valid code via the
// onScanned callback, then stops the session so the camera doesn't keep
// firing while the confirm sheet is up. The owning view re-presents this
// when the user taps "Scan again".
struct BarcodeScannerView: UIViewControllerRepresentable {
    let onScanned: (String) -> Void
    let onError: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerViewController {
        let vc = ScannerViewController()
        vc.onScanned = onScanned
        vc.onError = onError
        return vc
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}

    final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
        var onScanned: ((String) -> Void)?
        var onError: ((String) -> Void)?

        private let session = AVCaptureSession()
        private var previewLayer: AVCaptureVideoPreviewLayer?
        private let supportedTypes: [AVMetadataObject.ObjectType] = [
            .ean8, .ean13, .upce, .code128, .code39, .code93, .pdf417, .interleaved2of5
        ]

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            configureSession()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            previewLayer?.frame = view.layer.bounds
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            startSession()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            stopSession()
        }

        private func configureSession() {
            guard let device = AVCaptureDevice.default(for: .video) else {
                onError?("Camera unavailable on this device.")
                return
            }
            do {
                let input = try AVCaptureDeviceInput(device: device)
                guard session.canAddInput(input) else {
                    onError?("Couldn't access the camera input.")
                    return
                }
                session.addInput(input)

                let output = AVCaptureMetadataOutput()
                guard session.canAddOutput(output) else {
                    onError?("Couldn't attach barcode reader.")
                    return
                }
                session.addOutput(output)
                output.setMetadataObjectsDelegate(self, queue: .main)
                output.metadataObjectTypes = supportedTypes.filter { output.availableMetadataObjectTypes.contains($0) }

                let preview = AVCaptureVideoPreviewLayer(session: session)
                preview.videoGravity = .resizeAspectFill
                preview.frame = view.layer.bounds
                view.layer.addSublayer(preview)
                self.previewLayer = preview
            } catch {
                onError?(error.localizedDescription)
            }
        }

        private func startSession() {
            guard !session.isRunning else { return }
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.session.startRunning()
            }
        }

        private func stopSession() {
            guard session.isRunning else { return }
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.session.stopRunning()
            }
        }

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            guard
                let object = metadataObjects.compactMap({ $0 as? AVMetadataMachineReadableCodeObject }).first,
                let code = object.stringValue,
                !code.isEmpty
            else { return }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            stopSession()
            onScanned?(code)
        }
    }
}
