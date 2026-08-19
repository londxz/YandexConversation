//
//  BackendFirstRealtimeSpeechClient.swift
//  HackatonYandex
//
//  Created by Rodion Kholodov.
//

import Foundation

final class BackendFirstRealtimeSpeechClient: RealtimeSpeechClient {
    var eventHandler: ((RealtimeSpeechEvent) -> Void)?

    private enum ActiveClient: Equatable {
        case none
        case remote
        case local
    }

    private let remoteClient: RealtimeSpeechClient
    private let localClient: RealtimeSpeechClient
    private let fallbackBufferLimit = 160_000
    private let stateQueue = DispatchQueue(
        label: "com.rodionkholodov.razgovor.backend-first-realtime-speech",
        qos: .userInitiated
    )

    private var configuration: RealtimeSpeechConfiguration?
    private var activeClient: ActiveClient = .none
    private var bufferedAudio: [Data] = []
    private var bufferedAudioBytes = 0
    private var shouldReplayBufferedAudio = false
    private var stopRequested = false

    init(
        remoteClient: RealtimeSpeechClient,
        localClient: RealtimeSpeechClient
    ) {
        self.remoteClient = remoteClient
        self.localClient = localClient

        remoteClient.eventHandler = { [weak self] event in
            self?.stateQueue.async { [weak self] in
                self?.handleRemoteEvent(event)
            }
        }
        localClient.eventHandler = { [weak self] event in
            self?.stateQueue.async { [weak self] in
                self?.handleLocalEvent(event)
            }
        }
    }

    func start(configuration: RealtimeSpeechConfiguration) {
        stateQueue.async { [weak self] in
            guard let self else { return }
            cancelCurrentSession()
            self.configuration = configuration
            stopRequested = false
            bufferedAudio.removeAll(keepingCapacity: true)
            bufferedAudioBytes = 0

            if configuration.processingMode == .onDeviceOnly {
                activeClient = .local
                localClient.start(configuration: configuration)
            } else {
                activeClient = .remote
                remoteClient.start(configuration: configuration)
            }
        }
    }

    func appendAudioChunk(_ data: Data) {
        guard !data.isEmpty else { return }
        stateQueue.async { [weak self] in
            guard let self else { return }
            appendToFallbackBuffer(data)

            switch activeClient {
            case .remote:
                remoteClient.appendAudioChunk(data)
            case .local:
                if !shouldReplayBufferedAudio {
                    localClient.appendAudioChunk(data)
                }
            case .none:
                break
            }
        }
    }

    func stop() {
        stateQueue.async { [weak self] in
            guard let self else { return }
            stopRequested = true
            switch activeClient {
            case .remote:
                remoteClient.stop()
            case .local:
                localClient.stop()
            case .none:
                finishStoppedSession()
            }
        }
    }

    func cancel() {
        stateQueue.async { [weak self] in
            self?.cancelCurrentSession()
        }
    }

    private func cancelCurrentSession() {
        remoteClient.cancel()
        localClient.cancel()
        activeClient = .none
        configuration = nil
        shouldReplayBufferedAudio = false
        stopRequested = false
        bufferedAudio.removeAll(keepingCapacity: true)
        bufferedAudioBytes = 0
    }

    private func handleRemoteEvent(_ event: RealtimeSpeechEvent) {
        guard activeClient == .remote else { return }

        switch event {
        case .failure:
            if stopRequested {
                remoteClient.cancel()
                finishStoppedSession()
            } else {
                switchToLocalFallback()
            }
        case .final:
            bufferedAudio.removeAll(keepingCapacity: true)
            bufferedAudioBytes = 0
            emit(event)
        case .stopped:
            finishStoppedSession()
        default:
            emit(event)
        }
    }

    private func handleLocalEvent(_ event: RealtimeSpeechEvent) {
        guard activeClient == .local else { return }

        if case .failure = event, stopRequested {
            localClient.cancel()
            finishStoppedSession()
            return
        }
        if case .connected = event, shouldReplayBufferedAudio {
            shouldReplayBufferedAudio = false
            let chunks = bufferedAudio
            chunks.forEach(localClient.appendAudioChunk)
        }
        if case .final = event {
            bufferedAudio.removeAll(keepingCapacity: true)
            bufferedAudioBytes = 0
        }
        if case .stopped = event {
            finishStoppedSession()
            return
        }
        emit(event)
    }

    private func switchToLocalFallback() {
        guard !stopRequested, let configuration else {
            emit(.failure(AppError.speechUnavailable))
            return
        }

        remoteClient.cancel()
        activeClient = .local
        shouldReplayBufferedAudio = true
        localClient.start(configuration: configuration)
    }

    private func finishStoppedSession() {
        activeClient = .none
        configuration = nil
        shouldReplayBufferedAudio = false
        stopRequested = false
        bufferedAudio.removeAll(keepingCapacity: true)
        bufferedAudioBytes = 0
        emit(.stopped)
    }

    private func appendToFallbackBuffer(_ data: Data) {
        bufferedAudio.append(data)
        bufferedAudioBytes += data.count

        while bufferedAudioBytes > fallbackBufferLimit,
              let first = bufferedAudio.first {
            bufferedAudio.removeFirst()
            bufferedAudioBytes -= first.count
        }
    }

    private func emit(_ event: RealtimeSpeechEvent) {
        DispatchQueue.main.async { [weak self] in
            self?.eventHandler?(event)
        }
    }
}
