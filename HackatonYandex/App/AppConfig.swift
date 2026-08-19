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
        static let eagerlyRegistersDeviceSession = "RAZGOVOR_EAGER_DEVICE_REGISTRATION"
    }

    let environment: AppEnvironment
    let apiBaseURL: URL
    let requestTimeout: TimeInterval
    let eagerlyRegistersDeviceSession: Bool

    init(
        environment: AppEnvironment,
        apiBaseURL: URL,
        requestTimeout: TimeInterval,
        eagerlyRegistersDeviceSession: Bool = false
    ) {
        self.environment = environment
        self.apiBaseURL = apiBaseURL
        self.requestTimeout = requestTimeout
        self.eagerlyRegistersDeviceSession = eagerlyRegistersDeviceSession
    }

    static func makeDefault() -> AppConfig {
        let environment = AppEnvironment.current
        let overrideURL = ProcessInfo.processInfo.environment[EnvironmentKeys.apiBaseURL]
            .flatMap(URL.init(string:))
        #if DEBUG
        let eagerlyRegistersDeviceSession = ProcessInfo.processInfo.environment[
            EnvironmentKeys.eagerlyRegistersDeviceSession
        ] == "1"
        #else
        let eagerlyRegistersDeviceSession = false
        #endif

        return AppConfig(
            environment: environment,
            apiBaseURL: overrideURL ?? defaultBaseURL(for: environment),
            requestTimeout: 30,
            eagerlyRegistersDeviceSession: eagerlyRegistersDeviceSession
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
