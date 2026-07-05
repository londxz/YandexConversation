//
//  AppConfig.swift
//  HackatonYandex
//
//  Created by Rodion Kholodov.
//

import Foundation

enum AppEnvironment {
    case development
    case staging
    case production

    static var current: AppEnvironment {
        #if DEBUG
        return .development
        #else
        return .production
        #endif
    }
}

struct AppConfig {
    private enum EnvironmentKeys {
        static let apiBaseURL = "RAZGOVOR_API_BASE_URL"
    }

    let environment: AppEnvironment
    let apiBaseURL: URL
    let requestTimeout: TimeInterval

    static func makeDefault() -> AppConfig {
        let environment = AppEnvironment.current
        let overrideURL = ProcessInfo.processInfo.environment[EnvironmentKeys.apiBaseURL]
            .flatMap(URL.init(string:))

        return AppConfig(
            environment: environment,
            apiBaseURL: overrideURL ?? defaultBaseURL(for: environment),
            requestTimeout: 30
        )
    }

    private static func defaultBaseURL(for environment: AppEnvironment) -> URL {
        switch environment {
        case .development:
            return URL(string: "https://api.razgovor.app")!
        case .staging:
            return URL(string: "https://staging-api.razgovor.app")!
        case .production:
            return URL(string: "https://api.razgovor.app")!
        }
    }
}
