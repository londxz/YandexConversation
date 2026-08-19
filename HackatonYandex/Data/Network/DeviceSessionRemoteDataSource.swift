//
//  DeviceSessionRemoteDataSource.swift
//  HackatonYandex
//
//  Created by Rodion Kholodov.
//

import Foundation

protocol DeviceSessionRemoteDataSource: AnyObject {
    func register(idempotencyKey: String) async throws -> DeviceSession
    func refresh(
        deviceID: String,
        refreshToken: String,
        idempotencyKey: String
    ) async throws -> DeviceSession
    func delete(deviceID: String, accessToken: String) async throws
}

protocol DeviceMetadataProviding {
    var appVersion: String { get }
    var locale: String { get }
}

struct DefaultDeviceMetadataProvider: DeviceMetadataProviding {
    let appVersion: String
    let locale: String

    init(
        bundle: Bundle = .main,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) {
        appVersion = bundle.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0.0.0"
        locale = (preferredLanguages.first ?? "ru-RU")
            .replacingOccurrences(of: "_", with: "-")
    }
}

final class DefaultDeviceSessionRemoteDataSource: DeviceSessionRemoteDataSource {
    private enum Endpoint {
        static let register = "v1/devices/register"
        static let refresh = "v1/devices/refresh"

        static func device(_ deviceID: String) -> String {
            "v1/devices/\(deviceID)"
        }
    }

    private let httpClient: HTTPClient
    private let metadataProvider: DeviceMetadataProviding
    private let encoder: JSONEncoder

    init(
        httpClient: HTTPClient,
        metadataProvider: DeviceMetadataProviding = DefaultDeviceMetadataProvider(),
        encoder: JSONEncoder = JSONEncoder()
    ) {
        self.httpClient = httpClient
        self.metadataProvider = metadataProvider
        self.encoder = encoder
    }

    func register(idempotencyKey: String) async throws -> DeviceSession {
        let body = try encoder.encode(RegisterDeviceRequest(
            platform: "ios",
            appVersion: metadataProvider.appVersion,
            locale: metadataProvider.locale
        ))
        let request = httpClient.makeRequest(
            path: Endpoint.register,
            method: "POST",
            headers: jsonHeaders(idempotencyKey: idempotencyKey),
            body: body
        )
        return try await sendSessionRequest(request)
    }

    func refresh(
        deviceID: String,
        refreshToken: String,
        idempotencyKey: String
    ) async throws -> DeviceSession {
        let body = try encoder.encode(RefreshDeviceSessionRequest(
            deviceID: deviceID,
            refreshToken: refreshToken
        ))
        let request = httpClient.makeRequest(
            path: Endpoint.refresh,
            method: "POST",
            headers: jsonHeaders(idempotencyKey: idempotencyKey),
            body: body
        )
        return try await sendSessionRequest(request)
    }

    func delete(deviceID: String, accessToken: String) async throws {
        let request = httpClient.makeRequest(
            path: Endpoint.device(deviceID),
            method: "DELETE",
            headers: ["Authorization": "Bearer \(accessToken)"]
        )
        let result = try await httpClient.send(request)
        _ = try httpClient.successfulData(from: result)
    }

    private func sendSessionRequest(_ request: URLRequest) async throws -> DeviceSession {
        let result = try await httpClient.send(request)
        let data = try httpClient.successfulData(from: result)
        let response = try httpClient.decode(DeviceSessionResponse.self, from: data)
        return try response.domainModel()
    }

    private func jsonHeaders(idempotencyKey: String) -> [String: String] {
        [
            "Content-Type": "application/json",
            "Idempotency-Key": idempotencyKey
        ]
    }
}

private struct RegisterDeviceRequest: Encodable {
    let platform: String
    let appVersion: String
    let locale: String

    enum CodingKeys: String, CodingKey {
        case platform
        case appVersion = "app_version"
        case locale
    }
}

private struct RefreshDeviceSessionRequest: Encodable {
    let deviceID: String
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case deviceID = "device_id"
        case refreshToken = "refresh_token"
    }
}

private struct DeviceSessionResponse: Decodable {
    let deviceID: String
    let accessToken: String
    let refreshToken: String
    let expiresAt: String

    enum CodingKeys: String, CodingKey {
        case deviceID = "device_id"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresAt = "expires_at"
    }

    func domainModel() throws -> DeviceSession {
        guard let expirationDate = Self.parseDate(expiresAt) else {
            throw AppError.decodingFailed
        }
        return DeviceSession(
            deviceID: deviceID,
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expirationDate
        )
    }

    private static func parseDate(_ value: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: value) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
