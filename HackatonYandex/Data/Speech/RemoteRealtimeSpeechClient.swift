//
//  RemoteRealtimeSpeechClient.swift
//  HackatonYandex
//
//  Created by Rodion Kholodov.
//

import Foundation

final class RemoteRealtimeSpeechClient: NSObject, RealtimeSpeechClient {
    var eventHandler: ((RealtimeSpeechEvent) -> Void)?

    private let config: AppConfig
    private let deviceSessionRepository: DeviceSessionRepository
    private let stateQueue = DispatchQueue(
        label: "com.rodionkholodov.razgovor.realtime-speech",
        qos: .userInitiated
    )
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let maxPendingChunks = 50
    private let maxReconnectAttempts = 4

    private lazy var urlSession = URLSession(
        configuration: .default,
        delegate: self,
        delegateQueue: nil
    )

    private var configuration: RealtimeSpeechConfiguration?
    private var webSocketTask: URLSessionWebSocketTask?
    private var shouldRun = false
    private var isReady = false
    private var isSending = false
    private var stopRequested = false
    private var nextSequence = 1
    private var reconnectAttempt = 0
    private var pendingChunks: [Data] = []
    private var reconnectWorkItem: DispatchWorkItem?
    private var stopWorkItem: DispatchWorkItem?
    private var accessToken: String?

    init(
        config: AppConfig,
        deviceSessionRepository: DeviceSessionRepository
    ) {
        self.config = config
        self.deviceSessionRepository = deviceSessionRepository
        super.init()
    }

    func start(configuration: RealtimeSpeechConfiguration) {
        stateQueue.async { [weak self] in
            guard let self else { return }
            cancelCurrentSession(notify: false)
            self.configuration = configuration
            shouldRun = true
            stopRequested = false
            reconnectAttempt = 0
            pendingChunks.removeAll(keepingCapacity: true)
            emit(.connecting)
            connect()
        }
    }

    func appendAudioChunk(_ data: Data) {
        guard !data.isEmpty else { return }
        stateQueue.async { [weak self] in
            guard let self, shouldRun, !stopRequested else { return }
            if pendingChunks.count == maxPendingChunks {
                pendingChunks.removeFirst()
            }
            pendingChunks.append(data)
            sendNextChunkIfPossible()
        }
    }

    func stop() {
        stateQueue.async { [weak self] in
            guard let self else { return }
            shouldRun = false
            stopRequested = true
            reconnectWorkItem?.cancel()
            reconnectWorkItem = nil

            guard webSocketTask != nil, isReady else {
                cancelCurrentSession(notify: true)
                return
            }
            sendNextChunkIfPossible()
            sendStopIfPossible()
        }
    }

    func cancel() {
        stateQueue.async { [weak self] in
            self?.cancelCurrentSession(notify: false)
        }
    }

    private func connect() {
        guard shouldRun,
              let configuration else {
            return
        }

        Task { [weak self, deviceSessionRepository] in
            do {
                let token = try await deviceSessionRepository.accessToken()
                self?.stateQueue.async { [weak self] in
                    guard let self, shouldRun, self.configuration == configuration else { return }
                    openSocket(accessToken: token)
                }
            } catch {
                self?.stateQueue.async { [weak self] in
                    self?.handleConnectionFailure(error)
                }
            }
        }
    }

    private func openSocket(accessToken: String) {
        guard let url = websocketURL() else {
            finishWithFailure(AppError.invalidURL)
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = config.requestTimeout
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-ID")

        self.accessToken = accessToken
        nextSequence = 1
        isReady = false
        isSending = false
        let task = urlSession.webSocketTask(with: request)
        webSocketTask = task
        task.resume()
    }

    private func websocketURL() -> URL? {
        let endpoint = config.apiBaseURL.appendingPathComponent("v1/speech/stream")
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            return nil
        }
        switch components.scheme?.lowercased() {
        case "http":
            components.scheme = "ws"
        case "https":
            components.scheme = "wss"
        default:
            return nil
        }
        return components.url
    }

    private func sendStart(on task: URLSessionWebSocketTask) {
        guard let configuration else { return }
        let message = StartMessage(
            type: "start",
            conversationId: configuration.conversationId,
            mode: "listen",
            language: configuration.language,
            audio: AudioFormat(
                format: "pcm16",
                sampleRate: 16_000,
                channels: 1
            )
        )
        send(message, on: task) { [weak self, weak task] error in
            guard let self, let task else { return }
            stateQueue.async {
                guard self.webSocketTask === task else { return }
                if let error {
                    self.handleConnectionFailure(error)
                }
            }
        }
    }

    private func receiveNext(on task: URLSessionWebSocketTask) {
        task.receive { [weak self, weak task] result in
            guard let self, let task else { return }
            stateQueue.async {
                guard self.webSocketTask === task else { return }
                switch result {
                case .success(let message):
                    self.handle(message, from: task)
                    if self.webSocketTask === task {
                        self.receiveNext(on: task)
                    }
                case .failure(let error):
                    self.handleConnectionFailure(error)
                }
            }
        }
    }

    private func handle(
        _ message: URLSessionWebSocketTask.Message,
        from task: URLSessionWebSocketTask
    ) {
        let data: Data
        switch message {
        case .string(let value):
            guard let valueData = value.data(using: .utf8) else {
                finishWithFailure(AppError.decodingFailed)
                return
            }
            data = valueData
        case .data(let value):
            data = value
        @unknown default:
            finishWithFailure(AppError.decodingFailed)
            return
        }

        guard let event = try? decoder.decode(ServerEvent.self, from: data) else {
            finishWithFailure(AppError.decodingFailed)
            return
        }

        switch event.type {
        case "ready":
            reconnectAttempt = 0
            isReady = true
            emit(.connected)
            sendNextChunkIfPossible()
            sendStopIfPossible()
        case "partial", "final":
            guard let segment = event.segment else { return }
            if event.type == "partial" {
                emit(.partial(segment))
            } else {
                emit(.final(segment))
            }
        case "error":
            emit(
                .failure(
                    AppError.apiError(
                        code: event.code ?? "speech_unavailable",
                        message: event.message ?? "Speech recognition failed.",
                        requestID: event.requestId
                    )
                )
            )
        case "stopped":
            stopWorkItem?.cancel()
            stopWorkItem = nil
            task.cancel(with: .normalClosure, reason: nil)
            webSocketTask = nil
            isReady = false
            stopRequested = false
            emit(.stopped)
        default:
            finishWithFailure(AppError.decodingFailed)
        }
    }

    private func sendNextChunkIfPossible() {
        guard shouldRun || stopRequested,
              isReady,
              !isSending,
              let task = webSocketTask,
              let data = pendingChunks.first else {
            sendStopIfPossible()
            return
        }

        isSending = true
        let sequence = nextSequence
        let message = AudioChunkMessage(
            type: "audio_chunk",
            sequence: sequence,
            data: data
        )
        send(message, on: task) { [weak self, weak task] error in
            guard let self, let task else { return }
            stateQueue.async {
                guard self.webSocketTask === task else { return }
                self.isSending = false
                if let error {
                    self.handleConnectionFailure(error)
                    return
                }
                if !self.pendingChunks.isEmpty {
                    self.pendingChunks.removeFirst()
                }
                self.nextSequence = sequence + 1
                self.sendNextChunkIfPossible()
            }
        }
    }

    private func sendStopIfPossible() {
        guard stopRequested,
              isReady,
              !isSending,
              pendingChunks.isEmpty,
              let task = webSocketTask else {
            return
        }

        isReady = false
        send(StopMessage(type: "stop"), on: task) { [weak self, weak task] error in
            guard let self, let task else { return }
            stateQueue.async {
                guard self.webSocketTask === task else { return }
                if error != nil {
                    self.cancelCurrentSession(notify: true)
                    return
                }
                self.scheduleStopTimeout(for: task)
            }
        }
    }

    private func scheduleStopTimeout(for task: URLSessionWebSocketTask) {
        stopWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self, weak task] in
            guard let self, let task, webSocketTask === task else { return }
            cancelCurrentSession(notify: true)
        }
        stopWorkItem = workItem
        stateQueue.asyncAfter(deadline: .now() + 8, execute: workItem)
    }

    private func handleConnectionFailure(_ error: Error) {
        guard webSocketTask != nil || shouldRun else {
            if stopRequested {
                cancelCurrentSession(notify: true)
            }
            return
        }

        let failedTask = webSocketTask
        let statusCode = (failedTask?.response as? HTTPURLResponse)?.statusCode
        failedTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isReady = false
        isSending = false
        nextSequence = 1

        guard shouldRun else {
            cancelCurrentSession(notify: true)
            return
        }

        if statusCode == 401, let accessToken {
            refreshTokenAndReconnect(rejectedToken: accessToken)
            return
        }

        reconnectAttempt += 1
        guard reconnectAttempt <= maxReconnectAttempts else {
            finishWithFailure(Self.mapConnectionError(error))
            return
        }

        emit(.reconnecting(attempt: reconnectAttempt))
        let delay = min(pow(2, Double(reconnectAttempt - 1)) * 0.5, 4)
        let workItem = DispatchWorkItem { [weak self] in
            self?.connect()
        }
        reconnectWorkItem?.cancel()
        reconnectWorkItem = workItem
        stateQueue.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func refreshTokenAndReconnect(rejectedToken: String) {
        Task { [weak self, deviceSessionRepository] in
            do {
                _ = try await deviceSessionRepository.refreshAccessToken(
                    rejectedAccessToken: rejectedToken
                )
                self?.stateQueue.async { [weak self] in
                    self?.connect()
                }
            } catch {
                self?.stateQueue.async { [weak self] in
                    self?.finishWithFailure(error)
                }
            }
        }
    }

    private func finishWithFailure(_ error: Error) {
        cancelCurrentSession(notify: false)
        emit(.failure(error))
    }

    private func cancelCurrentSession(notify: Bool) {
        let shouldNotify = notify && (webSocketTask != nil || stopRequested)
        shouldRun = false
        isReady = false
        isSending = false
        stopRequested = false
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        stopWorkItem?.cancel()
        stopWorkItem = nil
        pendingChunks.removeAll(keepingCapacity: true)
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        accessToken = nil
        if shouldNotify {
            emit(.stopped)
        }
    }

    private func send<Message: Encodable>(
        _ message: Message,
        on task: URLSessionWebSocketTask,
        completion: @escaping (Error?) -> Void
    ) {
        do {
            let data = try encoder.encode(message)
            guard let text = String(data: data, encoding: .utf8) else {
                completion(AppError.decodingFailed)
                return
            }
            task.send(.string(text), completionHandler: completion)
        } catch {
            completion(error)
        }
    }

    private func emit(_ event: RealtimeSpeechEvent) {
        DispatchQueue.main.async { [weak self] in
            self?.eventHandler?(event)
        }
    }

    private static func mapConnectionError(_ error: Error) -> Error {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet,
                 .networkConnectionLost,
                 .cannotFindHost,
                 .cannotConnectToHost,
                 .dnsLookupFailed,
                 .timedOut:
                return AppError.networkUnavailable
            default:
                break
            }
        }
        return AppError.speechUnavailable
    }
}

extension RemoteRealtimeSpeechClient: URLSessionWebSocketDelegate {
    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        stateQueue.async { [weak self, weak webSocketTask] in
            guard let self,
                  let webSocketTask,
                  self.webSocketTask === webSocketTask else {
                return
            }
            receiveNext(on: webSocketTask)
            sendStart(on: webSocketTask)
        }
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        stateQueue.async { [weak self, weak webSocketTask] in
            guard let self,
                  let webSocketTask,
                  self.webSocketTask === webSocketTask else {
                return
            }
            if closeCode == .normalClosure, self.stopRequested {
                self.cancelCurrentSession(notify: true)
            } else {
                self.handleConnectionFailure(AppError.networkUnavailable)
            }
        }
    }
}

private struct StartMessage: Encodable {
    let type: String
    let conversationId: String
    let mode: String
    let language: String
    let audio: AudioFormat

    enum CodingKeys: String, CodingKey {
        case type
        case conversationId = "conversation_id"
        case mode
        case language
        case audio
    }
}

private struct AudioFormat: Encodable {
    let format: String
    let sampleRate: Int
    let channels: Int

    enum CodingKeys: String, CodingKey {
        case format
        case sampleRate = "sample_rate"
        case channels
    }
}

private struct AudioChunkMessage: Encodable {
    let type: String
    let sequence: Int
    let data: Data
}

private struct StopMessage: Encodable {
    let type: String
}

private struct ServerEvent: Decodable {
    let type: String
    let sequence: Int?
    let messageId: String?
    let text: String?
    let speaker: ServerSpeaker?
    let confidence: Double?
    let code: String?
    let message: String?
    let requestId: String?

    var segment: RealtimeSpeechSegment? {
        guard let sequence,
              let text,
              let speaker else {
            return nil
        }
        return RealtimeSpeechSegment(
            id: messageId,
            sequence: sequence,
            text: text,
            speakerId: speaker.id,
            speakerLabel: speaker.label,
            confidence: confidence
        )
    }

    enum CodingKeys: String, CodingKey {
        case type
        case sequence
        case messageId = "message_id"
        case text
        case speaker
        case confidence
        case code
        case message
        case requestId = "request_id"
    }
}

private struct ServerSpeaker: Decodable {
    let id: String
    let label: String
}
