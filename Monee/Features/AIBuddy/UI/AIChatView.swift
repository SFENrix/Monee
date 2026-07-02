//
//  AIChatView.swift
//  FreelanceFinance
//
//  Created by Rio Ferdinand on 02/07/26.
//
//  Chat UI for the AI Buddy feature. Kept single-file for now (mirrors the pattern used in
//  ContentView.swift) — split into smaller files later if this grows.
//

import SwiftUI
import SwiftData

struct AIChatView: View {
    @Environment(\.modelContext) private var modelContext
        @Environment(AppContainer.self) private var appContainer
        @StateObject private var viewModel = AIChatViewModel()
        @State private var draft: String = ""
        @State private var showingHistory = false
        @State private var showingIncomeEstimate = false

    @Query(sort: \ChatSession.updatedAt, order: .reverse) private var sessions: [ChatSession]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let error = viewModel.errorMessage {
                    ErrorBanner(message: error)
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            if viewModel.messages.isEmpty {
                                EmptyStateView()
                                    .padding(.top, 60)
                            }
                            ForEach(viewModel.messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }
                            if viewModel.isThinking {
                                ThinkingBubble()
                            }
                        }
                        .padding()
                    }
                    .onChange(of: viewModel.messages.count) { _, _ in
                        scrollToBottom(proxy)
                    }
                }

                InputBar(text: $draft, isSending: viewModel.isThinking, onSend: send)
            }
            .navigationTitle(viewModel.currentSessionTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showingHistory = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        viewModel.startNewSession()
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
            .sheet(isPresented: $showingHistory) {
                ChatHistoryListView(sessions: sessions) { session in
                    viewModel.loadSession(session, modelContext: modelContext)
                    showingHistory = false
                }
            }
            .task {
                viewModel.bootstrap(modelContext: modelContext)
            }
        }.sheet(isPresented: $showingHistory) {
            ChatHistoryListView(sessions: sessions) { session in
                viewModel.loadSession(session, modelContext: modelContext)
                showingHistory = false
            }
        }
        .sheet(isPresented: $showingIncomeEstimate) {
            IncomeEstimateSheet()
        }
        .task {
            viewModel.bootstrap(modelContext: modelContext)
            if !appContainer.isUserOnboarded && !UserFinancialProfile.hasEstimate {
                showingIncomeEstimate = true
            }
        }
    
    }

    private func send() {
        let text = draft
        draft = ""
        Task {
            await viewModel.sendMessage(text, modelContext: modelContext)
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let last = viewModel.messages.last else { return }
        withAnimation {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }
}

// MARK: - Message Bubble

private struct MessageBubble: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }
            Text(message.content)
                .padding(12)
                .background(isUser ? Color.accentColor : Color(.secondarySystemBackground))
                .foregroundStyle(isUser ? Color.white : Color.primary)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            if !isUser { Spacer(minLength: 40) }
        }
    }
}

private struct ThinkingBubble: View {
    var body: some View {
        HStack {
            ProgressView()
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            Spacer(minLength: 40)
        }
    }
}

private struct ErrorBanner: View {
    let message: String
    var body: some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(.white)
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(Color.red)
    }
}

private struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Ask AI Buddy anything about your spending")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Input Bar

private struct InputBar: View {
    @Binding var text: String
    let isSending: Bool
    let onSend: () -> Void

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    var body: some View {
        HStack(spacing: 8) {
            TextField("Ask your AI Buddy…", text: $text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)

            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title)
            }
            .disabled(!canSend)
        }
        .padding()
        .background(.bar)
    }
}

// MARK: - History

private struct ChatHistoryListView: View {
    let sessions: [ChatSession]
    let onSelect: (ChatSession) -> Void

    var body: some View {
        NavigationStack {
            List(sessions) { session in
                Button {
                    onSelect(session)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.title)
                            .font(.body)
                            .foregroundStyle(.primary)
                        Text(session.updatedAt, format: .dateTime.day().month().hour().minute())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .overlay {
                if sessions.isEmpty {
                    ContentUnavailableView(
                        "No Chats Yet",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("Start a conversation and it'll show up here.")
                    )
                }
            }
            .navigationTitle("Past Chats")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    AIChatView()
        .modelContainer(SwiftDataService.makePreviewContainer(seeded: true))
}
