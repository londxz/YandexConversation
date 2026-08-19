//
//  RemoteSpeechRecognitionService.swift
//  HackatonYandex
//
//  Created by Rodion Kholodov.
//

import Foundation

final class RemoteSpeechRecognitionService: SpeechRecognitionService {
    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func transcribeAudio(
        fileURL: URL,
        language: String,
        completion: @escaping (Result<SpeechToTextModel, Error>) -> Void
    ) {
        apiClient.uploadWavFile(
            fileURL: fileURL,
            language: language,
            completion: completion
        )
    }
}
