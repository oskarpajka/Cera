//
//  CameraService.swift
//  Cera
//
//  Created by Oskar Pajka on 25/02/2026.
//

import AVFoundation
import os

// MARK: - Camera Permission

enum CameraPermission: Sendable {
    case authorized
    case denied
    case notDetermined
}

// MARK: - Camera Service

/// Manages the AVCaptureSession and streams video frames for processing.
///
/// Runs all AVFoundation work on a dedicated serial queue to satisfy
/// `AVCaptureVideoDataOutputSampleBufferDelegate` threading requirements
/// and to keep the main thread free.
final class CameraService: NSObject, @unchecked Sendable {

    // MARK: - Public Properties

    let session = AVCaptureSession()

    /// The latest pixel buffer from the camera.
    /// Thread-safe: written on the camera queue, read from any thread.
    var latestPixelBuffer: CVPixelBuffer? {
        bufferLock.withLock { _latestPixelBuffer }
    }

    // MARK: - Private Properties

    private let captureQueue = DispatchQueue(label: "com.cera.camera", qos: .userInitiated)
    private var isConfigured = false
    private var _latestPixelBuffer: CVPixelBuffer?
    private let bufferLock = OSAllocatedUnfairLock()

    // MARK: - Permission

    static var permissionStatus: CameraPermission {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:            return .authorized
        case .denied, .restricted:   return .denied
        case .notDetermined:         return .notDetermined
        @unknown default:            return .denied
        }
    }

    static func requestPermission() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    // MARK: - Session Configuration

    func configure() {
        guard !isConfigured else { return }

        session.beginConfiguration()
        session.sessionPreset = .hd1920x1080

        // Camera input
        guard
            let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: camera),
            session.canAddInput(input)
        else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)

        // Video data output (for live frame processing)
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: captureQueue)

        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)

            // Lock orientation to portrait so Vision coordinates stay consistent
            if let connection = videoOutput.connection(with: .video) {
                connection.videoRotationAngle = 90
            }
        }

        session.commitConfiguration()
        isConfigured = true
    }

    // MARK: - Session Lifecycle

    func start() {
        guard isConfigured else { return }
        captureQueue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func stop() {
        captureQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        bufferLock.withLock { _latestPixelBuffer = pixelBuffer }
    }
}
