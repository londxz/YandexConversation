//
//  AppLogger.swift
//  HackatonYandex
//
//  Created by Rodion Kholodov.
//

import Foundation

enum AppLogger {
    static func debug(_ message: @autoclosure () -> String) {
        #if DEBUG
        print("[DEBUG] \(message())")
        #endif
    }

    static func error(_ message: @autoclosure () -> String) {
        #if DEBUG
        print("[ERROR] \(message())")
        #endif
    }
}
