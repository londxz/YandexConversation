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
}

private enum VoiceInputState {
    case idle
    case requestingPermission
    case recording
    case recognizing
}

protocol ConversationView: AnyObject {
    func render(_ viewModel: ConversationViewModel)
    func displayStartTypingHint()
    func displayMicrophoneHint()
    func hideConversationHints()
    func presentMicrophoneOverlay()
    func displayRecognizedSpeech(_ text: String)
    func displayConversationError(_ message: String)
    func displaySubmittedText(_ text: String)
    func clearConversationMessages()
    func toggleConversationDisplayRotation()
    func resetConversationDisplay()
}

@MainActor
final class ConversationPresenter {
    private weak var view: ConversationView?
    private let microphonePermissionService: MicrophonePermissionService
    private let audioRecordingService: AudioRecordingService
    private let speechRecognitionService: SpeechRecognitionService
    private let fetchSettingsUseCase: FetchSettingsUseCase
    private let saveConversationUseCase: SaveConversationUseCase
    private let addConversationMessageUseCase: AddConversationMessageUseCase
    private var mode: ConversationMode = .talk
    private var voiceInputState: VoiceInputState = .idle
    private var currentConversation: Conversation
    private var hasPersistedConversation = false
    private var settings = AppSettings.defaultValue

    init(
        view: ConversationView,
        microphonePermissionService: MicrophonePermissionService,
        audioRecordingService: AudioRecordingService,
        speechRecognitionService: SpeechRecognitionService,
        fetchSettingsUseCase: FetchSettingsUseCase,
        saveConversationUseCase: SaveConversationUseCase,
        addConversationMessageUseCase: AddConversationMessageUseCase
    ) {
        self.view = view
        self.microphonePermissionService = microphonePermissionService
        self.audioRecordingService = audioRecordingService
        self.speechRecognitionService = speechRecognitionService
        self.fetchSettingsUseCase = fetchSettingsUseCase
        self.saveConversationUseCase = saveConversationUseCase
        self.addConversationMessageUseCase = addConversationMessageUseCase
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
        view?.hideConversationHints()
        view?.resetConversationDisplay()
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
        view?.presentMicrophoneOverlay()
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

        voiceInputState = .requestingPermission
        microphonePermissionService.requestPermission { [weak self] isGranted in
            DispatchQueue.main.async {
                guard let self else { return }
                guard self.voiceInputState == .requestingPermission else { return }

                guard isGranted else {
                    self.voiceInputState = .idle
                    self.view?.displayConversationError("Разрешите доступ к микрофону в настройках iOS.")
                    return
                }

                do {
                    try self.audioRecordingService.startRecording()
                    self.voiceInputState = .recording
                } catch {
                    AppLogger.error("Failed to start recording: \(error.localizedDescription)")
                    self.voiceInputState = .idle
                    self.view?.displayConversationError("Не удалось включить запись.")
                }
            }
        }

        return true
    }

    func didRequestStopVoiceRecording() {
        if voiceInputState == .requestingPermission {
            voiceInputState = .idle
            return
        }

        guard voiceInputState == .recording else {
            return
        }

        guard let fileURL = audioRecordingService.stopRecording() else {
            voiceInputState = .idle
            view?.displayConversationError("Не удалось найти записанный аудиофайл.")
            return
        }

        voiceInputState = .recognizing
        let conversationId = currentConversation.id
        let audioRecordingService = audioRecordingService
        speechRecognitionService.transcribeAudio(
            fileURL: fileURL,
            language: settings.recognitionLanguage
        ) { [weak self] result in
            DispatchQueue.main.async {
                audioRecordingService.discardRecording(at: fileURL)
                guard let self else { return }
                guard self.currentConversation.id == conversationId else { return }

                self.voiceInputState = .idle

                switch result {
                case .success(let model):
                    self.handleRecognizedSpeech(model.text)
                case .failure(let error):
                    AppLogger.error("Speech recognition failed: \(error.localizedDescription)")
                    self.view?.displayConversationError("Не удалось распознать речь.")
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

        view?.hideConversationHints()
        view?.resetConversationDisplay()
        view?.clearConversationMessages()
        renderCurrentMode()
        displayEmptyTalkHintsIfNeeded()
    }

    func didShowEmptyTalkScreen() {
        displayEmptyTalkHintsIfNeeded()
    }

    func didRequestRotationToggle() {
        view?.toggleConversationDisplayRotation()
    }

    func didRequestResetRotation() {
        view?.resetConversationDisplay()
    }

    private func renderCurrentMode() {
        view?.render(
            ConversationViewModel(
                mode: mode,
                isInputVisible: mode == .talk,
                transcriptFontScale: settings.transcriptFontScale
            )
        )
    }

    private func displayEmptyTalkHintsIfNeeded() {
        guard mode == .talk else { return }

        view?.displayMicrophoneHint()
        view?.displayStartTypingHint()
    }

    private func handleRecognizedSpeech(_ text: String) {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else {
            view?.displayConversationError("Речь не распознана.")
            return
        }

        view?.hideConversationHints()
        view?.displayRecognizedSpeech(normalizedText)
        persistMessage(
            text: normalizedText,
            source: .externalSpeech,
            speakerId: nil,
            speakerLabel: "Говорящий 1",
            audioDurationMs: nil
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
        switch voiceInputState {
        case .idle:
            break
        case .requestingPermission, .recognizing:
            voiceInputState = .idle
        case .recording:
            if let fileURL = audioRecordingService.stopRecording() {
                audioRecordingService.discardRecording(at: fileURL)
            }
            voiceInputState = .idle
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
    var domainMode: Conversation.Mode {
        switch self {
        case .talk:
            return .talk
        case .listen:
            return .listen
        }
    }
}
