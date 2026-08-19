//
//  ConversationPresenterTests.swift
//  HackatonYandexTests
//
//  Created by Rodion Kholodov.
//

import XCTest
@testable import HackatonYandex

@MainActor
final class ConversationPresenterTests: XCTestCase {
    func testProductionContainerUsesBackendFirstSpeechRecognition() {
        let container = AppContainer()

        XCTAssertTrue(container.speechRecognitionService is BackendFirstSpeechRecognitionService)
    }

    func testBackendFirstRecognitionReturnsRemoteResultWithoutLocalFallback() async throws {
        let remote = SpeechRecognitionServiceStub()
        remote.result = .success(
            SpeechToTextModel(text: "С сервера", language: "ru-RU", durationMs: 500, confidence: nil)
        )
        let local = SpeechRecognitionServiceStub()
        let service = BackendFirstSpeechRecognitionService(remoteService: remote, localService: local)
        let completed = expectation(description: "Remote recognition completed")
        var recognizedText: String?

        service.transcribeAudio(
            fileURL: URL(fileURLWithPath: "/tmp/backend-first.wav"),
            language: "ru-RU",
            conversationId: UUID().uuidString,
            processingMode: .allowSystemNetworkFallback
        ) { result in
            recognizedText = try? result.get().text
            completed.fulfill()
        }

        await fulfillment(of: [completed], timeout: 1)
        XCTAssertEqual(recognizedText, "С сервера")
        XCTAssertEqual(remote.requests.count, 1)
        XCTAssertTrue(local.requests.isEmpty)
    }

    func testBackendFirstRecognitionFallsBackToAppleAfterRemoteFailure() async {
        let remote = SpeechRecognitionServiceStub()
        remote.result = .failure(AppError.networkUnavailable)
        let local = SpeechRecognitionServiceStub()
        local.result = .success(
            SpeechToTextModel(text: "Локально", language: "ru-RU", durationMs: 500, confidence: nil)
        )
        let service = BackendFirstSpeechRecognitionService(remoteService: remote, localService: local)
        let completed = expectation(description: "Local fallback completed")
        var recognizedText: String?

        service.transcribeAudio(
            fileURL: URL(fileURLWithPath: "/tmp/backend-fallback.wav"),
            language: "ru-RU",
            conversationId: UUID().uuidString,
            processingMode: .allowSystemNetworkFallback
        ) { result in
            recognizedText = try? result.get().text
            completed.fulfill()
        }

        await fulfillment(of: [completed], timeout: 1)
        XCTAssertEqual(recognizedText, "Локально")
        XCTAssertEqual(remote.requests.count, 1)
        XCTAssertEqual(local.requests.first?.processingMode, .allowSystemNetworkFallback)
    }

    func testBackendFirstRecognitionKeepsLocalOnlyAudioOffBackend() async {
        let remote = SpeechRecognitionServiceStub()
        let local = SpeechRecognitionServiceStub()
        local.result = .success(
            SpeechToTextModel(text: "На устройстве", language: "ru-RU", durationMs: 500, confidence: nil)
        )
        let service = BackendFirstSpeechRecognitionService(remoteService: remote, localService: local)
        let completed = expectation(description: "On-device recognition completed")

        service.transcribeAudio(
            fileURL: URL(fileURLWithPath: "/tmp/local-only.wav"),
            language: "ru-RU",
            conversationId: UUID().uuidString,
            processingMode: .onDeviceOnly
        ) { _ in completed.fulfill() }

        await fulfillment(of: [completed], timeout: 1)
        XCTAssertTrue(remote.requests.isEmpty)
        XCTAssertEqual(local.requests.first?.processingMode, .onDeviceOnly)
    }

    func testSubmittingTextRendersMessageWithoutOpeningLargeDisplay() {
        let context = makeContext()

        context.presenter.didSubmitText("  Нужна помощь  ")

        XCTAssertEqual(context.view.submittedTexts, ["Нужна помощь"])
        XCTAssertTrue(context.view.largeTexts.isEmpty)
    }

    func testSpeakRequestUsesTextToSpeechService() {
        let context = makeContext()

        context.presenter.didRequestSpeak("  Повторите, пожалуйста  ")

        XCTAssertEqual(context.textToSpeechService.spokenTexts, ["Повторите, пожалуйста"])
    }

    func testResumeConversationRestoresModeAndMessages() async {
        let repository = ConversationRepositoryStub()
        let conversation = Conversation(
            id: "conversation-id",
            title: "Прием у врача",
            mode: .listen,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20),
            isPinned: false,
            syncState: .localOnly
        )
        let message = ConversationMessage(
            id: "message-id",
            conversationId: conversation.id,
            text: "Что вас беспокоит?",
            source: .externalSpeech,
            speakerId: nil,
            speakerLabel: "Говорящий 1",
            isFinal: true,
            createdAt: Date(timeIntervalSince1970: 15),
            audioDurationMs: nil,
            syncState: .localOnly
        )
        repository.conversations = [conversation]
        repository.messages = [message]

        let context = makeContext(repository: repository)
        let restored = expectation(description: "Conversation restored")
        context.view.onDisplayMessages = { restored.fulfill() }

        context.presenter.didRequestResumeConversation(id: conversation.id)
        await fulfillment(of: [restored], timeout: 1)

        XCTAssertEqual(context.view.renderedModels.last?.mode, .listen)
        XCTAssertEqual(context.view.displayedMessages, [message])
        XCTAssertEqual(context.view.clearCallCount, 1)
    }

    func testVoiceRecordingSendsCurrentConversationAndRendersTranscript() async throws {
        var settings = AppSettings.defaultValue
        settings.privacyMode = .standard
        settings.autoStartMicrophone = false
        settings.transcriptFontScale = 1.25

        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("presenter-recording.wav")
        let context = makeContext(settings: settings)
        context.audioRecordingService.recordingURL = audioURL
        context.speechRecognitionService.result = .success(
            SpeechToTextModel(
                text: "  Чем я могу помочь?  ",
                language: "ru-RU",
                durationMs: 1_250,
                confidence: 0.92
            )
        )

        await loadSettings(in: context)

        let recordingStarted = expectation(description: "Recording started")
        context.view.onRender = { viewModel in
            if viewModel.voiceInputState == .recording {
                recordingStarted.fulfill()
            }
        }
        XCTAssertTrue(context.presenter.didRequestStartVoiceRecording())
        await fulfillment(of: [recordingStarted], timeout: 1)
        context.view.onRender = nil

        let speechRendered = expectation(description: "Speech rendered")
        context.view.onRecognizedSpeech = { speechRendered.fulfill() }
        context.presenter.didRequestStopVoiceRecording()
        await fulfillment(of: [speechRendered], timeout: 1)

        XCTAssertEqual(context.audioRecordingService.startCallCount, 1)
        XCTAssertEqual(context.audioRecordingService.stopCallCount, 1)
        XCTAssertEqual(context.audioRecordingService.discardedURLs, [audioURL])
        XCTAssertEqual(context.view.recognizedTexts, ["Чем я могу помочь?"])
        let request = try XCTUnwrap(context.speechRecognitionService.requests.first)
        XCTAssertEqual(request.fileURL, audioURL)
        XCTAssertEqual(request.language, "ru-RU")
        XCTAssertEqual(request.processingMode, .allowSystemNetworkFallback)
        XCTAssertNotNil(UUID(uuidString: request.conversationId))
        XCTAssertTrue(
            context.view.renderedModels.contains { $0.voiceInputState == .recognizing }
        )
        XCTAssertEqual(context.view.renderedModels.last?.voiceInputState, .idle)
    }

    func testVoiceInputStopsAtConfiguredLimit() async {
        var settings = AppSettings.defaultValue
        settings.privacyMode = .standard
        settings.autoStartMicrophone = false
        settings.transcriptFontScale = 1.25

        let context = makeContext(
            settings: settings,
            maximumRecordingDuration: 0.01
        )
        context.audioRecordingService.recordingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("presenter-auto-limit.wav")
        context.speechRecognitionService.result = .success(
            SpeechToTextModel(
                text: "Автоматическая остановка",
                language: "ru-RU",
                durationMs: 30_000,
                confidence: nil
            )
        )

        await loadSettings(in: context)

        let speechRendered = expectation(description: "Recording limit speech rendered")
        context.view.onRecognizedSpeech = { speechRendered.fulfill() }
        XCTAssertTrue(context.presenter.didRequestStartVoiceRecording())
        await fulfillment(of: [speechRendered], timeout: 1)

        XCTAssertEqual(context.audioRecordingService.startCallCount, 1)
        XCTAssertEqual(context.audioRecordingService.stopCallCount, 1)
        XCTAssertEqual(context.speechRecognitionService.requests.count, 1)
        XCTAssertEqual(context.view.renderedModels.last?.voiceInputState, .idle)
    }

    func testViewLoadDoesNotStartPushToTalkRecordingAutomatically() async {
        var settings = AppSettings.defaultValue
        settings.privacyMode = .standard
        settings.autoStartMicrophone = true
        settings.transcriptFontScale = 1.25

        let context = makeContext(settings: settings)

        await loadSettings(in: context)

        XCTAssertEqual(context.audioRecordingService.startCallCount, 0)
        XCTAssertEqual(context.speechRecognitionService.requests.count, 0)
        XCTAssertEqual(context.view.renderedModels.last?.voiceInputState, .idle)
    }

    func testLocalOnlyModeUsesOnDeviceRecognitionInsteadOfBlockingRecording() async throws {
        var settings = AppSettings.defaultValue
        settings.privacyMode = .localOnly
        settings.autoStartMicrophone = false
        settings.transcriptFontScale = 1.25

        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("presenter-local-recording.wav")
        let context = makeContext(settings: settings)
        context.audioRecordingService.recordingURL = audioURL
        context.speechRecognitionService.result = .success(
            SpeechToTextModel(
                text: "Локальное распознавание",
                language: "ru-RU",
                durationMs: 900,
                confidence: 0.9
            )
        )

        await loadSettings(in: context)

        let recordingStarted = expectation(description: "Local recording started")
        context.view.onRender = { viewModel in
            if viewModel.voiceInputState == .recording {
                recordingStarted.fulfill()
            }
        }
        XCTAssertTrue(context.presenter.didRequestStartVoiceRecording())
        await fulfillment(of: [recordingStarted], timeout: 1)
        context.view.onRender = nil

        let speechRendered = expectation(description: "Local speech rendered")
        context.view.onRecognizedSpeech = { speechRendered.fulfill() }
        context.presenter.didRequestStopVoiceRecording()
        await fulfillment(of: [speechRendered], timeout: 1)

        let request = try XCTUnwrap(context.speechRecognitionService.requests.first)
        XCTAssertEqual(request.processingMode, .onDeviceOnly)
        XCTAssertEqual(context.view.recognizedTexts, ["Локальное распознавание"])
        XCTAssertTrue(context.view.errors.isEmpty)
    }

    func testNetworkRecognitionErrorExplainsOfflineFallback() async {
        var settings = AppSettings.defaultValue
        settings.privacyMode = .standard
        settings.autoStartMicrophone = false
        settings.transcriptFontScale = 1.25

        let context = makeContext(settings: settings)
        context.audioRecordingService.recordingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("presenter-network-error.wav")
        context.speechRecognitionService.result = .failure(AppError.networkUnavailable)

        await loadSettings(in: context)

        let recordingStarted = expectation(description: "Recording started")
        context.view.onRender = { viewModel in
            if viewModel.voiceInputState == .recording {
                recordingStarted.fulfill()
            }
        }
        context.presenter.didRequestStartVoiceRecording()
        await fulfillment(of: [recordingStarted], timeout: 1)
        context.view.onRender = nil

        let errorRendered = expectation(description: "Network error rendered")
        context.view.onError = { errorRendered.fulfill() }
        context.presenter.didRequestStopVoiceRecording()
        await fulfillment(of: [errorRendered], timeout: 1)

        XCTAssertEqual(
            context.view.errors.last,
            "Для выбранного языка сейчас нужен интернет. Печатный ввод и готовые фразы продолжают работать."
        )
        XCTAssertEqual(context.view.renderedModels.last?.voiceInputState, .idle)
    }

    func testStartingNewConversationCancelsRecognitionAndDeletesTemporaryAudio() async {
        var settings = AppSettings.defaultValue
        settings.privacyMode = .standard
        settings.autoStartMicrophone = false
        settings.transcriptFontScale = 1.25

        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("presenter-cancelled-transcription.wav")
        let context = makeContext(settings: settings)
        context.audioRecordingService.recordingURL = audioURL

        await loadSettings(in: context)

        let recordingStarted = expectation(description: "Recording started")
        context.view.onRender = { viewModel in
            if viewModel.voiceInputState == .recording {
                recordingStarted.fulfill()
            }
        }
        context.presenter.didRequestStartVoiceRecording()
        await fulfillment(of: [recordingStarted], timeout: 1)
        context.view.onRender = nil

        context.presenter.didRequestStopVoiceRecording()
        XCTAssertEqual(context.view.renderedModels.last?.voiceInputState, .recognizing)

        context.presenter.didRequestNewConversation()

        XCTAssertEqual(context.speechRecognitionService.cancelCallCount, 1)
        XCTAssertEqual(context.audioRecordingService.discardedURLs, [audioURL])
        XCTAssertEqual(context.view.renderedModels.last?.voiceInputState, .idle)
        XCTAssertEqual(context.view.clearCallCount, 1)
    }

    private func makeContext(
        repository: ConversationRepositoryStub = ConversationRepositoryStub(),
        settings: AppSettings = .defaultValue,
        maximumRecordingDuration: TimeInterval = 30
    ) -> (
        presenter: ConversationPresenter,
        view: ConversationViewSpy,
        textToSpeechService: TextToSpeechServiceSpy,
        audioRecordingService: AudioRecordingServiceStub,
        speechRecognitionService: SpeechRecognitionServiceStub
    ) {
        let view = ConversationViewSpy()
        let settingsRepository = SettingsRepositoryStub(settings: settings)
        let textToSpeechService = TextToSpeechServiceSpy()
        let audioRecordingService = AudioRecordingServiceStub()
        let speechRecognitionService = SpeechRecognitionServiceStub()
        let presenter = ConversationPresenter(
            view: view,
            microphonePermissionService: MicrophonePermissionServiceStub(),
            audioRecordingService: audioRecordingService,
            speechRecognitionService: speechRecognitionService,
            textToSpeechService: textToSpeechService,
            fetchSettingsUseCase: FetchSettingsUseCase(repository: settingsRepository),
            fetchConversationUseCase: FetchConversationUseCase(repository: repository),
            fetchConversationMessagesUseCase: FetchConversationMessagesUseCase(repository: repository),
            saveConversationUseCase: SaveConversationUseCase(repository: repository),
            addConversationMessageUseCase: AddConversationMessageUseCase(repository: repository),
            maximumRecordingDuration: maximumRecordingDuration
        )
        return (
            presenter,
            view,
            textToSpeechService,
            audioRecordingService,
            speechRecognitionService
        )
    }

    private func loadSettings(
        in context: (
            presenter: ConversationPresenter,
            view: ConversationViewSpy,
            textToSpeechService: TextToSpeechServiceSpy,
            audioRecordingService: AudioRecordingServiceStub,
            speechRecognitionService: SpeechRecognitionServiceStub
        )
    ) async {
        let settingsLoaded = expectation(description: "Settings loaded")
        context.view.onRender = { viewModel in
            if viewModel.transcriptFontScale == 1.25 {
                settingsLoaded.fulfill()
            }
        }
        context.presenter.viewDidLoad()
        await fulfillment(of: [settingsLoaded], timeout: 1)
        context.view.onRender = nil
    }
}
