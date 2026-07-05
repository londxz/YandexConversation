//
//  PhraseUseCases.swift
//  HackatonYandex
//
//  Created by Rodion Kholodov.
//

import Foundation

struct FetchPhrasesUseCase {
    let repository: PhraseRepository

    func execute() async throws -> [Phrase] {
        try await repository.fetchPhrases()
    }
}

struct CreatePhraseUseCase {
    let repository: PhraseRepository

    func execute(text: String) async throws -> Phrase {
        let now = Date()
        let phrase = Phrase(
            id: UUID().uuidString,
            folderId: nil,
            text: text,
            category: "custom",
            isFavorite: false,
            sortOrder: Int(now.timeIntervalSince1970),
            usageCount: 0,
            createdAt: now,
            updatedAt: now,
            syncState: .localOnly
        )

        try await repository.savePhrase(phrase)
        return phrase
    }
}

struct SavePhraseUseCase {
    let repository: PhraseRepository

    func execute(_ phrase: Phrase) async throws {
        try await repository.savePhrase(phrase)
    }
}

struct DeletePhraseUseCase {
    let repository: PhraseRepository

    func execute(id: String) async throws {
        try await repository.deletePhrase(id: id)
    }
}

struct RecordPhraseUsageUseCase {
    let repository: PhraseRepository

    func execute(_ phrase: Phrase) async throws {
        var updatedPhrase = phrase
        updatedPhrase.usageCount += 1
        updatedPhrase.updatedAt = Date()
        try await repository.savePhrase(updatedPhrase)
    }
}
