import ReplayKit
import UIKit

/// Handles screen recording for the Clawdbot node
class ScreenRecordCapability: NSObject {
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var tempVideoURL: URL?

    @MainActor
    func record(durationMs: Int, fps: Int, includeAudio: Bool) async throws -> [String: Any] {
        // Check if screen recording is enabled in settings
        guard AppSettings.shared.allowScreenRecording else {
            throw NodeError(code: .screenRecordingPermissionRequired, message: "Screen recording is disabled in app settings")
        }

        // ReplayKit screen recording
        let recorder = RPScreenRecorder.shared()

        guard recorder.isAvailable else {
            throw NodeError(code: .screenRecordingPermissionRequired, message: "Screen recording not available")
        }

        // Capture screen dimensions on main actor
        let screenWidth = Int(UIScreen.main.bounds.width * UIScreen.main.scale)
        let screenHeight = Int(UIScreen.main.bounds.height * UIScreen.main.scale)

        // Create temp file
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = UUID().uuidString + ".mp4"
        let tempURL = tempDir.appendingPathComponent(fileName)
        tempVideoURL = tempURL

        // Setup asset writer
        let writer = try AVAssetWriter(outputURL: tempURL, fileType: .mp4)

        // Video settings
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: screenWidth,
            AVVideoHeightKey: screenHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 2_000_000,
                AVVideoMaxKeyFrameIntervalKey: fps
            ]
        ]

        let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        vInput.expectsMediaDataInRealTime = true
        writer.add(vInput)
        videoInput = vInput

        // Audio settings (if requested)
        if includeAudio {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 2,
                AVSampleRateKey: 44100.0,
                AVEncoderBitRateKey: 128000
            ]

            let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            aInput.expectsMediaDataInRealTime = true
            writer.add(aInput)
            audioInput = aInput
        }

        assetWriter = writer
        writer.startWriting()

        // Record using async continuation
        let videoData: Data = try await withCheckedThrowingContinuation { continuation in
            var hasStartedSession = false

            recorder.startCapture { [weak self] sampleBuffer, bufferType, error in
                guard let self = self else { return }

                if let error = error {
                    print("Recording error: \(error)")
                    return
                }

                guard CMSampleBufferDataIsReady(sampleBuffer) else { return }

                if !hasStartedSession {
                    hasStartedSession = true
                    self.assetWriter?.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
                }

                switch bufferType {
                case .video:
                    if let input = self.videoInput, input.isReadyForMoreMediaData {
                        input.append(sampleBuffer)
                    }
                case .audioApp, .audioMic:
                    if includeAudio, let input = self.audioInput, input.isReadyForMoreMediaData {
                        input.append(sampleBuffer)
                    }
                @unknown default:
                    break
                }
            } completionHandler: { error in
                if let error = error {
                    continuation.resume(throwing: NodeError(code: .screenRecordingPermissionRequired,
                                                           message: error.localizedDescription))
                }
            }

            // Stop recording after duration
            Task {
                try? await Task.sleep(nanoseconds: UInt64(durationMs) * 1_000_000)

                recorder.stopCapture { [weak self] error in
                    guard let self = self else { return }

                    self.videoInput?.markAsFinished()
                    self.audioInput?.markAsFinished()

                    self.assetWriter?.finishWriting {
                        do {
                            let data = try Data(contentsOf: tempURL)
                            try? FileManager.default.removeItem(at: tempURL)
                            continuation.resume(returning: data)
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                }
            }
        }

        return [
            "format": "mp4",
            "base64": videoData.base64EncodedString()
        ]
    }
}
