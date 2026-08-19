//
//  BackendFirstSpeechRecognitionService.swift
//  HackatonYandex
//
//  Created by Rodion Kholodov.
//

import Foundation

final class BackendFirstSpeechRecognitionService: SpeechRecognitionService {
    private let remoteService: SpeechRecognitionService
    private let localService: SpeechRecognitionService
    private var activeRequestID: UUID?

    init(
        remoteService: SpeechRecognitionService,
        localService: SpeechRecognitionService
    ) {
        self.remoteService = remoteService
        self.localService = localService
    }

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

        if processingMode == .onDeviceOnly {
            transcribeLocally(
                requestID: requestID,
                fileURL: fileURL,
                language: language,
                conversationId: conversationId,
                processingMode: .onDeviceOnly,
                completion: completion
            )
            return
        }

        remoteService.transcribeAudio(
            fileURL: fileURL,
            language: language,
            conversationId: conversationId,
            processingMode: processingMode
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.activeRequestID == requestID else { return }

                switch result {
                case .success:
                    self.finish(requestID: requestID, result: result, completion: completion)
                case .failure:
                    self.transcribeLocally(
                        requestID: requestID,
                        fileURL: fileURL,
                        language: language,
                        conversationId: conversationId,
                        processingMode: .allowSystemNetworkFallback,
                        completion: completion
                    )
                }
            }
        }
    }

    func cancelTranscription() {
        activeRequestID = nil
        remoteService.cancelTranscription()
        localService.cancelTranscription()
    }

    private func transcribeLocally(
        requestID: UUID,
        fileURL: URL,
        language: String,
        conversationId: String,
        processingMode: SpeechRecognitionProcessingMode,
        completion: @escaping (Result<SpeechToTextModel, Error>) -> Void
    ) {
        localService.transcribeAudio(
            fileURL: fileURL,
            language: language,
            conversationId: conversationId,
            processingMode: processingMode
        ) { [weak self] result in
            DispatchQueue.main.async {
                self?.finish(requestID: requestID, result: result, completion: completion)
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
        completion(result)
    }
}
