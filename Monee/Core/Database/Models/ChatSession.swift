//
//  ChatSession.swift
//  FreelanceFinance
//
//  Created by Rio Ferdinand on 30/06/26.
//


import Foundation
import SwiftData

@Model
final class ChatSession {
    var id: UUID
    var userPrompt: String
    var aiResponse: String
    var timestamp: Date
    
    init(userPrompt: String, aiResponse: String, timestamp: Date = Date()) {
        self.id = UUID()
        self.userPrompt = userPrompt
        self.aiResponse = aiResponse
        self.timestamp = timestamp
    }
}