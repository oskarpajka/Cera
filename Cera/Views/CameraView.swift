//
//  CameraView.swift
//  Cera
//
//  Created by Oskar Pajka on 25/02/2026.
//

import SwiftUI
import AVFoundation

// MARK: - Camera Preview (UIViewRepresentable)

/// Wraps an `AVCaptureVideoPreviewLayer` for display in SwiftUI.
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {}
}

// MARK: - Camera Preview UIView

/// A `UIView` subclass that hosts an `AVCaptureVideoPreviewLayer`
/// and keeps it sized to fill the view bounds.
final class CameraPreviewUIView: UIView {
    let previewLayer = AVCaptureVideoPreviewLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.addSublayer(previewLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
    }
}
