//
//  HTTPClient.swift
//  HackatonYandex
//
//  Created by Rodion Kholodov.
//

import Foundation

struct HTTPClientResponse {
    let data: Data
    let response: HTTPURLResponse
}

final class HTTPClient {
    private let config: AppConfig
    private let urlSession: URLSession
    private let decoder: JSONDecoder

    init(
        config: AppConfig,
        urlSession: URLSession = .shared,
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.config = config
        self.urlSession = urlSession
        self.decoder = decoder
    }

    func makeRequest(
        path: String,
        method: String,
        headers: [String: String] = [:],
        body: Data? = nil
    ) -> URLRequest {
        let url = config.apiBaseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = config.requestTimeout
        request.httpBody = body
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-ID")
        headers.forEach { field, value in
            request.setValue(value, forHTTPHeaderField: field)
        }
        return request
    }

    func send(_ request: URLRequest) async throws -> HTTPClientResponse {
        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AppError.unknown
            }
            return HTTPClientResponse(data: data, response: httpResponse)
        } catch let error as AppError {
            throw error
        } catch let error as URLError where Self.isConnectivityError(error) {
            throw AppError.networkUnavailable
        } catch {
            throw error
        }
    }

    func successfulData(from result: HTTPClientResponse) throws -> Data {
        guard (200...299).contains(result.response.statusCode) else {
            throw apiError(from: result)
        }
        return result.data
    }

    func decode<Response: Decodable>(
        _ type: Response.Type,
        from data: Data
    ) throws -> Response {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            AppLogger.error("Failed to decode API response")
            throw AppError.decodingFailed
        }
    }

    func apiError(from result: HTTPClientResponse) -> AppError {
        guard let apiError = try? decoder.decode(APIErrorEnvelope.self, from: result.data) else {
            return .serverError(statusCode: result.response.statusCode)
        }

        return .apiError(
            code: apiError.error.code,
            message: apiError.error.message,
            requestID: apiError.error.requestID
                ?? result.response.value(forHTTPHeaderField: "X-Request-ID")
        )
    }

    private static func isConnectivityError(_ error: URLError) -> Bool {
        switch error.code {
        case .notConnectedToInternet,
             .networkConnectionLost,
             .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed,
             .timedOut:
            return true
        default:
            return false
        }
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
