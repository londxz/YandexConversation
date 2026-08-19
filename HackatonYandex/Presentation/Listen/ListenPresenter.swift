//
//  ListenPresenter.swift
//  HackatonYandex
//
//  Created by Rodion Kholodov.
//

import Foundation

enum ListenSessionState: Equatable {
    case idle
    case requestingPermission
    case connecting
    case listening
    case reconnecting
    case pausing
    case paused
    case failed(String)
}

struct ListenViewModel: Equatable {
    let state: ListenSessionState
    let statusText: String
    let isMicrophoneActive: Bool
    let isControlEnabled: Bool
    let showsPauseAction: Bool
}

@MainActor
protocol ListenView: AnyObject {
    func render(_ viewModel: ListenViewModel)
    func displayPartialSpeech(_ segment: RealtimeSpeechSegment)
    func displayFinalSpeech(_ segment: RealtimeSpeechSegment)
    func clearPartialSpeech()
}

@MainActor
protocol ListenPresenterDelegate: AnyObject {
    func listenPresenter(
        _ presenter: ListenPresenter,
        didFinalize segment: RealtimeSpeechSegment,
        conversationId: String
    )
    func listenPresenter(
        _ presenter: ListenPresenter,
        didChangeMicrophoneActivity isActive: Bool
    )
}

@MainActor
final class ListenPresenter {
    weak var delegate: ListenPresenterDelegate?

    private weak var view: ListenView?
    private let microphonePermissionService: MicrophonePermissionService
    private let audioCaptureService: RealtimeAudioCaptureService
    private let speechClient: RealtimeSpeechClient

    private var configuration: RealtimeSpeechConfiguration?
    private var state: ListenSessionState = .idle
    private var isActive = false
    private var hasUserPaused = false

    init(
        view: ListenView,
        microphonePermissionService: MicrophonePermissionService,
        audioCaptureService: RealtimeAudioCaptureService,
        speechClient: RealtimeSpeechClient
    ) {
        self.view = view
        self.microphonePermissionService = microphonePermissionService
        self.audioCaptureService = audioCaptureService
        self.speechClient = speechClient
        speechClient.eventHandler = { [weak self] event in
            DispatchQueue.main.async {
                self?.handle(event)
            }
        }
    }

    func viewDidLoad() {
        render()
    }

    func activate(
        configuration: RealtimeSpeechConfiguration,
        autoStart: Bool
    ) {
        let configurationChanged = self.configuration != configuration
        if configurationChanged {
            stopImmediately()
            self.configuration = configuration
            hasUserPaused = false
            view?.clearPartialSpeech()
        }

        isActive = true
        if autoStart, !hasUserPaused, state != .listening, state != .connecting {
            startListening()
        } else if state == .idle {
            transition(to: .paused)
        } else {
            render()
        }
    }

    func deactivate() {
        isActive = false
        stopImmediately()
        configuration = nil
        hasUserPaused = false
        transition(to: .idle)
    }

    func didTapPauseResume() {
        switch state {
        case .listening, .connecting, .reconnecting, .requestingPermission:
            hasUserPaused = true
            pauseListening()
        case .paused, .failed:
            hasUserPaused = false
            startListening()
        case .idle:
            guard isActive else { return }
            startListening()
        case .pausing:
            break
        }
    }

    func clearTranscriptState() {
        view?.clearPartialSpeech()
    }

    private func startListening() {
        guard isActive,
              configuration != nil else {
            return
        }
        guard state != .requestingPermission,
              state != .connecting,
              state != .listening else {
            return
        }

        transition(to: .requestingPermission)
        microphonePermissionService.requestPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self,
                      self.isActive,
                      self.state == .requestingPermission else {
                    return
                }
                guard granted else {
                    self.transition(to: .failed("Разрешите доступ к микрофону в настройках iOS"))
                    return
                }
                self.beginAudioAndRecognition()
            }
        }
    }

    private func beginAudioAndRecognition() {
        guard let configuration else { return }

        do {
            speechClient.start(configuration: configuration)
            try audioCaptureService.startCapture { [weak speechClient] data in
                speechClient?.appendAudioChunk(data)
            }
            delegate?.listenPresenter(self, didChangeMicrophoneActivity: true)
            transition(to: .connecting)
        } catch {
            speechClient.cancel()
            audioCaptureService.stopCapture()
            delegate?.listenPresenter(self, didChangeMicrophoneActivity: false)
            transition(to: .failed("Не удалось включить микрофон"))
        }
    }

    private func pauseListening() {
        guard state != .pausing, state != .paused else { return }
        audioCaptureService.stopCapture()
        delegate?.listenPresenter(self, didChangeMicrophoneActivity: false)
        transition(to: .pausing)
        speechClient.stop()
    }

    private func stopImmediately() {
        audioCaptureService.stopCapture()
        speechClient.cancel()
        delegate?.listenPresenter(self, didChangeMicrophoneActivity: false)
        view?.clearPartialSpeech()
        state = .idle
    }

    private func handle(_ event: RealtimeSpeechEvent) {
        guard isActive else { return }

        switch event {
        case .connecting:
            transition(to: .connecting)
        case .connected:
            transition(to: .listening)
        case .reconnecting:
            transition(to: .reconnecting)
        case .partial(let segment):
            view?.displayPartialSpeech(segment)
        case .final(let segment):
            view?.clearPartialSpeech()
            view?.displayFinalSpeech(segment)
            if let conversationId = configuration?.conversationId {
                delegate?.listenPresenter(
                    self,
                    didFinalize: segment,
                    conversationId: conversationId
                )
            }
        case .stopped:
            view?.clearPartialSpeech()
            transition(to: .paused)
        case .failure(let error):
            audioCaptureService.stopCapture()
            delegate?.listenPresenter(self, didChangeMicrophoneActivity: false)
            view?.clearPartialSpeech()
            transition(to: .failed(message(for: error)))
        }
    }

    private func transition(to newState: ListenSessionState) {
        state = newState
        render()
    }

    private func render() {
        let isMicrophoneActive = audioCaptureService.isCapturing
        view?.render(
            ListenViewModel(
                state: state,
                statusText: statusText(for: state),
                isMicrophoneActive: isMicrophoneActive,
                isControlEnabled: state != .requestingPermission && state != .pausing,
                showsPauseAction: isMicrophoneActive
            )
        )
    }

    private func statusText(for state: ListenSessionState) -> String {
        switch state {
        case .idle:
            return "Режим «Слушать»"
        case .requestingPermission:
            return "Проверяем доступ к микрофону"
        case .connecting:
            return "Подключение к распознаванию"
        case .listening:
            return "Слушаю"
        case .reconnecting:
            return "Восстанавливаю соединение"
        case .pausing:
            return "Завершаю фразу"
        case .paused:
            return "Прослушивание приостановлено"
        case .failed(let message):
            return message
        }
    }

    private func message(for error: Error) -> String {
        guard let appError = error as? AppError else {
            return "Распознавание временно недоступно"
        }
        switch appError {
        case .permissionDenied:
            return "Разрешите распознавание речи в настройках iOS"
        case .onDeviceRecognitionUnavailable:
            return "Офлайн-распознавание недоступно для выбранного языка"
        case .networkUnavailable:
            return "Нет соединения. Нажмите, чтобы повторить"
        default:
            return "Распознавание временно недоступно. Нажмите, чтобы повторить"
        }
    }
}
