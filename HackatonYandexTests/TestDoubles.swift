//
//  TestDoubles.swift
//  HackatonYandexTests
//
//  Created by Rodion Kholodov.
//

import Foundation
@testable import HackatonYandex

final class ConversationRepositoryStub: ConversationRepository {
    var conversations: [Conversation] = []
    var messages: [ConversationMessage] = []

    func fetchConversations() async throws -> [Conversation] {
        conversations
    }

    func fetchConversation(id: String) async throws -> Conversation? {
        conversations.first { $0.id == id }
    }

    func fetchMessages(conversationId: String) async throws -> [ConversationMessage] {
        messages.filter { $0.conversationId == conversationId }
    }

    func saveConversation(_ conversation: Conversation) async throws {
        conversations.removeAll { $0.id == conversation.id }
        conversations.append(conversation)
    }

    func saveMessage(_ message: ConversationMessage) async throws {
        messages.removeAll { $0.id == message.id }
        messages.append(message)
    }

    func deleteConversation(id: String) async throws {
        conversations.removeAll { $0.id == id }
        messages.removeAll { $0.conversationId == id }
    }
}

final class SettingsRepositoryStub: SettingsRepository {
    var settings: AppSettings

    init(settings: AppSettings = .defaultValue) {
        self.settings = settings
    }

    func fetchSettings() async throws -> AppSettings {
        settings
    }

    func saveSettings(_ settings: AppSettings) async throws {
        self.settings = settings
    }
}

final class MicrophonePermissionServiceStub: MicrophonePermissionService {
    var isGranted = true

    var authorizationStatus: MicrophonePermissionStatus {
        isGranted ? .granted : .denied
    }

    func requestPermission(completion: @escaping (Bool) -> Void) {
        completion(isGranted)
    }
}

final class AudioRecordingServiceStub: AudioRecordingService {
    var recordingURL: URL?
    var startError: Error?
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var discardedURLs: [URL] = []

    func startRecording() throws {
        startCallCount += 1
        if let startError {
            throw startError
        }
    }

    func stopRecording() -> URL? {
        stopCallCount += 1
        return recordingURL
    }

    func discardRecording(at fileURL: URL) {
        discardedURLs.append(fileURL)
    }
}

final class SpeechRecognitionServiceStub: SpeechRecognitionService {
    struct Request: Equatable {
        let fileURL: URL
        let language: String
        let conversationId: String
    }

    var result: Result<SpeechToTextModel, Error>?
    private(set) var requests: [Request] = []
    private(set) var cancelCallCount = 0

    func transcribeAudio(
        fileURL: URL,
        language: String,
        conversationId: String,
        completion: @escaping (Result<SpeechToTextModel, Error>) -> Void
    ) {
        requests.append(
            Request(
                fileURL: fileURL,
                language: language,
                conversationId: conversationId
            )
        )
        if let result {
            completion(result)
        }
    }

    func cancelTranscription() {
        cancelCallCount += 1
    }
}

final class TextToSpeechServiceSpy: TextToSpeechService {
    private(set) var spokenTexts: [String] = []
    private(set) var stopCallCount = 0
    private(set) var appliedSettings: [AppSettings] = []
    var isSpeaking = false

    func speak(_ text: String) {
        spokenTexts.append(text)
        isSpeaking = true
    }

    func stop() {
        stopCallCount += 1
        isSpeaking = false
    }

    func availableVoices(language: String) -> [TextToSpeechVoice] {
        []
    }

    func apply(settings: AppSettings) {
        appliedSettings.append(settings)
    }
}

@MainActor
final class ConversationViewSpy: ConversationView {
    private(set) var renderedModels: [ConversationViewModel] = []
    private(set) var submittedTexts: [String] = []
    private(set) var largeTexts: [String] = []
    private(set) var displayedMessages: [ConversationMessage] = []
    private(set) var clearCallCount = 0
    private(set) var errors: [String] = []
    private(set) var recognizedTexts: [String] = []
    var onDisplayMessages: (() -> Void)?
    var onRecognizedSpeech: (() -> Void)?
    var onError: (() -> Void)?
    var onRender: ((ConversationViewModel) -> Void)?

    func render(_ viewModel: ConversationViewModel) {
        renderedModels.append(viewModel)
        onRender?(viewModel)
    }

    func displayStartTypingHint() {}
    func displayMicrophoneHint() {}
    func hideConversationHints() {}

    func displayLargeText(_ text: String) {
        largeTexts.append(text)
    }

    func dismissLargeTextDisplay() {}
    func displayRecognizedSpeech(_ text: String) {
        recognizedTexts.append(text)
        onRecognizedSpeech?()
    }

    func displayConversationError(_ message: String) {
        errors.append(message)
        onError?()
    }

    func displaySubmittedText(_ text: String) {
        submittedTexts.append(text)
    }

    func clearConversationMessages() {
        clearCallCount += 1
    }

    func displayConversationMessages(_ messages: [ConversationMessage]) {
        displayedMessages = messages
        onDisplayMessages?()
    }
}

@MainActor
final class LargeTextDisplayViewSpy: LargeTextDisplayView {
    private(set) var models: [LargeTextDisplayViewModel] = []
    private(set) var rotations: [Bool] = []
    private(set) var dismissCallCount = 0

    func render(_ viewModel: LargeTextDisplayViewModel) {
        models.append(viewModel)
    }

    func setDisplayRotated(_ isRotated: Bool) {
        rotations.append(isRotated)
    }

    func dismissLargeTextDisplay() {
        dismissCallCount += 1
    }
}
