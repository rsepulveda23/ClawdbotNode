import Foundation
import SwiftUI

/// Represents a chat message in the conversation
struct ChatMessage: Identifiable, Equatable {
    let id: String
    let role: MessageRole
    let content: String
    let timestamp: Date
    var attachments: [ChatAttachment]
    var isLoading: Bool

    init(
        id: String = UUID().uuidString,
        role: MessageRole,
        content: String,
        timestamp: Date = Date(),
        attachments: [ChatAttachment] = [],
        isLoading: Bool = false
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.attachments = attachments
        self.isLoading = isLoading
    }

    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id
    }
}

enum MessageRole: String, Codable {
    case user
    case assistant
    case system
}

/// Attachment types for chat messages
struct ChatAttachment: Identifiable, Equatable {
    let id: String
    let type: AttachmentType
    let data: Data?
    let url: URL?
    let mimeType: String?

    init(
        id: String = UUID().uuidString,
        type: AttachmentType,
        data: Data? = nil,
        url: URL? = nil,
        mimeType: String? = nil
    ) {
        self.id = id
        self.type = type
        self.data = data
        self.url = url
        self.mimeType = mimeType
    }

    static func == (lhs: ChatAttachment, rhs: ChatAttachment) -> Bool {
        lhs.id == rhs.id
    }
}

enum AttachmentType: String, Codable {
    case image
    case audio
    case file
}
