import SwiftUI
import UIKit

// Minimal UIImagePickerController wrapper. Week 1 scope: pick OR snap a photo, return UIImage.
// Week 3+: replace with AVFoundation custom camera for LiDAR depth + reference-object overlay.
struct CameraView: UIViewControllerRepresentable {
    let onPicked: (UIImage) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPicked: onPicked) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onPicked: (UIImage) -> Void
        init(onPicked: @escaping (UIImage) -> Void) { self.onPicked = onPicked }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]
        ) {
            if let image = info[.originalImage] as? UIImage { onPicked(image) }
            picker.dismiss(animated: true)
        }
    }
}
