//
//  AppleSpeechRecognitionService.swift
//  HackatonYandex
//
//  Created by Rodion Kholodov.
//

import Foundation
import Speech

final class AppleSpeechRecognitionService: SpeechRecognitionService {
    private var activeRequestID: UUID?
    private var recognizer: SFSpeechRecognizer?
    private var recognitionTask: SFSpeechRecognitionTask?

    func transcribeAudio(
        fileURL: URL,
        language: String,
        conversationId: String,
        processingMode: SpeechRecognitionProcessingMode,
        completion: @escaping (Result<SpeechToTextModel, Error>) -> Void
    ) {
        cancelTranscription()

        let requestID = UUID()
        activeRequestID = requestID

        authorizeIfNeeded { [weak self] authorizationResult in
            guard let self, self.activeRequestID == requestID else { return }

            switch authorizationResult {
            case .success:
                self.startRecognition(
                    requestID: requestID,
                    fileURL: fileURL,
                    language: language,
                    processingMode: processingMode,
                    completion: completion
                )
            case .failure(let error):
                self.finish(requestID: requestID, result: .failure(error), completion: completion)
            }
        }
    }

    func cancelTranscription() {
        activeRequestID = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        recognizer = nil
    }

    private func authorizeIfNeeded(
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            completion(.success(()))
        case .notDetermined:
            SFSpeechRecognizer.requestAuthorization { status in
                DispatchQueue.main.async {
                    completion(status == .authorized ? .success(()) : .failure(AppError.permissionDenied))
                }
            }
        case .denied, .restricted:
            completion(.failure(AppError.permissionDenied))
        @unknown default:
            completion(.failure(AppError.permissionDenied))
        }
    }

    private func startRecognition(
        requestID: UUID,
        fileURL: URL,
        language: String,
        processingMode: SpeechRecognitionProcessingMode,
        completion: @escaping (Result<SpeechToTextModel, Error>) -> Void
    ) {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language)) else {
            finish(requestID: requestID, result: .failure(AppError.speechUnavailable), completion: completion)
            return
        }

        let supportsOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        if processingMode == .onDeviceOnly, !supportsOnDeviceRecognition {
            finish(
                requestID: requestID,
                result: .failure(AppError.onDeviceRecognitionUnavailable),
                completion: completion
            )
            return
        }

        guard recognizer.isAvailable || supportsOnDeviceRecognition else {
            finish(requestID: requestID, result: .failure(AppError.speechUnavailable), completion: completion)
            return
        }

        let request = SFSpeechURLRecognitionRequest(url: fileURL)
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = supportsOnDeviceRecognition
        request.addsPunctuation = true

        self.recognizer = recognizer
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self, self.activeRequestID == requestID else { return }

                if let result, result.isFinal {
                    let transcription = result.bestTranscription
                    let segments = transcription.segments
                    let durationMs = segments.last.map {
                        Int((Double($0.timestamp) + Double($0.duration)) * 1_000)
                    }
                    let confidence = segments.isEmpty
                        ? nil
                        : segments.reduce(0.0) { $0 + Double($1.confidence) } / Double(segments.count)
                    let model = SpeechToTextModel(
                        text: transcription.formattedString,
                        language: language,
                        durationMs: durationMs,
                        confidence: confidence
                    )
                    self.finish(requestID: requestID, result: .success(model), completion: completion)
                    return
                }

                if let error {
                    self.finish(
                        requestID: requestID,
                        result: .failure(self.mapRecognitionError(error)),
                        completion: completion
                    )
                }
            }
        }
    }

    private func finish(
        requestID: UUID,
        result: Result<SpeechToTextModel, Error>,
        completion: @escaping (Result<SpeechToTextModel, Error>) -> Void
    ) {
        guard activeRequestID == requestID else { return }

        activeRequestID = nil
        recognitionTask = nil
        recognizer = nil
        completion(result)
    }

    private func mapRecognitionError(_ error: Error) -> Error {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return AppError.networkUnavailable
        }
        return AppError.speechUnavailable
    }
}
