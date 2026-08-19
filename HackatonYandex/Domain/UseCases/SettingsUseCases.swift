//
//  SettingsUseCases.swift
//  HackatonYandex
//
//  Created by Rodion Kholodov.
//

import Foundation

struct FetchSettingsUseCase {
    let repository: SettingsRepository

    func execute() async throws -> AppSettings {
        try await repository.fetchSettings()
    }
}

struct SaveSettingsUseCase {
    let repository: SettingsRepository

    func execute(_ settings: AppSettings) async throws {
        try await repository.saveSettings(settings)
    }
}

struct DeleteAllUserDataUseCase {
    let repository: LocalDataRepository

    func execute() async throws {
        try await repository.deleteAllUserData()
    }
}
