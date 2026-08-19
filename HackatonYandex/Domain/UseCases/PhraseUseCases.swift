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

    func execute(text: String, folderId: String? = nil) async throws -> Phrase {
        let now = Date()
        let phrase = Phrase(
            id: UUID().uuidString,
            folderId: folderId,
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

struct FetchPhraseFoldersUseCase {
    let repository: PhraseRepository

    func execute() async throws -> [PhraseFolder] {
        try await repository.fetchPhraseFolders()
    }
}

struct SavePhraseFolderUseCase {
    let repository: PhraseRepository

    func execute(_ folder: PhraseFolder) async throws {
        try await repository.savePhraseFolder(folder)
    }
}

struct CreatePhraseFolderUseCase {
    let repository: PhraseRepository

    func execute(title: String, sortOrder: Int) async throws -> PhraseFolder {
        let folder = PhraseFolder(id: UUID().uuidString, title: title, sortOrder: sortOrder)
        try await repository.savePhraseFolder(folder)
        return folder
    }
}

struct DeletePhraseFolderUseCase {
    let repository: PhraseRepository

    func execute(id: String) async throws {
        try await repository.deletePhraseFolder(id: id)
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
