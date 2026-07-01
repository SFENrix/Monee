import Foundation
import SwiftData
import SwiftUI

@MainActor
class AIChatViewModel: ObservableObject {
    
    // The protocol ensures we are decoupled from the specific AI implementation
    private let aiAdapter: AIAdapterProtocol
    
    // UI State
    @Published var isThinking: Bool = false
    @Published var errorMessage: String? = nil
    
    init(aiAdapter: AIAdapterProtocol = AppleIntelligenceAdapter()) {
        self.aiAdapter = aiAdapter
    }
    
    /// Processes the user's message, fetches RAG context, and saves the result.
    func sendMessage(_ text: String, modelContext: ModelContext) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        isThinking = true
        errorMessage = nil
        
        do {
            // 1. Context Gathering (RAG)
            let transactionContext = try fetchAndSerializeTransactions(using: modelContext)
            
            // 2. Execution (Calling the Apple Intelligence Adapter)
            let response = try await aiAdapter.generateAdvice(
                systemContext: transactionContext,
                userPrompt: text
            )
            
            // 3. Persistence (Saving the transcript)
            let newSession = ChatSession(userPrompt: text, aiResponse: response)
            modelContext.insert(newSession)
            
            // SwiftData auto-saves, but we can explicitly save if needed
            try modelContext.save()
            
        } catch {
            // Graceful on-device error handling
            self.errorMessage = "Failed to process request: \(error.localizedDescription)"
        }
        
        isThinking = false
    }
    
    /// Fetches the user's recent transactions and converts them to a lightweight string for the AI
    private func fetchAndSerializeTransactions(using context: ModelContext) throws -> String {
        // Fetch all transactions (In a full production app, you might limit this to the last 30 days)
        let descriptor = FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        let transactions = try context.fetch(descriptor)
        
        guard !transactions.isEmpty else {
            return "No recent transactions found. The user's financial slate is clean."
        }
        
        // Serialize the data into a clean, readable format for the LLM
        let serializedData = transactions.prefix(50).map { txn in
            "- \(txn.date.formatted(date: .abbreviated, time: .omitted)): \(txn.title) ($\(String(format: "%.2f", txn.amount)))"
        }.joined(separator: "\n")
        
        return serializedData
    }
}
