//
//  DeviceSession.swift
//  HackatonYandex
//
//  Created by Rodion Kholodov.
//

import Foundation

struct DeviceSession: Codable, Equatable {
    let deviceID: String
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date

    func hasUsableAccessToken(
        at date: Date,
        refreshLeeway: TimeInterval
    ) -> Bool {
        expiresAt.timeIntervalSince(date) > refreshLeeway
    }
}
