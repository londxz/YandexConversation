//
//  DefaultDeviceSessionRepository.swift
//  HackatonYandex
//
//  Created by Rodion Kholodov.
//

import Foundation

actor DefaultDeviceSessionRepository: DeviceSessionRepository {
    private let store: DeviceSessionStateStoring
    private let remoteDataSource: DeviceSessionRemoteDataSource
    private let refreshLeeway: TimeInterval
    private let now: () -> Date

    private var cachedState: StoredDeviceSessionState?
    private var hasLoadedState = false
    private var networkTask: Task<DeviceSession, Error>?

    init(
        store: DeviceSessionStateStoring,
        remoteDataSource: DeviceSessionRemoteDataSource,
        refreshLeeway: TimeInterval = 30,
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.remoteDataSource = remoteDataSource
        self.refreshLeeway = refreshLeeway
        self.now = now
    }

    func session() async throws -> DeviceSession {
        let state = try loadState()
        if state.pendingOperation == nil,
           let session = state.session,
           session.hasUsableAccessToken(at: now(), refreshLeeway: refreshLeeway) {
            return session
        }
        return try await resolveSession(rejectedAccessToken: nil)
    }

    func accessToken() async throws -> String {
        let activeSession = try await session()
        return activeSession.accessToken
    }

    func refreshAccessToken(rejectedAccessToken: String) async throws -> String {
        let state = try loadState()
        if state.pendingOperation == nil,
           let session = state.session,
           session.accessToken != rejectedAccessToken,
           session.hasUsableAccessToken(at: now(), refreshLeeway: refreshLeeway) {
            return session.accessToken
        }

        let refreshed = try await resolveSession(
            rejectedAccessToken: rejectedAccessToken
        )
        return refreshed.accessToken
    }

    func deleteRemoteSession() async throws {
        let state = try loadState()
        guard state.session != nil || state.pendingOperation != nil else {
            return
        }

        let activeSession = try await session()
        try await remoteDataSource.delete(
            deviceID: activeSession.deviceID,
            accessToken: activeSession.accessToken
        )

        try deleteState()
    }

    private func resolveSession(
        rejectedAccessToken: String?
    ) async throws -> DeviceSession {
        if let networkTask {
            return try await networkTask.value
        }

        let task = Task { [weak self] () throws -> DeviceSession in
            guard let self else {
                throw AppError.unknown
            }
            return try await self.performResolution(
                rejectedAccessToken: rejectedAccessToken
            )
        }
        networkTask = task

        do {
            let session = try await task.value
            networkTask = nil
            return session
        } catch {
            networkTask = nil
            throw error
        }
    }

    private func performResolution(
        rejectedAccessToken: String?
    ) async throws -> DeviceSession {
        var state = try loadState()

        if let pendingOperation = state.pendingOperation {
            return try await execute(pendingOperation)
        }

        if let session = state.session {
            if let rejectedAccessToken,
               session.accessToken != rejectedAccessToken,
               session.hasUsableAccessToken(at: now(), refreshLeeway: refreshLeeway) {
                return session
            }

            let operation = PendingDeviceSessionOperation.refresh(
                idempotencyKey: UUID().uuidString,
                session: session
            )
            state.pendingOperation = operation
            try saveState(state)
            return try await execute(operation)
        }

        let operation = PendingDeviceSessionOperation.registration(
            idempotencyKey: UUID().uuidString
        )
        state.pendingOperation = operation
        try saveState(state)
        return try await execute(operation)
    }

    private func execute(
        _ operation: PendingDeviceSessionOperation
    ) async throws -> DeviceSession {
        switch operation.kind {
        case .register:
            let session = try await remoteDataSource.register(
                idempotencyKey: operation.idempotencyKey
            )
            try saveState(StoredDeviceSessionState(
                session: session,
                pendingOperation: nil
            ))
            return session

        case .refresh:
            guard let deviceID = operation.deviceID,
                  let refreshToken = operation.refreshToken else {
                try deleteState()
                return try await performResolution(rejectedAccessToken: nil)
            }

            do {
                let session = try await remoteDataSource.refresh(
                    deviceID: deviceID,
                    refreshToken: refreshToken,
                    idempotencyKey: operation.idempotencyKey
                )
                try saveState(StoredDeviceSessionState(
                    session: session,
                    pendingOperation: nil
                ))
                return session
            } catch let error as AppError where error.isInvalidCredentials {
                var resetState = StoredDeviceSessionState.empty
                let registration = PendingDeviceSessionOperation.registration(
                    idempotencyKey: UUID().uuidString
                )
                resetState.pendingOperation = registration
                try saveState(resetState)
                return try await execute(registration)
            }
        }
    }

    private func loadState() throws -> StoredDeviceSessionState {
        if hasLoadedState {
            return cachedState ?? .empty
        }

        do {
            let state = try store.loadState() ?? .empty
            cachedState = state
            hasLoadedState = true
            return state
        } catch DeviceSessionStoreError.corruptedData {
            do {
                try store.deleteState()
            } catch {
                throw AppError.secureStorageUnavailable
            }
            cachedState = .empty
            hasLoadedState = true
            return .empty
        } catch {
            throw AppError.secureStorageUnavailable
        }
    }

    private func saveState(_ state: StoredDeviceSessionState) throws {
        do {
            try store.saveState(state)
            cachedState = state
            hasLoadedState = true
        } catch {
            throw AppError.secureStorageUnavailable
        }
    }

    private func deleteState() throws {
        do {
            try store.deleteState()
            cachedState = .empty
            hasLoadedState = true
        } catch {
            throw AppError.secureStorageUnavailable
        }
    }
}

private extension AppError {
    var isInvalidCredentials: Bool {
        guard case .apiError(let code, _, _) = self else {
            return false
        }
        return code == "invalid_credentials"
    }
}
