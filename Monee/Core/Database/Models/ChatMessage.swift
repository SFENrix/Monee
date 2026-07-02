
//
//  ChatMessage.swift
//  FreelanceFinance
//
//  Created by Rio Ferdinand on 02/07/26.
//
//  One turn inside a ChatSession. See the note in ChatSession.swift for why this
//  uses a plain `sessionID` foreign key instead of a SwiftData @Relationship.
//

import Foundation
import SwiftData

enum ChatRole: String, Codable {
    case user
    case assistant
}

@Model
final class ChatMessage {
    var id: UUID
    var sessionID: UUID
    var role: ChatRole
    var content: String
    var timestamp: Date

    init(sessionID: UUID, role: ChatRole, content: String, timestamp: Date = Date()) {
        self.id = UUID()
        self.sessionID = sessionID
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}
