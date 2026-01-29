import AVFoundation
import UIKit

/// Handles camera operations for the Clawdbot node
class CameraCapability: NSObject {
    private var captureSession: AVCaptureSession?
    private var photoOutput: AVCapturePhotoOutput?
    private var videoOutput: AVCaptureMovieFileOutput?
    private var previewLayer: AVCaptureVideoPreviewLayer?

    private var photoContinuation: CheckedContinuation<Data, Error>?
    private var videoContinuation: CheckedContinuation<Data, Error>?
    private var tempVideoURL: URL?

    // MARK: - Camera List

    func listCameras() async throws -> [String: Any] {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera],
            mediaType: .video,
            position: .unspecified
        )

        let devices = discoverySession.devices.map { device -> [String: Any] in
            return [
                "id": device.uniqueID,
                "name": device.localizedName,
                "position": device.position == .front ? "front" : "back",
                "deviceType": deviceTypeString(device.deviceType)
            ]
        }

        return ["devices": devices]
    }

    private func deviceTypeString(_ type: AVCaptureDevice.DeviceType) -> String {
        switch type {
        case .builtInWideAngleCamera: return "wide"
        case .builtInUltraWideCamera: return "ultrawide"
        case .builtInTelephotoCamera: return "telephoto"
        default: return "unknown"
        }
    }

    // MARK: - Camera Snap

    func snap(facing: String, maxWidth: Int, quality: Double, format: String, delayMs: Int) async throws -> [String: Any] {
        // Check permissions
        guard await checkCameraPermission() else {
            throw NodeError(code: .cameraPermissionRequired, message: "Camera permission not granted")
        }

        // Check if camera is enabled in settings
        guard AppSettings.shared.allowCamera else {
            throw NodeError(code: .cameraDisabled, message: "Camera is disabled in app settings")
        }

        // Apply delay if specified
        if delayMs > 0 {
            try await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
        }

        // Setup capture session
        let session = AVCaptureSession()
        session.sessionPreset = .photo

        // Get camera device
        let position: AVCaptureDevice.Position = facing == "front" ? .front : .back
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            throw NodeError(code: .cameraDisabled, message: "No camera available for position: \(facing)")
        }

        // Add input
        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input) else {
            throw NodeError(code: .cameraDisabled, message: "Cannot add camera input")
        }
        session.addInput(input)

        // Add photo output
        let output = AVCapturePhotoOutput()
        guard session.canAddOutput(output) else {
            throw NodeError(code: .cameraDisabled, message: "Cannot add photo output")
        }
        session.addOutput(output)

        captureSession = session
        photoOutput = output

        // Start session
        session.startRunning()

        // Wait for session to stabilize
        try await Task.sleep(nanoseconds: 500_000_000) // 500ms

        // Capture photo
        let photoData = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            self.photoContinuation = continuation

            let settings = AVCapturePhotoSettings()
            if output.availablePhotoCodecTypes.contains(.jpeg) {
                settings.photoQualityPrioritization = .balanced
            }

            output.capturePhoto(with: settings, delegate: self)
        }

        // Stop session
        session.stopRunning()

        // Process image
        guard let image = UIImage(data: photoData) else {
            throw NodeError(code: .cameraDisabled, message: "Failed to process captured image")
        }

        // Resize if needed
        let resizedImage = resizeImage(image, maxWidth: CGFloat(maxWidth))

        // Compress to format
        let outputData: Data?
        if format.lowercased() == "png" {
            outputData = resizedImage.pngData()
        } else {
            outputData = resizedImage.jpegData(compressionQuality: quality)
        }

        guard let finalData = outputData else {
            throw NodeError(code: .cameraDisabled, message: "Failed to encode image")
        }

        // Ensure under 5MB
        var compressedData = finalData
        var compressionQuality = quality
        while compressedData.count > 5_000_000 && compressionQuality > 0.1 {
            compressionQuality -= 0.1
            if let recompressed = resizedImage.jpegData(compressionQuality: compressionQuality) {
                compressedData = recompressed
            }
        }

        return [
            "format": format.lowercased() == "png" ? "png" : "jpg",
            "base64": compressedData.base64EncodedString(),
            "width": Int(resizedImage.size.width),
            "height": Int(resizedImage.size.height)
        ]
    }

    private func resizeImage(_ image: UIImage, maxWidth: CGFloat) -> UIImage {
        guard image.size.width > maxWidth else { return image }

        let scale = maxWidth / image.size.width
        let newSize = CGSize(width: maxWidth, height: image.size.height * scale)

        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let resized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return resized ?? image
    }

    // MARK: - Camera Clip

    func clip(facing: String, durationMs: Int, includeAudio: Bool, format: String) async throws -> [String: Any] {
        // Check permissions
        guard await checkCameraPermission() else {
            throw NodeError(code: .cameraPermissionRequired, message: "Camera permission not granted")
        }

        guard AppSettings.shared.allowCamera else {
            throw NodeError(code: .cameraDisabled, message: "Camera is disabled in app settings")
        }

        if includeAudio {
            guard await checkMicrophonePermission() else {
                throw NodeError(code: .recordAudioPermissionRequired, message: "Microphone permission not granted")
            }
        }

        // Setup capture session
        let session = AVCaptureSession()
        session.sessionPreset = .high

        // Get camera device
        let position: AVCaptureDevice.Position = facing == "front" ? .front : .back
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            throw NodeError(code: .cameraDisabled, message: "No camera available for position: \(facing)")
        }

        // Add video input
        let videoInput = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(videoInput) else {
            throw NodeError(code: .cameraDisabled, message: "Cannot add video input")
        }
        session.addInput(videoInput)

        // Add audio input if requested
        if includeAudio, let audioDevice = AVCaptureDevice.default(for: .audio) {
            let audioInput = try AVCaptureDeviceInput(device: audioDevice)
            if session.canAddInput(audioInput) {
                session.addInput(audioInput)
            }
        }

        // Add movie output
        let movieOutput = AVCaptureMovieFileOutput()
        guard session.canAddOutput(movieOutput) else {
            throw NodeError(code: .cameraDisabled, message: "Cannot add movie output")
        }
        session.addOutput(movieOutput)

        captureSession = session
        videoOutput = movieOutput

        // Start session
        session.startRunning()

        // Wait for session to stabilize
        try await Task.sleep(nanoseconds: 300_000_000) // 300ms

        // Create temp file
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = UUID().uuidString + ".mp4"
        let tempURL = tempDir.appendingPathComponent(fileName)
        tempVideoURL = tempURL

        // Start recording
        let videoData = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            self.videoContinuation = continuation

            movieOutput.maxRecordedDuration = CMTime(value: Int64(durationMs), timescale: 1000)
            movieOutput.startRecording(to: tempURL, recordingDelegate: self)
        }

        // Stop session
        session.stopRunning()

        // Cleanup temp file
        if let url = tempVideoURL {
            try? FileManager.default.removeItem(at: url)
        }

        return [
            "format": "mp4",
            "base64": videoData.base64EncodedString(),
            "durationMs": durationMs,
            "hasAudio": includeAudio
        ]
    }

    // MARK: - Permission Checks

    private func checkCameraPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }

    private func checkMicrophonePermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }
}

// MARK: - Photo Capture Delegate
extension CameraCapability: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            photoContinuation?.resume(throwing: error)
            photoContinuation = nil
            return
        }

        guard let data = photo.fileDataRepresentation() else {
            photoContinuation?.resume(throwing: NodeError(code: .cameraDisabled, message: "Failed to get photo data"))
            photoContinuation = nil
            return
        }

        photoContinuation?.resume(returning: data)
        photoContinuation = nil
    }
}

// MARK: - Video Recording Delegate
extension CameraCapability: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            videoContinuation?.resume(throwing: error)
            videoContinuation = nil
            return
        }

        do {
            let data = try Data(contentsOf: outputFileURL)
            videoContinuation?.resume(returning: data)
        } catch {
            videoContinuation?.resume(throwing: error)
        }
        videoContinuation = nil
    }
}
