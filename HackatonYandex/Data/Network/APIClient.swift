//
//  APIClient.swift
//  HackatonYandex
//
//  Created by Rodion Kholodov.
//

import Foundation

final class APIClient {
    private enum Endpoint {
        static let speechTranscribe = "v1/speech/transcribe"
    }

    private let httpClient: HTTPClient
    private let deviceSessionRepository: DeviceSessionRepository

    init(
        httpClient: HTTPClient,
        deviceSessionRepository: DeviceSessionRepository
    ) {
        self.httpClient = httpClient
        self.deviceSessionRepository = deviceSessionRepository
    }

    func uploadWavFile(
        fileURL: URL,
        language: String,
        completion: @escaping (Result<SpeechToTextModel, Error>) -> Void
    ) {
        Task {
            do {
                let response = try await uploadWavFile(
                    fileURL: fileURL,
                    language: language
                )
                completion(.success(response))
            } catch {
                completion(.failure(error))
            }
        }
    }

    private func uploadWavFile(
        fileURL: URL,
        language: String
    ) async throws -> SpeechToTextModel {
        let boundary = UUID().uuidString
        var data = Data()
        appendMultipartField(
            name: "language",
            value: language,
            boundary: boundary,
            to: &data
        )
        appendMultipartFileHeader(
            fieldName: "file",
            filename: fileURL.lastPathComponent,
            contentType: "audio/wav",
            boundary: boundary,
            to: &data
        )
        data.append(try Data(contentsOf: fileURL))
        data.append("\r\n".data(using: .utf8)!)
        data.append("--\(boundary)--\r\n".data(using: .utf8)!)

        let request = httpClient.makeRequest(
            path: Endpoint.speechTranscribe,
            method: "POST",
            headers: [
                "Content-Type": "multipart/form-data; boundary=\(boundary)"
            ],
            body: data
        )
        let responseData = try await sendAuthorized(request)
        return try httpClient.decode(SpeechToTextModel.self, from: responseData)
    }

    private func sendAuthorized(_ originalRequest: URLRequest) async throws -> Data {
        let accessToken = try await deviceSessionRepository.accessToken()
        var request = originalRequest
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        var result = try await httpClient.send(request)
        if result.response.statusCode == 401 {
            let refreshedToken = try await deviceSessionRepository.refreshAccessToken(
                rejectedAccessToken: accessToken
            )
            request.setValue(
                "Bearer \(refreshedToken)",
                forHTTPHeaderField: "Authorization"
            )
            result = try await httpClient.send(request)
        }
        return try httpClient.successfulData(from: result)
    }

    private func appendMultipartField(
        name: String,
        value: String,
        boundary: String,
        to data: inout Data
    ) {
        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append(
            "Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n"
                .data(using: .utf8)!
        )
        data.append("\(value)\r\n".data(using: .utf8)!)
    }

    private func appendMultipartFileHeader(
        fieldName: String,
        filename: String,
        contentType: String,
        boundary: String,
        to data: inout Data
    ) {
        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append(
            "Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(filename)\"\r\n"
                .data(using: .utf8)!
        )
        data.append("Content-Type: \(contentType)\r\n\r\n".data(using: .utf8)!)
    }
}
