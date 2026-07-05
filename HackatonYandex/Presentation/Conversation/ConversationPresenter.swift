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
    func toggleConversationDisplayRotation()
    func resetConversationDisplay()
}

final class ConversationPresenter {
    private weak var view: ConversationView?
    private let microphonePermissionService: MicrophonePermissionService
    private let audioRecordingService: AudioRecordingService
    private let speechRecognitionService: SpeechRecognitionService
    private var mode: ConversationMode = .talk
    private var voiceInputState: VoiceInputState = .idle

    init(
        view: ConversationView,
        microphonePermissionService: MicrophonePermissionService,
        audioRecordingService: AudioRecordingService,
        speechRecognitionService: SpeechRecognitionService
    ) {
        self.view = view
        self.microphonePermissionService = microphonePermissionService
        self.audioRecordingService = audioRecordingService
        self.speechRecognitionService = speechRecognitionService
    }

    func viewDidLoad() {
        renderCurrentMode()
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
        view?.hideConversationHints()
        renderCurrentMode()
    }

    func didRequestStartTypingHint() {
        guard mode == .talk else {
            return
        }

        view?.displayStartTypingHint()
    }

    func didRequestMicrophoneHint() {
        guard mode == .talk else {
            return
        }

        view?.displayMicrophoneHint()
    }

    func didTapMicrophoneHint() {
        view?.presentMicrophoneOverlay()
    }

    @discardableResult
    func didRequestStartVoiceRecording() -> Bool {
        guard voiceInputState == .idle else {
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
        let audioRecordingService = audioRecordingService
        speechRecognitionService.transcribeAudio(fileURL: fileURL) { [weak self] result in
            DispatchQueue.main.async {
                audioRecordingService.discardRecording(at: fileURL)
                self?.voiceInputState = .idle

                switch result {
                case .success(let model):
                    self?.view?.displayRecognizedSpeech(model.text)
                case .failure(let error):
                    AppLogger.error("Speech recognition failed: \(error.localizedDescription)")
                    self?.view?.displayConversationError("Не удалось распознать речь.")
                }
            }
        }
    }

    func didSubmitText(_ text: String) {
        view?.displaySubmittedText(text)
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
                isInputVisible: mode == .talk
            )
        )
    }
}
