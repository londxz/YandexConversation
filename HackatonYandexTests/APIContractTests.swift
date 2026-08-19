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
        let conversationId = "682e61f1-d211-4a20-8b5c-48a164bc4043"
        let transport = HTTPTransportStub { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/v1/speech/transcribe")
            XCTAssertNotNil(request.value(forHTTPHeaderField: "X-Request-ID"))
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Authorization"),
                "Bearer access-token"
            )
            XCTAssertTrue(
                request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true
            )

            let body = String(
                decoding: try XCTUnwrap(request.httpBody),
                as: UTF8.self
            )
            XCTAssertTrue(body.contains("name=\"language\"\r\n\r\nru-RU"))
            XCTAssertTrue(body.contains("name=\"conversation_id\"\r\n\r\n\(conversationId)"))
            XCTAssertTrue(body.contains("name=\"file\"; filename="))

            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["X-Request-ID": "request-test"]
                )
            )
            let responseBody = Data(
                """
                {
                  "text": "Здравствуйте",
                  "language": "ru-RU",
                  "duration_ms": 1250,
                  "confidence": 0.94
                }
                """.utf8
            )
            return (responseBody, response)
        }
        let client = APIClient(
            httpClient: HTTPClient(config: makeConfig(), transport: transport),
            deviceSessionRepository: DeviceSessionRepositoryStub(
                accessToken: "access-token",
                refreshedAccessToken: "fresh-access-token"
            )
        )
        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("api-contract-\(UUID().uuidString).wav")
        try Data([0x52, 0x49, 0x46, 0x46]).write(to: audioURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let result = try await withCheckedThrowingContinuation { continuation in
            client.uploadWavFile(
                fileURL: audioURL,
                language: "ru-RU",
                conversationId: conversationId
            ) { result in
                continuation.resume(with: result)
            }
        }

        XCTAssertEqual(result.text, "Здравствуйте")
        XCTAssertEqual(result.language, "ru-RU")
        XCTAssertEqual(result.durationMs, 1250)
        XCTAssertEqual(result.confidence, 0.94)
    }

    func testDeviceRegistrationRequestAndResponseFollowV1Contract() async throws {
        let config = makeConfig()
        let transport = HTTPTransportStub { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/v1/devices/register")
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Idempotency-Key"),
                "registration-idempotency-key"
            )
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Content-Type"),
                "application/json"
            )

            let body = try XCTUnwrap(request.httpBody)
            let json = try XCTUnwrap(
                JSONSerialization.jsonObject(with: body) as? [String: String]
            )
            XCTAssertEqual(json["platform"], "ios")
            XCTAssertEqual(json["app_version"], "1.2.3")
            XCTAssertEqual(json["locale"], "ru-RU")

            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 201,
                httpVersion: nil,
                headerFields: nil
            ))
            let responseBody = Data(
                """
                {
                  "device_id": "682e61f1-d211-4a20-8b5c-48a164bc4043",
                  "access_token": "access-token",
                  "refresh_token": "refresh-token",
                  "expires_at": "2026-08-19T18:00:00.123Z"
                }
                """.utf8
            )
            return (responseBody, response)
        }
        let httpClient = HTTPClient(config: config, transport: transport)
        let remoteDataSource = DefaultDeviceSessionRemoteDataSource(
            httpClient: httpClient,
            metadataProvider: DeviceMetadataStub(
                appVersion: "1.2.3",
                locale: "ru-RU"
            )
        )

        let deviceSession = try await remoteDataSource.register(
            idempotencyKey: "registration-idempotency-key"
        )

        XCTAssertEqual(
            deviceSession.deviceID,
            "682e61f1-d211-4a20-8b5c-48a164bc4043"
        )
        XCTAssertEqual(deviceSession.accessToken, "access-token")
        XCTAssertEqual(deviceSession.refreshToken, "refresh-token")
    }

    func testAuthorizedRequestRefreshesOnceAfterUnauthorizedResponse() async throws {
        let session = makeStubbedURLSession()
        let repository = DeviceSessionRepositoryStub(
            accessToken: "expired-access-token",
            refreshedAccessToken: "fresh-access-token"
        )
        let client = APIClient(
            httpClient: HTTPClient(config: makeConfig(), urlSession: session),
            deviceSessionRepository: repository
        )
        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("authorized-api-contract-\(UUID().uuidString).wav")
        try Data([0x52, 0x49, 0x46, 0x46]).write(to: audioURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let requestCounter = LockedCounter()
        URLProtocolStub.handler = { request in
            let attempt = requestCounter.increment()
            let expectedToken = attempt == 1
                ? "expired-access-token"
                : "fresh-access-token"
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Authorization"),
                "Bearer \(expectedToken)"
            )

            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: attempt == 1 ? 401 : 200,
                httpVersion: nil,
                headerFields: nil
            ))
            if attempt == 1 {
                return (
                    response,
                    Data(
                        """
                        {
                          "error": {
                            "code": "invalid_credentials",
                            "message": "Credentials are expired.",
                            "request_id": "request-auth"
                          }
                        }
                        """.utf8
                    )
                )
            }
            return (
                response,
                Data(
                    """
                    {
                      "text": "Здравствуйте",
                      "language": "ru-RU",
                      "duration_ms": 800,
                      "confidence": 0.9
                    }
                    """.utf8
                )
            )
        }

        let result = try await withCheckedThrowingContinuation { continuation in
            client.uploadWavFile(
                fileURL: audioURL,
                language: "ru-RU",
                conversationId: "682e61f1-d211-4a20-8b5c-48a164bc4043"
            ) { result in
                continuation.resume(with: result)
            }
        }

        XCTAssertEqual(result.text, "Здравствуйте")
        XCTAssertEqual(requestCounter.value, 2)
        let refreshArguments = await repository.recordedRejectedTokens()
        XCTAssertEqual(refreshArguments, ["expired-access-token"])
    }

    private func makeConfig() -> AppConfig {
        AppConfig(
            environment: .development,
            apiBaseURL: URL(string: "https://api.example.com")!,
            requestTimeout: 5
        )
    }

    private func makeStubbedURLSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: configuration)
    }

}

private struct DeviceMetadataStub: DeviceMetadataProviding {
    let appVersion: String
    let locale: String
}

private actor DeviceSessionRepositoryStub: DeviceSessionRepository {
    private let initialAccessToken: String
    private let refreshedAccessToken: String
    private var rejectedTokens: [String] = []

    init(accessToken: String, refreshedAccessToken: String) {
        initialAccessToken = accessToken
        self.refreshedAccessToken = refreshedAccessToken
    }

    func session() async throws -> DeviceSession {
        DeviceSession(
            deviceID: UUID().uuidString,
            accessToken: initialAccessToken,
            refreshToken: "refresh-token",
            expiresAt: Date().addingTimeInterval(3_600)
        )
    }

    func accessToken() async throws -> String {
        initialAccessToken
    }

    func refreshAccessToken(rejectedAccessToken: String) async throws -> String {
        rejectedTokens.append(rejectedAccessToken)
        return refreshedAccessToken
    }

    func deleteRemoteSession() async throws {}

    func recordedRejectedTokens() -> [String] {
        rejectedTokens
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }

    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        storedValue += 1
        return storedValue
    }
}

private final class HTTPTransportStub: HTTPTransport {
    private let handler: (URLRequest) throws -> (Data, URLResponse)

    init(handler: @escaping (URLRequest) throws -> (Data, URLResponse)) {
        self.handler = handler
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try handler(request)
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
