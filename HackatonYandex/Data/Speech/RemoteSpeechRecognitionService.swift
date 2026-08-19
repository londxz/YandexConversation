//
//  RemoteSpeechRecognitionService.swift
//  HackatonYandex
//
//  Created by Rodion Kholodov.
//

import Foundation

final class RemoteSpeechRecognitionService: SpeechRecognitionService {
    private let apiClient: APIClient
    private var transcriptionTask: Task<Void, Never>?

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func transcribeAudio(
        fileURL: URL,
        language: String,
        conversationId: String,
        processingMode: SpeechRecognitionProcessingMode,
        completion: @escaping (Result<SpeechToTextModel, Error>) -> Void
    ) {
        transcriptionTask?.cancel()
        transcriptionTask = apiClient.uploadWavFile(
            fileURL: fileURL,
            language: language,
            conversationId: conversationId,
            completion: completion
        )
    }

    func cancelTranscription() {
        transcriptionTask?.cancel()
        transcriptionTask = nil
    }
}
