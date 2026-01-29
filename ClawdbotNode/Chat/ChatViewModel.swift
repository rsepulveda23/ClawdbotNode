import Foundation
import SwiftUI
import PhotosUI
import AVFoundation

/// View model for the chat interface
@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputText: String = ""
    @Published var isRecording: Bool = false
    @Published var selectedImage: UIImage?
    @Published var isSending: Bool = false

    private var audioRecorder: AVAudioRecorder?
    private var audioURL: URL?
    private let sessionKey = "ios-app"

    init() {
        // Add welcome message
        let welcome = ChatMessage(
            role: .assistant,
            content: "Hey! I'm connected and ready to help. What's up?"
        )
        messages.append(welcome)

        // Listen for incoming chat messages
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleIncomingMessage(_:)),
            name: .chatMessageReceived,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleIncomingMessage(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let content = userInfo["content"] as? String else { return }

        let messageId = userInfo["id"] as? String ?? UUID().uuidString

        // Remove loading indicator if present
        if let loadingIndex = messages.firstIndex(where: { $0.isLoading }) {
            messages.remove(at: loadingIndex)
        }

        let message = ChatMessage(
            id: messageId,
            role: .assistant,
            content: content
        )

        Task { @MainActor in
            self.messages.append(message)
        }
    }

    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || selectedImage != nil else { return }

        isSending = true
        inputText = ""

        // Create user message
        var attachments: [ChatAttachment] = []
        var imageBase64: String?

        if let image = selectedImage {
            if let imageData = image.jpegData(compressionQuality: 0.8) {
                attachments.append(ChatAttachment(
                    type: .image,
                    data: imageData,
                    mimeType: "image/jpeg"
                ))
                imageBase64 = imageData.base64EncodedString()
            }
            selectedImage = nil
        }

        let userMessage = ChatMessage(
            role: .user,
            content: text,
            attachments: attachments
        )
        messages.append(userMessage)

        // Add loading indicator
        let loadingMessage = ChatMessage(
            role: .assistant,
            content: "",
            isLoading: true
        )
        messages.append(loadingMessage)

        // Send via gateway
        Task {
            await GatewayClient.shared.sendChatMessage(
                text: text,
                imageBase64: imageBase64,
                sessionKey: sessionKey
            )
            isSending = false
        }
    }

    // MARK: - Image Selection

    func handleImageSelection(_ item: PhotosPickerItem?) {
        guard let item = item else { return }

        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                await MainActor.run {
                    self.selectedImage = image
                }
            }
        }
    }

    // MARK: - Voice Recording

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        let audioSession = AVAudioSession.sharedInstance()

        do {
            try audioSession.setCategory(.playAndRecord, mode: .default)
            try audioSession.setActive(true)

            let tempDir = FileManager.default.temporaryDirectory
            audioURL = tempDir.appendingPathComponent("\(UUID().uuidString).m4a")

            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]

            audioRecorder = try AVAudioRecorder(url: audioURL!, settings: settings)
            audioRecorder?.record()
            isRecording = true
        } catch {
            print("Failed to start recording: \(error)")
        }
    }

    private func stopRecording() {
        audioRecorder?.stop()
        isRecording = false

        guard let url = audioURL,
              let audioData = try? Data(contentsOf: url) else { return }

        // Send audio message
        let attachment = ChatAttachment(
            type: .audio,
            data: audioData,
            mimeType: "audio/m4a"
        )

        let userMessage = ChatMessage(
            role: .user,
            content: "[Voice message]",
            attachments: [attachment]
        )
        messages.append(userMessage)

        // Add loading indicator
        let loadingMessage = ChatMessage(
            role: .assistant,
            content: "",
            isLoading: true
        )
        messages.append(loadingMessage)

        // Send via gateway
        Task {
            await GatewayClient.shared.sendChatMessage(
                text: nil,
                audioBase64: audioData.base64EncodedString(),
                sessionKey: sessionKey
            )
        }

        // Clean up
        try? FileManager.default.removeItem(at: url)
        audioURL = nil
    }

    func clearChat() {
        messages.removeAll()
        let welcome = ChatMessage(
            role: .assistant,
            content: "Chat cleared. How can I help?"
        )
        messages.append(welcome)
    }
}

// MARK: - Notification Extension

extension Notification.Name {
    static let chatMessageReceived = Notification.Name("chatMessageReceived")
}
