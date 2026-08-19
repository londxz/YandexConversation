//
//  AppleRealtimeSpeechClient.swift
//  HackatonYandex
//
//  Created by Rodion Kholodov.
//

import AVFoundation
import Foundation
import Speech

final class AppleRealtimeSpeechClient: RealtimeSpeechClient {
    var eventHandler: ((RealtimeSpeechEvent) -> Void)?

    private let stateQueue = DispatchQueue(
        label: "com.rodionkholodov.razgovor.apple-realtime-speech",
        qos: .userInitiated
    )
    private let audioFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )!

    private var configuration: RealtimeSpeechConfiguration?
    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var shouldRun = false
    private var stopping = false
    private var sequence = 0
    private var lastPartialText = ""

    func start(configuration: RealtimeSpeechConfiguration) {
        stateQueue.async { [weak self] in
            guard let self else { return }
            cancelCurrentSession(notify: false)
            self.configuration = configuration
            shouldRun = true
            stopping = false
            sequence = 0
            emit(.connecting)
            authorizeIfNeeded()
        }
    }

    func appendAudioChunk(_ data: Data) {
        guard !data.isEmpty else { return }
        stateQueue.async { [weak self] in
            guard let self,
                  shouldRun,
                  !stopping,
                  let request = recognitionRequest,
                  let buffer = makeAudioBuffer(from: data) else {
                return
            }
            request.append(buffer)
        }
    }

    func stop() {
        stateQueue.async { [weak self] in
            guard let self else { return }
            shouldRun = false
            stopping = true
            guard let request = recognitionRequest else {
                cancelCurrentSession(notify: true)
                return
            }
            request.endAudio()
            stateQueue.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self, stopping else { return }
                cancelCurrentSession(notify: true)
            }
        }
    }

    func cancel() {
        stateQueue.async { [weak self] in
            self?.cancelCurrentSession(notify: false)
        }
    }

    private func authorizeIfNeeded() {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            startRecognitionTask()
        case .notDetermined:
            SFSpeechRecognizer.requestAuthorization { [weak self] status in
                self?.stateQueue.async { [weak self] in
                    guard let self, shouldRun else { return }
                    if status == .authorized {
                        startRecognitionTask()
                    } else {
                        finishWithFailure(AppError.permissionDenied)
                    }
                }
            }
        case .denied, .restricted:
            finishWithFailure(AppError.permissionDenied)
        @unknown default:
            finishWithFailure(AppError.permissionDenied)
        }
    }

    private func startRecognitionTask() {
        guard shouldRun,
              let configuration,
              let recognizer = SFSpeechRecognizer(
                locale: Locale(identifier: configuration.language)
              ) else {
            finishWithFailure(AppError.speechUnavailable)
            return
        }

        if configuration.processingMode == .onDeviceOnly,
           !recognizer.supportsOnDeviceRecognition {
            finishWithFailure(AppError.onDeviceRecognitionUnavailable)
            return
        }
        guard recognizer.isAvailable || recognizer.supportsOnDeviceRecognition else {
            finishWithFailure(AppError.speechUnavailable)
            return
        }

        recognitionTask?.cancel()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.requiresOnDeviceRecognition = configuration.processingMode == .onDeviceOnly
        recognitionRequest = request
        self.recognizer = recognizer
        lastPartialText = ""

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self, weak request] result, error in
            guard let self, let request else { return }
            stateQueue.async {
                guard self.recognitionRequest === request else { return }
                self.handleRecognitionResult(result, error: error)
            }
        }
        emit(.connected)
    }

    private func handleRecognitionResult(
        _ result: SFSpeechRecognitionResult?,
        error: Error?
    ) {
        if let result {
            let text = result.bestTranscription.formattedString
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty, text != lastPartialText {
                lastPartialText = text
                sequence += 1
                let segment = RealtimeSpeechSegment(
                    id: result.isFinal ? UUID().uuidString : nil,
                    sequence: sequence,
                    text: text,
                    speakerId: "speaker_1",
                    speakerLabel: "Говорящий 1",
                    confidence: confidence(from: result.bestTranscription)
                )
                emit(result.isFinal ? .final(segment) : .partial(segment))
            }

            if result.isFinal {
                if stopping {
                    cancelCurrentSession(notify: true)
                } else if shouldRun {
                    startRecognitionTask()
                }
                return
            }
        }

        if let error {
            if stopping {
                cancelCurrentSession(notify: true)
            } else {
                finishWithFailure(mapRecognitionError(error))
            }
        }
    }

    private func makeAudioBuffer(from data: Data) -> AVAudioPCMBuffer? {
        guard data.count.isMultiple(of: MemoryLayout<Int16>.size) else { return nil }
        let frameCount = AVAudioFrameCount(data.count / MemoryLayout<Int16>.size)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(
                pcmFormat: audioFormat,
                frameCapacity: frameCount
              ),
              let channelData = buffer.int16ChannelData else {
            return nil
        }
        buffer.frameLength = frameCount
        data.copyBytes(
            to: UnsafeMutableBufferPointer(
                start: channelData[0],
                count: Int(frameCount)
            )
        )
        return buffer
    }

    private func confidence(from transcription: SFTranscription) -> Double? {
        let segments = transcription.segments
        guard !segments.isEmpty else { return nil }
        return segments.reduce(0) { $0 + Double($1.confidence) } / Double(segments.count)
    }

    private func finishWithFailure(_ error: Error) {
        cancelCurrentSession(notify: false)
        emit(.failure(error))
    }

    private func cancelCurrentSession(notify: Bool) {
        let shouldNotify = notify && (recognitionRequest != nil || stopping)
        shouldRun = false
        stopping = false
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        recognizer = nil
        configuration = nil
        lastPartialText = ""
        if shouldNotify {
            emit(.stopped)
        }
    }

    private func emit(_ event: RealtimeSpeechEvent) {
        DispatchQueue.main.async { [weak self] in
            self?.eventHandler?(event)
        }
    }

    private func mapRecognitionError(_ error: Error) -> Error {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return AppError.networkUnavailable
        }
        return AppError.speechUnavailable
    }
}
