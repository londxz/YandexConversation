//
//  CoreDataRepositoriesTests.swift
//  HackatonYandexTests
//
//  Created by Rodion Kholodov.
//

import XCTest
@testable import HackatonYandex

final class CoreDataRepositoriesTests: XCTestCase {
    func testConversationAndMessageRoundTrip() async throws {
        let repository = CoreDataConversationRepository(coreDataStack: CoreDataStack(inMemory: true))
        let conversation = Conversation(
            id: "conversation-id",
            title: "Тестовый разговор",
            mode: .talk,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20),
            isPinned: false,
            syncState: .localOnly
        )
        let message = ConversationMessage(
            id: "message-id",
            conversationId: conversation.id,
            text: "Здравствуйте",
            source: .userTyped,
            speakerId: nil,
            speakerLabel: nil,
            isFinal: true,
            createdAt: Date(timeIntervalSince1970: 15),
            audioDurationMs: nil,
            syncState: .localOnly
        )

        try await repository.saveConversation(conversation)
        try await repository.saveMessage(message)

        let fetchedConversation = try await repository.fetchConversation(id: conversation.id)
        let fetchedMessages = try await repository.fetchMessages(conversationId: conversation.id)
        XCTAssertEqual(fetchedConversation, conversation)
        XCTAssertEqual(fetchedMessages, [message])

        try await repository.deleteConversation(id: conversation.id)
        let deletedConversation = try await repository.fetchConversation(id: conversation.id)
        let deletedMessages = try await repository.fetchMessages(conversationId: conversation.id)
        XCTAssertNil(deletedConversation)
        XCTAssertTrue(deletedMessages.isEmpty)
    }

    func testDeletingFolderKeepsPhraseAndRemovesFolderAssignment() async throws {
        let repository = CoreDataPhraseRepository(coreDataStack: CoreDataStack(inMemory: true))
        let folder = PhraseFolder(id: "doctor", title: "Врач", sortOrder: 0)
        let phrase = Phrase(
            id: "phrase-id",
            folderId: folder.id,
            text: "Пожалуйста, напишите назначение",
            category: "custom",
            isFavorite: false,
            sortOrder: 0,
            usageCount: 0,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 10),
            syncState: .localOnly
        )

        try await repository.savePhraseFolder(folder)
        try await repository.savePhrase(phrase)
        try await repository.deletePhraseFolder(id: folder.id)

        let folders = try await repository.fetchPhraseFolders()
        let phrases = try await repository.fetchPhrases()
        XCTAssertTrue(folders.isEmpty)
        let storedPhrase = try XCTUnwrap(phrases.first { $0.id == phrase.id })
        XCTAssertNil(storedPhrase.folderId)
        XCTAssertEqual(storedPhrase.text, phrase.text)
    }
}
