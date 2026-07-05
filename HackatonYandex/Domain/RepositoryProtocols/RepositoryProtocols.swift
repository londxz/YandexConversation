//
//  RepositoryProtocols.swift
//  HackatonYandex
//
//  Created by Rodion Kholodov.
//

import Foundation

protocol ConversationRepository {
    func fetchConversations() async throws -> [Conversation]
    func fetchMessages(conversationId: String) async throws -> [ConversationMessage]
    func saveConversation(_ conversation: Conversation) async throws
    func saveMessage(_ message: ConversationMessage) async throws
    func deleteConversation(id: String) async throws
}

protocol PhraseRepository {
    func fetchPhrases() async throws -> [Phrase]
    func savePhrase(_ phrase: Phrase) async throws
    func deletePhrase(id: String) async throws
}

protocol SettingsRepository {
    func fetchSettings() async throws -> AppSettings
    func saveSettings(_ settings: AppSettings) async throws
}

protocol SpeechRecognitionRepository {
    func transcribeAudio(fileURL: URL) async throws -> SpeechToTextModel
}
