//
//  KeychainDeviceSessionStore.swift
//  HackatonYandex
//
//  Created by Rodion Kholodov.
//

import Foundation
import Security

struct StoredDeviceSessionState: Codable, Equatable {
    var session: DeviceSession?
    var pendingOperation: PendingDeviceSessionOperation?

    static let empty = StoredDeviceSessionState(
        session: nil,
        pendingOperation: nil
    )
}

struct PendingDeviceSessionOperation: Codable, Equatable {
    enum Kind: String, Codable {
        case register
        case refresh
    }

    let kind: Kind
    let idempotencyKey: String
    let deviceID: String?
    let refreshToken: String?

    static func registration(idempotencyKey: String) -> PendingDeviceSessionOperation {
        PendingDeviceSessionOperation(
            kind: .register,
            idempotencyKey: idempotencyKey,
            deviceID: nil,
            refreshToken: nil
        )
    }

    static func refresh(
        idempotencyKey: String,
        session: DeviceSession
    ) -> PendingDeviceSessionOperation {
        PendingDeviceSessionOperation(
            kind: .refresh,
            idempotencyKey: idempotencyKey,
            deviceID: session.deviceID,
            refreshToken: session.refreshToken
        )
    }
}

protocol DeviceSessionStateStoring {
    func loadState() throws -> StoredDeviceSessionState?
    func saveState(_ state: StoredDeviceSessionState) throws
    func deleteState() throws
}

enum DeviceSessionStoreError: Error, Equatable {
    case corruptedData
    case keychainFailure(status: OSStatus)
}

final class KeychainDeviceSessionStore: DeviceSessionStateStoring {
    private let service: String
    private let account: String
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        service: String = (Bundle.main.bundleIdentifier ?? "HackatonYandex") + ".device-session",
        account: String = "device-session-state-v1",
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.service = service
        self.account = account
        self.encoder = encoder
        self.decoder = decoder
    }

    func loadState() throws -> StoredDeviceSessionState? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw DeviceSessionStoreError.keychainFailure(status: status)
        }
        guard let data = item as? Data,
              let state = try? decoder.decode(StoredDeviceSessionState.self, from: data) else {
            throw DeviceSessionStoreError.corruptedData
        }
        return state
    }

    func saveState(_ state: StoredDeviceSessionState) throws {
        let data: Data
        do {
            data = try encoder.encode(state)
        } catch {
            throw DeviceSessionStoreError.corruptedData
        }

        let attributes = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            attributes as CFDictionary
        )
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw DeviceSessionStoreError.keychainFailure(status: updateStatus)
        }

        var insert = baseQuery
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let insertStatus = SecItemAdd(insert as CFDictionary, nil)
        guard insertStatus == errSecSuccess else {
            throw DeviceSessionStoreError.keychainFailure(status: insertStatus)
        }
    }

    func deleteState() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw DeviceSessionStoreError.keychainFailure(status: status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false
        ]
    }
}
