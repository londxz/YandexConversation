//
//  DomainModels.swift
//  HackatonYandex
//
//  Created by Rodion Kholodov.
//

import Foundation

enum SyncState: String, Codable, Equatable {
    case localOnly
    case pendingUpload
    case synced
    case failed
}

struct Conversation: Codable, Equatable, Identifiable {
    enum Mode: String, Codable {
        case talk
        case listen
    }

    let id: String
    var title: String
    var mode: Mode
    var createdAt: Date
    var updatedAt: Date
    var isPinned: Bool
    var syncState: SyncState
}

struct ConversationMessage: Codable, Equatable, Identifiable {
    enum Source: String, Codable {
        case userTyped
        case userVoice
        case externalSpeech
        case quickPhrase
        case system
    }

    let id: String
    let conversationId: String
    var text: String
    var source: Source
    var speakerId: String?
    var speakerLabel: String?
    var isFinal: Bool
    var createdAt: Date
    var audioDurationMs: Int?
    var syncState: SyncState
}

struct Speaker: Codable, Equatable, Identifiable {
    let id: String
    let conversationId: String
    var label: String
    var colorToken: String
}

struct Phrase: Codable, Equatable, Identifiable {
    let id: String
    var folderId: String?
    var text: String
    var category: String?
    var isFavorite: Bool
    var sortOrder: Int
    var usageCount: Int
    var createdAt: Date
    var updatedAt: Date
    var syncState: SyncState

    static let starterPhrases: [Phrase] = [
        Phrase(
            id: "starter-repeat",
            folderId: nil,
            text: "Я не слышу. Повторите, пожалуйста, что вы сказали.",
            category: "basic",
            isFavorite: true,
            sortOrder: 0,
            usageCount: 0,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            syncState: .localOnly
        ),
        Phrase(
            id: "starter-write",
            folderId: nil,
            text: "Напишите, пожалуйста.",
            category: "basic",
            isFavorite: false,
            sortOrder: 1,
            usageCount: 0,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            syncState: .localOnly
        ),
        Phrase(
            id: "starter-slower",
            folderId: nil,
            text: "Говорите медленнее и разборчивее, пожалуйста.",
            category: "basic",
            isFavorite: false,
            sortOrder: 2,
            usageCount: 0,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            syncState: .localOnly
        )
    ]
}

struct PhraseFolder: Codable, Equatable, Identifiable {
    let id: String
    var title: String
    var sortOrder: Int
}

struct AppSettings: Codable, Equatable {
    enum PrivacyMode: String, Codable {
        case standard
        case localOnly
    }

    var recognitionLanguage: String
    var ttsLanguage: String
    var ttsVoiceIdentifier: String?
    var speechRate: Float
    var transcriptFontScale: Float
    var autoStartMicrophone: Bool
    var saveConversationsByDefault: Bool
    var syncEnabled: Bool
    var privacyMode: PrivacyMode

    static let defaultValue = AppSettings(
        recognitionLanguage: "ru-RU",
        ttsLanguage: "ru-RU",
        ttsVoiceIdentifier: nil,
        speechRate: 0.5,
        transcriptFontScale: 1.0,
        autoStartMicrophone: true,
        saveConversationsByDefault: true,
        syncEnabled: false,
        privacyMode: .localOnly
    )
}
