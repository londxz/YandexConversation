//
//  DeviceSessionRepositoryTests.swift
//  HackatonYandexTests
//
//  Created by Rodion Kholodov.
//

import XCTest
@testable import HackatonYandex

final class DeviceSessionRepositoryTests: XCTestCase {
    func testConcurrentTokenRequestsShareOneRegistration() async throws {
        let expectedSession = makeSession(accessToken: "access-token")
        let store = InMemoryDeviceSessionStore()
        let remote = DeviceSessionRemoteStub(
            registerResult: .success(expectedSession),
            operationDelayNanoseconds: 50_000_000
        )
        let repository = DefaultDeviceSessionRepository(
            store: store,
            remoteDataSource: remote
        )

        async let firstToken = repository.accessToken()
        async let secondToken = repository.accessToken()
        let tokens = try await (firstToken, secondToken)
        let registerCallCount = await remote.registerCallCount()

        XCTAssertEqual(tokens.0, "access-token")
        XCTAssertEqual(tokens.1, "access-token")
        XCTAssertEqual(registerCallCount, 1)
    }

    func testFailedRegistrationRetriesWithSameIdempotencyKeyAfterRestart() async throws {
        let store = InMemoryDeviceSessionStore()
        let failingRemote = DeviceSessionRemoteStub(
            registerResult: .failure(AppError.networkUnavailable)
        )
        let firstRepository = DefaultDeviceSessionRepository(
            store: store,
            remoteDataSource: failingRemote
        )

        do {
            _ = try await firstRepository.session()
            XCTFail("Registration should fail while the network is unavailable")
        } catch {
            XCTAssertEqual(error as? AppError, .networkUnavailable)
        }

        let pendingKey = try XCTUnwrap(
            store.loadState()?.pendingOperation?.idempotencyKey
        )
        let recoveredSession = makeSession(accessToken: "recovered-token")
        let recoveredRemote = DeviceSessionRemoteStub(
            registerResult: .success(recoveredSession)
        )
        let restartedRepository = DefaultDeviceSessionRepository(
            store: store,
            remoteDataSource: recoveredRemote
        )

        let session = try await restartedRepository.session()
        let registrationKeys = await recoveredRemote.registrationKeys()

        XCTAssertEqual(session, recoveredSession)
        XCTAssertEqual(registrationKeys, [pendingKey])
        XCTAssertNil(store.currentState?.pendingOperation)
    }

    func testConcurrentUnauthorizedResponsesRotateTokensOnce() async throws {
        let oldSession = makeSession(accessToken: "old-access-token")
        let refreshedSession = makeSession(accessToken: "new-access-token")
        let store = InMemoryDeviceSessionStore(
            state: StoredDeviceSessionState(
                session: oldSession,
                pendingOperation: nil
            )
        )
        let remote = DeviceSessionRemoteStub(
            registerResult: .failure(AppError.unknown),
            refreshResult: .success(refreshedSession),
            operationDelayNanoseconds: 50_000_000
        )
        let repository = DefaultDeviceSessionRepository(
            store: store,
            remoteDataSource: remote
        )

        async let firstToken = repository.refreshAccessToken(
            rejectedAccessToken: "old-access-token"
        )
        async let secondToken = repository.refreshAccessToken(
            rejectedAccessToken: "old-access-token"
        )
        let tokens = try await (firstToken, secondToken)
        let refreshCallCount = await remote.refreshCallCount()

        XCTAssertEqual(tokens.0, "new-access-token")
        XCTAssertEqual(tokens.1, "new-access-token")
        XCTAssertEqual(refreshCallCount, 1)
        XCTAssertEqual(store.currentState?.session, refreshedSession)
    }

    private func makeSession(accessToken: String) -> DeviceSession {
        DeviceSession(
            deviceID: "682e61f1-d211-4a20-8b5c-48a164bc4043",
            accessToken: accessToken,
            refreshToken: "refresh-\(accessToken)",
            expiresAt: Date(timeIntervalSince1970: 2_000_000_000)
        )
    }
}

private final class InMemoryDeviceSessionStore: DeviceSessionStateStoring {
    private(set) var currentState: StoredDeviceSessionState?

    init(state: StoredDeviceSessionState? = nil) {
        currentState = state
    }

    func loadState() throws -> StoredDeviceSessionState? {
        currentState
    }

    func saveState(_ state: StoredDeviceSessionState) throws {
        currentState = state
    }

    func deleteState() throws {
        currentState = nil
    }
}

private actor DeviceSessionRemoteStub: DeviceSessionRemoteDataSource {
    private let registerResult: Result<DeviceSession, Error>
    private let refreshResult: Result<DeviceSession, Error>
    private let operationDelayNanoseconds: UInt64
    private var storedRegistrationKeys: [String] = []
    private var storedRefreshCallCount = 0

    init(
        registerResult: Result<DeviceSession, Error>,
        refreshResult: Result<DeviceSession, Error> = .failure(AppError.unknown),
        operationDelayNanoseconds: UInt64 = 0
    ) {
        self.registerResult = registerResult
        self.refreshResult = refreshResult
        self.operationDelayNanoseconds = operationDelayNanoseconds
    }

    func register(idempotencyKey: String) async throws -> DeviceSession {
        storedRegistrationKeys.append(idempotencyKey)
        try await delayIfNeeded()
        return try registerResult.get()
    }

    func refresh(
        deviceID: String,
        refreshToken: String,
        idempotencyKey: String
    ) async throws -> DeviceSession {
        storedRefreshCallCount += 1
        try await delayIfNeeded()
        return try refreshResult.get()
    }

    func delete(deviceID: String, accessToken: String) async throws {}

    func registerCallCount() -> Int {
        storedRegistrationKeys.count
    }

    func registrationKeys() -> [String] {
        storedRegistrationKeys
    }

    func refreshCallCount() -> Int {
        storedRefreshCallCount
    }

    private func delayIfNeeded() async throws {
        guard operationDelayNanoseconds > 0 else { return }
        try await Task.sleep(nanoseconds: operationDelayNanoseconds)
    }
}
