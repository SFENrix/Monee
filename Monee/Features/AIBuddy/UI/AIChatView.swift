//
//  AIChatView.swift
//  FreelanceFinance
//
//  Merged 03/07/26 — combines the design team's visual layer (gradient background,
//  mascot empty state, ChatBubble/ChatInputBar) with the existing functional layer
//  (AIChatViewModel, SwiftData persistence, chat history, income estimate onboarding).
//
//  ASSUMPTION: MessageText, ChatBubble, ChatInputBar, and PufferfishMascot are defined
//  elsewhere in the project already (delivered separately by the design team). This file
//  does NOT redeclare them.
//
//  Fixed vs. previous version: removed a duplicate `.sheet(showingHistory)` and a
//  duplicate `.task { }` block that were left in from a merge.
//
//  Updated 06/07/26 — restyled to match the new mockup: onboarding-style peach/mint
//  gradient background, updated empty-state header copy/typography, and a soft white
//  circular history button instead of the solid accent-color one.
//

import SwiftUI
import SwiftData

struct AIChatView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = AIChatViewModel()
    @Query(sort: \ChatSession.updatedAt, order: .reverse) private var sessions: [ChatSession]

    var userFirstName: String { UserProfile.name ?? "there" }

    @State private var draft: String = ""
    @State private var showingHistory = false

    var body: some View {
        ZStack {
            backgroundGradient

            VStack(spacing: 0) {
                if let error = viewModel.errorMessage {
                    ErrorBanner(message: error)
                        .padding(.top, 60)
                }

                if viewModel.messages.isEmpty {
                    emptyState
                } else {
                    conversationList
                }

                ChatInputBar(
                    text: $draft,
                    onSend: send,
                    onMicTap: startDictation
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .disabled(viewModel.isThinking)
            }
        }
        .dismissKeyboardOnTap()
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 10) {
                if !viewModel.messages.isEmpty {
                    circularButton(systemImage: "plus") {
                        viewModel.startNewSession()
                    }
                }
                circularButton(systemImage: "clock") {
                    showingHistory = true
                }
            }
            .padding(.trailing, 20)
            .padding(.top, 8)
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
    }

    // MARK: - Button

    /// Soft white circular button (history / new session), matching the
    /// rounded, low-contrast icon buttons used across onboarding.
    private func circularButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(red: 0.18, green: 0.14, blue: 0.22))
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.white.opacity(0.85)))
                .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 60)

            Image("buntel")
                .resizable()
                .scaledToFit()
                .frame(width: 190, height: 190)
            
            VStack(spacing: 8) {
                Text("Hi \(userFirstName)!")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.16, green: 0.35, blue: 0.34))

                Text("Thinking about buying something?")
                    .font(.system(size: 17))
                    .foregroundStyle(Color(red: 0.18, green: 0.14, blue: 0.22))
            }
            .padding(.top, 8)

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 40)
    }

    // MARK: - Conversation

    /// Bridges the real SwiftData-backed ChatMessage into the design layer's lightweight
    /// MessageText, so ChatBubble stays decoupled from persistence entirely.
    private var displayMessages: [MessageText] {
        viewModel.messages.map { message in
            MessageText(
                
                sender: message.role == .user ? .user : .assistant,
                text: message.content
            )
        }
    }

    private var conversationList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(displayMessages) { message in
                        ChatBubble(message: message)
                            .id(message.id)
                    }
                    if viewModel.isThinking {
                        ThinkingBubble()
                            .id("thinking")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 64)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.messages.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: viewModel.isThinking) { _, isThinking in
                guard isThinking else { return }
                withAnimation { proxy.scrollTo("thinking", anchor: .bottom) }
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let last = displayMessages.last else { return }
        withAnimation {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }

    // MARK: - Background

    /// Onboarding-style peach/mint gradient, matching Buntel's visual language
    /// across the rest of the app instead of the flat blue-tinted background.
    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.97, green: 0.90, blue: 0.82),
                Color(red: 0.94, green: 0.85, blue: 0.80),
                Color(red: 0.85, green: 0.92, blue: 0.87)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // MARK: - Actions

    private func send() {
        let text = draft
        draft = ""
        Task {
            await viewModel.sendMessage(text, modelContext: modelContext)
        }
    }

    private func startDictation() {
        // TODO: voice input isn't in the 7-day POC scope (see freelancer_finance_poc_v3.md).
        // Leave as a no-op for now, or hide the mic button until this is greenlit.
    }
}

// MARK: - Thinking Indicator (functional placeholder — restyle to match ChatBubble later)

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

// MARK: - Error Banner (functional placeholder)

private struct ErrorBanner: View {
    let message: String
    var body: some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(.white)
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(Color.red)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 16)
    }
}

// MARK: - History List (real data — replaces the design mock's ChatHistoryPlaceholder)

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
        .environment(AppContainer.shared)
}
