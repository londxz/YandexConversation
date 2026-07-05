//
//  APIClient.swift
//  HackatonYandex
//
//  Created by Родион Холодов on 02.06.2025.
//
import Foundation

final class APIClient {
    private enum Endpoint {
        static let speechTranscribe = "v1/speech/transcribe"
    }

    private let config: AppConfig
    private let urlSession: URLSession
    private let decoder: JSONDecoder
    private let requestQueue: DispatchQueue

    init(
        config: AppConfig = .makeDefault(),
        urlSession: URLSession = .shared,
        decoder: JSONDecoder = JSONDecoder(),
        requestQueue: DispatchQueue = DispatchQueue(label: "app.api-client.request", qos: .userInitiated)
    ) {
        self.config = config
        self.urlSession = urlSession
        self.decoder = decoder
        self.requestQueue = requestQueue
    }

    func uploadWavFile(fileURL: URL, completion: @escaping (Result<SpeechToTextModel, Error>) -> Void) {
        requestQueue.async {
            self.performUploadWavFile(fileURL: fileURL, completion: completion)
        }
    }

    private func performUploadWavFile(
        fileURL: URL,
        completion: @escaping (Result<SpeechToTextModel, Error>) -> Void
    ) {
        let url = config.apiBaseURL.appendingPathComponent(Endpoint.speechTranscribe)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = config.requestTimeout
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-ID")

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var data = Data()
        appendMultipartField(name: "language", value: "ru-RU", boundary: boundary, to: &data)
        appendMultipartFileHeader(
            fieldName: "file",
            filename: fileURL.lastPathComponent,
            contentType: "audio/wav",
            boundary: boundary,
            to: &data
        )

        do {
            let fileData = try Data(contentsOf: fileURL)
            data.append(fileData)
        } catch {
            completion(.failure(error))
            return
        }

        data.append("\r\n".data(using: .utf8)!)
        data.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = data

        let task = urlSession.dataTask(with: request) { responseData, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(AppError.unknown))
                return
            }

            if !(200...299).contains(httpResponse.statusCode) {
                completion(.failure(self.decodeAPIError(from: responseData, response: httpResponse)))
                return
            }

            guard let responseData = responseData else {
                completion(.failure(AppError.emptyResponse))
                return
            }

            do {
                let model = try self.decoder.decode(SpeechToTextModel.self, from: responseData)
                completion(.success(model))
            } catch {
                AppLogger.error("Decode error: \(error.localizedDescription)")
                completion(.failure(AppError.decodingFailed))
            }
        }

        task.resume()
    }

    private func appendMultipartField(name: String, value: String, boundary: String, to data: inout Data) {
        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
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

    private func decodeAPIError(from data: Data?, response: HTTPURLResponse) -> AppError {
        guard let data,
              let apiError = try? decoder.decode(APIErrorEnvelope.self, from: data) else {
            return .serverError(statusCode: response.statusCode)
        }

        return .apiError(
            code: apiError.error.code,
            message: apiError.error.message,
            requestID: apiError.error.requestID ?? response.value(forHTTPHeaderField: "X-Request-ID")
        )
    }
}

private struct APIErrorEnvelope: Decodable {
    let error: APIErrorPayload
}

private struct APIErrorPayload: Decodable {
    let code: String
    let message: String
    let requestID: String?

    enum CodingKeys: String, CodingKey {
        case code
        case message
        case requestID = "request_id"
    }
}
