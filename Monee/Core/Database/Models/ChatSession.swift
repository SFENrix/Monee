//
//  ChatSession.swift
//  FreelanceFinance
//
//  Created by Rio Ferdinand on 30/06/26.
//  Restructured 02/07/26 — was one row per Q&A pair, which can't represent a multi-turn
//  conversation or a "list of past chats". Split into ChatSession (this file, the thread
//  itself) + ChatMessage (each turn). Linked by a plain `sessionID`, not a SwiftData
//  @Relationship — relationships add cascade-delete rules and fetch complexity we don't
//  have time to debug this week. If this needs to get more robust later, that migration
//  is contained to this file + ChatMessage.swift.
//

import Foundation
import SwiftData

@Model
final class ChatSession {
    var id: UUID
    /// Sidebar label — defaults to the first user message, truncated. Editable later if needed.
    var title: String
    var createdAt: Date
    var updatedAt: Date

    init(title: String, createdAt: Date = Date()) {
        self.id = UUID()
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }
}
