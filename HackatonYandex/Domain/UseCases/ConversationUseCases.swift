//
//  ConversationUseCases.swift
//  HackatonYandex
//
//  Created by Rodion Kholodov.
//

import Foundation

struct FetchConversationHistoryUseCase {
    let repository: ConversationRepository

    func execute() async throws -> [Conversation] {
        try await repository.fetchConversations()
    }
}

struct FetchConversationMessagesUseCase {
    let repository: ConversationRepository

    func execute(conversationId: String) async throws -> [ConversationMessage] {
        try await repository.fetchMessages(conversationId: conversationId)
    }
}

struct FetchConversationUseCase {
    let repository: ConversationRepository

    func execute(id: String) async throws -> Conversation? {
        try await repository.fetchConversation(id: id)
    }
}

struct SaveConversationUseCase {
    let repository: ConversationRepository

    func execute(_ conversation: Conversation) async throws {
        try await repository.saveConversation(conversation)
    }
}

struct AddConversationMessageUseCase {
    let repository: ConversationRepository

    func execute(_ message: ConversationMessage) async throws {
        try await repository.saveMessage(message)
    }
}

struct DeleteConversationUseCase {
    let repository: ConversationRepository

    func execute(conversationId: String) async throws {
        try await repository.deleteConversation(id: conversationId)
    }
}
