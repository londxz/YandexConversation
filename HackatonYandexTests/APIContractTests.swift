//
//  APIContractTests.swift
//  HackatonYandexTests
//
//  Created by Rodion Kholodov.
//

import XCTest
@testable import HackatonYandex

final class APIContractTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.handler = nil
        super.tearDown()
    }

    func testSpeechTranscriptionRequestAndResponseFollowV1Contract() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        let config = AppConfig(
            environment: .development,
            apiBaseURL: try XCTUnwrap(URL(string: "https://api.example.com")),
            requestTimeout: 5
        )
        let client = APIClient(config: config, urlSession: session)
        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("api-contract-\(UUID().uuidString).wav")
        try Data([0x52, 0x49, 0x46, 0x46]).write(to: audioURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        URLProtocolStub.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/v1/speech/transcribe")
            XCTAssertNotNil(request.value(forHTTPHeaderField: "X-Request-ID"))
            XCTAssertTrue(
                request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true
            )

            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["X-Request-ID": "request-test"]
                )
            )
            let body = Data(
                """
                {
                  "text": "Здравствуйте",
                  "language": "ru-RU",
                  "duration_ms": 1250,
                  "confidence": 0.94
                }
                """.utf8
            )
            return (response, body)
        }

        let result = try await withCheckedThrowingContinuation { continuation in
            client.uploadWavFile(fileURL: audioURL, language: "ru-RU") { result in
                continuation.resume(with: result)
            }
        }

        XCTAssertEqual(result.text, "Здравствуйте")
        XCTAssertEqual(result.language, "ru-RU")
        XCTAssertEqual(result.durationMs, 1250)
        XCTAssertEqual(result.confidence, 0.94)
    }
}

private final class URLProtocolStub: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: AppError.unknown)
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
