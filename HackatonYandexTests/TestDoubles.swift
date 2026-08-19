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
        let processingMode: SpeechRecognitionProcessingMode
    }

    var result: Result<SpeechToTextModel, Error>?
    private(set) var requests: [Request] = []
    private(set) var cancelCallCount = 0

    func transcribeAudio(
        fileURL: URL,
        language: String,
        conversationId: String,
        processingMode: SpeechRecognitionProcessingMode,
        completion: @escaping (Result<SpeechToTextModel, Error>) -> Void
    ) {
        requests.append(
            Request(
                fileURL: fileURL,
                language: language,
                conversationId: conversationId,
                processingMode: processingMode
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

final class RealtimeAudioCaptureServiceStub: RealtimeAudioCaptureService {
    var startError: Error?
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var isCapturing = false
    private var chunkHandler: ((Data) -> Void)?

    func startCapture(onAudioChunk: @escaping (Data) -> Void) throws {
        startCallCount += 1
        if let startError {
            throw startError
        }
        isCapturing = true
        chunkHandler = onAudioChunk
    }

    func stopCapture() {
        stopCallCount += 1
        isCapturing = false
        chunkHandler = nil
    }

    func emitAudio(_ data: Data) {
        chunkHandler?(data)
    }
}

final class RealtimeSpeechClientSpy: RealtimeSpeechClient {
    var eventHandler: ((RealtimeSpeechEvent) -> Void)?
    var onStart: (() -> Void)?
    var onAudioChunk: (() -> Void)?
    var onStop: (() -> Void)?
    private(set) var configurations: [RealtimeSpeechConfiguration] = []
    private(set) var audioChunks: [Data] = []
    private(set) var stopCallCount = 0
    private(set) var cancelCallCount = 0

    func start(configuration: RealtimeSpeechConfiguration) {
        configurations.append(configuration)
        onStart?()
    }

    func appendAudioChunk(_ data: Data) {
        audioChunks.append(data)
        onAudioChunk?()
    }

    func stop() {
        stopCallCount += 1
        onStop?()
    }

    func cancel() {
        cancelCallCount += 1
    }

    func emit(_ event: RealtimeSpeechEvent) {
        eventHandler?(event)
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
final class ListenViewSpy: ListenView {
    private(set) var models: [ListenViewModel] = []
    private(set) var partialSegments: [RealtimeSpeechSegment] = []
    private(set) var finalSegments: [RealtimeSpeechSegment] = []
    private(set) var clearPartialCallCount = 0
    var onRender: ((ListenViewModel) -> Void)?

    func render(_ viewModel: ListenViewModel) {
        models.append(viewModel)
        onRender?(viewModel)
    }

    func displayPartialSpeech(_ segment: RealtimeSpeechSegment) {
        partialSegments.append(segment)
    }

    func displayFinalSpeech(_ segment: RealtimeSpeechSegment) {
        finalSegments.append(segment)
    }

    func clearPartialSpeech() {
        clearPartialCallCount += 1
    }
}

@MainActor
final class ListenPresenterDelegateSpy: ListenPresenterDelegate {
    struct FinalizedSegment: Equatable {
        let segment: RealtimeSpeechSegment
        let conversationId: String
    }

    private(set) var finalizedSegments: [FinalizedSegment] = []
    private(set) var microphoneActivity: [Bool] = []

    func listenPresenter(
        _ presenter: ListenPresenter,
        didFinalize segment: RealtimeSpeechSegment,
        conversationId: String
    ) {
        finalizedSegments.append(
            FinalizedSegment(
                segment: segment,
                conversationId: conversationId
            )
        )
    }

    func listenPresenter(
        _ presenter: ListenPresenter,
        didChangeMicrophoneActivity isActive: Bool
    ) {
        microphoneActivity.append(isActive)
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
