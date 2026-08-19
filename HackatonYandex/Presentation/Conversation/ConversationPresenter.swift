//
//  ConversationPresenter.swift
//  HackatonYandex
//
//  Created by Rodion Kholodov.
//

import Foundation

enum ConversationMode {
    case talk
    case listen

    init?(segmentIndex: Int) {
        switch segmentIndex {
        case 0:
            self = .talk
        case 1:
            self = .listen
        default:
            return nil
        }
    }

    var segmentIndex: Int {
        switch self {
        case .talk:
            return 0
        case .listen:
            return 1
        }
    }
}

struct ConversationViewModel {
    let mode: ConversationMode
    let isInputVisible: Bool
    let transcriptFontScale: Float
    let isMicrophoneAvailable: Bool
    let voiceInputState: ConversationVoiceInputState
}

enum ConversationVoiceInputState: Equatable {
    case idle
    case requestingPermission
    case recording
    case recognizing
}

@MainActor
protocol ConversationView: AnyObject {
    func render(_ viewModel: ConversationViewModel)
    func displayStartTypingHint()
    func displayMicrophoneHint()
    func hideConversationHints()
    func displayLargeText(_ text: String)
    func dismissLargeTextDisplay()
    func displayRecognizedSpeech(_ text: String)
    func displayConversationError(_ message: String)
    func displaySubmittedText(_ text: String)
    func clearConversationMessages()
    func displayConversationMessages(_ messages: [ConversationMessage])
}

@MainActor
final class ConversationPresenter {
    private weak var view: ConversationView?
    private let microphonePermissionService: MicrophonePermissionService
    private let audioRecordingService: AudioRecordingService
    private let speechRecognitionService: SpeechRecognitionService
    private let textToSpeechService: TextToSpeechService
    private let fetchSettingsUseCase: FetchSettingsUseCase
    private let fetchConversationUseCase: FetchConversationUseCase
    private let fetchConversationMessagesUseCase: FetchConversationMessagesUseCase
    private let saveConversationUseCase: SaveConversationUseCase
    private let addConversationMessageUseCase: AddConversationMessageUseCase
    private let maximumRecordingDuration: TimeInterval
    private var mode: ConversationMode = .talk
    private var voiceInputState: ConversationVoiceInputState = .idle
    private var currentConversation: Conversation
    private var hasPersistedConversation = false
    private var hasConversationMessages = false
    private var recordingLimitTask: Task<Void, Never>?
    private var pendingTranscriptionFileURL: URL?
    private var settings = AppSettings.defaultValue

    init(
        view: ConversationView,
        microphonePermissionService: MicrophonePermissionService,
        audioRecordingService: AudioRecordingService,
        speechRecognitionService: SpeechRecognitionService,
        textToSpeechService: TextToSpeechService,
        fetchSettingsUseCase: FetchSettingsUseCase,
        fetchConversationUseCase: FetchConversationUseCase,
        fetchConversationMessagesUseCase: FetchConversationMessagesUseCase,
        saveConversationUseCase: SaveConversationUseCase,
        addConversationMessageUseCase: AddConversationMessageUseCase,
        maximumRecordingDuration: TimeInterval = 30
    ) {
        self.view = view
        self.microphonePermissionService = microphonePermissionService
        self.audioRecordingService = audioRecordingService
        self.speechRecognitionService = speechRecognitionService
        self.textToSpeechService = textToSpeechService
        self.fetchSettingsUseCase = fetchSettingsUseCase
        self.fetchConversationUseCase = fetchConversationUseCase
        self.fetchConversationMessagesUseCase = fetchConversationMessagesUseCase
        self.saveConversationUseCase = saveConversationUseCase
        self.addConversationMessageUseCase = addConversationMessageUseCase
        self.maximumRecordingDuration = maximumRecordingDuration
        self.currentConversation = Self.makeInitialConversation(mode: mode.domainMode)
    }

    func viewDidLoad() {
        renderCurrentMode()
        refreshSettings()
    }

    func viewWillAppear() {
        refreshSettings()
    }

    func viewDidDisappear() {
        stopActiveVoiceInputIfNeeded()
        view?.hideConversationHints()
        view?.dismissLargeTextDisplay()
    }

    func didChangeSegment(index: Int) {
        guard let nextMode = ConversationMode(segmentIndex: index), nextMode != mode else {
            return
        }

        mode = nextMode
        currentConversation.mode = nextMode.domainMode
        currentConversation.updatedAt = Date()
        view?.hideConversationHints()
        renderCurrentMode()

        if hasPersistedConversation {
            persistCurrentConversation()
        }

    }

    func didTapMicrophoneHint() {
        view?.displayLargeText(
            "Включен микрофон.\nГоворите.\nПостарайтесь говорить разборчиво и не очень быстро"
        )
    }

    @discardableResult
    func didRequestStartVoiceRecording() -> Bool {
        guard voiceInputState == .idle else {
            return false
        }

        guard settings.privacyMode != .localOnly else {
            view?.displayConversationError(
                "Распознавание через сервер отключено в настройках конфиденциальности."
            )
            return false
        }

        transitionVoiceInput(to: .requestingPermission)
        microphonePermissionService.requestPermission { [weak self] isGranted in
            DispatchQueue.main.async {
                guard let self else { return }
                guard self.voiceInputState == .requestingPermission else { return }

                guard isGranted else {
                    self.transitionVoiceInput(to: .idle)
                    self.view?.displayConversationError("Разрешите доступ к микрофону в настройках iOS.")
                    return
                }

                do {
                    try self.audioRecordingService.startRecording()
                    self.transitionVoiceInput(to: .recording)
                    self.scheduleRecordingLimit(for: self.currentConversation.id)
                } catch {
                    AppLogger.error("Failed to start recording: \(error.localizedDescription)")
                    self.transitionVoiceInput(to: .idle)
                    self.view?.displayConversationError("Не удалось включить запись.")
                }
            }
        }

        return true
    }

    func didRequestStopVoiceRecording() {
        if voiceInputState == .requestingPermission {
            transitionVoiceInput(to: .idle)
            return
        }

        guard voiceInputState == .recording else {
            return
        }

        finishVoiceRecording(expectedConversationId: currentConversation.id)
    }

    private func finishVoiceRecording(expectedConversationId: String) {
        guard voiceInputState == .recording,
              currentConversation.id == expectedConversationId else {
            return
        }

        cancelRecordingLimit()

        guard let fileURL = audioRecordingService.stopRecording() else {
            transitionVoiceInput(to: .idle)
            view?.displayConversationError("Не удалось найти записанный аудиофайл.")
            return
        }

        transitionVoiceInput(to: .recognizing)
        let conversationId = currentConversation.id
        let audioRecordingService = audioRecordingService
        pendingTranscriptionFileURL = fileURL
        speechRecognitionService.transcribeAudio(
            fileURL: fileURL,
            language: settings.recognitionLanguage,
            conversationId: conversationId
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else {
                    audioRecordingService.discardRecording(at: fileURL)
                    return
                }
                if self.pendingTranscriptionFileURL == fileURL {
                    audioRecordingService.discardRecording(at: fileURL)
                    self.pendingTranscriptionFileURL = nil
                }
                guard self.currentConversation.id == conversationId else { return }
                guard self.voiceInputState == .recognizing else { return }

                self.transitionVoiceInput(to: .idle)

                switch result {
                case .success(let model):
                    self.handleRecognizedSpeech(model)
                case .failure(let error):
                    AppLogger.error("Speech recognition failed: \(error.localizedDescription)")
                    self.view?.displayConversationError(self.message(forSpeechError: error))
                }
            }
        }
    }

    func didSubmitText(_ text: String) {
        submitOutgoingMessage(text, source: .userTyped)
    }

    func didSubmitQuickPhrase(_ text: String) {
        submitOutgoingMessage(text, source: .quickPhrase)
    }

    func didRequestNewConversation() {
        stopActiveVoiceInputIfNeeded()
        currentConversation = Self.makeInitialConversation(mode: mode.domainMode)
        hasPersistedConversation = false
        hasConversationMessages = false

        view?.hideConversationHints()
        view?.dismissLargeTextDisplay()
        view?.clearConversationMessages()
        renderCurrentMode()
        displayEmptyTalkHintsIfNeeded()
    }

    func didRequestResumeConversation(id: String) {
        stopActiveVoiceInputIfNeeded()

        Task { [weak self, fetchConversationUseCase, fetchConversationMessagesUseCase] in
            guard let self else { return }

            do {
                guard let conversation = try await fetchConversationUseCase.execute(id: id) else {
                    self.view?.displayConversationError("Сохраненный разговор не найден.")
                    return
                }

                let messages = try await fetchConversationMessagesUseCase.execute(
                    conversationId: conversation.id
                )

                self.currentConversation = conversation
                self.mode = ConversationMode(domainMode: conversation.mode)
                self.hasPersistedConversation = true
                self.hasConversationMessages = !messages.isEmpty
                self.view?.hideConversationHints()
                self.view?.dismissLargeTextDisplay()
                self.view?.clearConversationMessages()
                self.renderCurrentMode()
                self.view?.displayConversationMessages(messages)
            } catch {
                AppLogger.error("Failed to resume conversation: \(error.localizedDescription)")
                self.view?.displayConversationError("Не удалось продолжить разговор.")
            }
        }
    }

    func didShowEmptyTalkScreen() {
        displayEmptyTalkHintsIfNeeded()
    }

    func didRequestLargeText(_ text: String) {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else { return }
        view?.displayLargeText(normalizedText)
    }

    func didRequestSpeak(_ text: String) {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else { return }
        textToSpeechService.speak(normalizedText)
    }

    private func renderCurrentMode() {
        view?.render(
            ConversationViewModel(
                mode: mode,
                isInputVisible: mode == .talk,
                transcriptFontScale: settings.transcriptFontScale,
                isMicrophoneAvailable: microphonePermissionService.authorizationStatus == .granted,
                voiceInputState: voiceInputState
            )
        )
    }

    private func displayEmptyTalkHintsIfNeeded() {
        guard mode == .talk else { return }

        view?.displayMicrophoneHint()
        view?.displayStartTypingHint()
    }

    private func handleRecognizedSpeech(_ model: SpeechToTextModel) {
        let normalizedText = model.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else {
            view?.displayConversationError("Речь не распознана.")
            return
        }

        hasConversationMessages = true
        view?.hideConversationHints()
        view?.displayRecognizedSpeech(normalizedText)
        persistMessage(
            text: normalizedText,
            source: .externalSpeech,
            speakerId: nil,
            speakerLabel: "Говорящий 1",
            audioDurationMs: model.durationMs
        )
    }

    private func submitOutgoingMessage(
        _ text: String,
        source: ConversationMessage.Source
    ) {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else {
            return
        }

        hasConversationMessages = true
        view?.hideConversationHints()
        view?.displaySubmittedText(normalizedText)
        persistMessage(
            text: normalizedText,
            source: source,
            speakerId: nil,
            speakerLabel: nil,
            audioDurationMs: nil
        )
    }

    private func persistCurrentConversation() {
        guard settings.saveConversationsByDefault else { return }

        let conversation = currentConversation

        Task { [saveConversationUseCase] in
            do {
                try await saveConversationUseCase.execute(conversation)
            } catch {
                AppLogger.error("Failed to save conversation: \(error.localizedDescription)")
            }
        }
    }

    private func persistMessage(
        text: String,
        source: ConversationMessage.Source,
        speakerId: String?,
        speakerLabel: String?,
        audioDurationMs: Int?
    ) {
        guard settings.saveConversationsByDefault else { return }

        let now = Date()
        if !hasPersistedConversation {
            currentConversation.title = Self.makeConversationTitle(from: text)
        }

        currentConversation.mode = mode.domainMode
        currentConversation.updatedAt = now
        hasPersistedConversation = true

        let conversation = currentConversation
        let message = ConversationMessage(
            id: UUID().uuidString,
            conversationId: conversation.id,
            text: text,
            source: source,
            speakerId: speakerId,
            speakerLabel: speakerLabel,
            isFinal: true,
            createdAt: now,
            audioDurationMs: audioDurationMs,
            syncState: .localOnly
        )

        Task { [saveConversationUseCase, addConversationMessageUseCase] in
            do {
                try await saveConversationUseCase.execute(conversation)
                try await addConversationMessageUseCase.execute(message)
            } catch {
                AppLogger.error("Failed to save conversation message: \(error.localizedDescription)")
            }
        }
    }

    private func stopActiveVoiceInputIfNeeded() {
        cancelRecordingLimit()

        switch voiceInputState {
        case .idle:
            break
        case .requestingPermission:
            transitionVoiceInput(to: .idle)
        case .recognizing:
            speechRecognitionService.cancelTranscription()
            discardPendingTranscriptionFile()
            transitionVoiceInput(to: .idle)
        case .recording:
            if let fileURL = audioRecordingService.stopRecording() {
                audioRecordingService.discardRecording(at: fileURL)
            }
            transitionVoiceInput(to: .idle)
        }
    }

    private func refreshSettings() {
        Task { [weak self, fetchSettingsUseCase] in
            do {
                let settings = try await fetchSettingsUseCase.execute()
                self?.settings = settings
                self?.renderCurrentMode()
            } catch {
                AppLogger.error("Failed to refresh conversation settings: \(error.localizedDescription)")
            }
        }
    }

    private func transitionVoiceInput(to state: ConversationVoiceInputState) {
        guard voiceInputState != state else { return }
        voiceInputState = state
        renderCurrentMode()
    }

    private func scheduleRecordingLimit(for conversationId: String) {
        cancelRecordingLimit()

        let duration = max(0, maximumRecordingDuration)
        let nanoseconds = UInt64(duration * 1_000_000_000)
        recordingLimitTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            self?.finishVoiceRecording(expectedConversationId: conversationId)
        }
    }

    private func cancelRecordingLimit() {
        recordingLimitTask?.cancel()
        recordingLimitTask = nil
    }

    private func discardPendingTranscriptionFile() {
        guard let fileURL = pendingTranscriptionFileURL else { return }
        audioRecordingService.discardRecording(at: fileURL)
        pendingTranscriptionFileURL = nil
    }

    private func message(forSpeechError error: Error) -> String {
        guard let appError = error as? AppError else {
            return "Не удалось распознать речь. Попробуйте ещё раз."
        }

        switch appError {
        case .networkUnavailable:
            return "Нет подключения к интернету. Печатный ввод и готовые фразы продолжают работать."
        case .apiError(let code, _, _):
            switch code {
            case "speech_unavailable":
                return "Распознавание речи временно недоступно. Попробуйте позже."
            case "speech_busy":
                return "Сервис распознавания занят. Повторите через несколько секунд."
            case "audio_too_long":
                return "Запись получилась слишком длинной. Говорите не больше 30 секунд."
            case "unsupported_language":
                return "Выбранный язык пока не поддерживается распознаванием."
            default:
                return "Не удалось распознать речь. Попробуйте ещё раз."
            }
        case .speechUnavailable:
            return "Распознавание речи временно недоступно. Попробуйте позже."
        default:
            return "Не удалось распознать речь. Попробуйте ещё раз."
        }
    }

    private static func makeInitialConversation(mode: Conversation.Mode) -> Conversation {
        let now = Date()

        return Conversation(
            id: UUID().uuidString,
            title: "Новый разговор",
            mode: mode,
            createdAt: now,
            updatedAt: now,
            isPinned: false,
            syncState: .localOnly
        )
    }

    private static func makeConversationTitle(from text: String) -> String {
        let maxTitleLength = 42
        guard text.count > maxTitleLength else {
            return text
        }

        let endIndex = text.index(text.startIndex, offsetBy: maxTitleLength)
        return "\(text[..<endIndex])..."
    }
}

private extension ConversationMode {
    init(domainMode: Conversation.Mode) {
        switch domainMode {
        case .talk:
            self = .talk
        case .listen:
            self = .listen
        }
    }

    var domainMode: Conversation.Mode {
        switch self {
        case .talk:
            return .talk
        case .listen:
            return .listen
        }
    }
}
