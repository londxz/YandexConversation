//
//  HistoryDateFormatter.swift
//  HackatonYandex
//
//  Created by Rodion Kholodov.
//

import Foundation

enum HistoryDateFormatter {
    static func make() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }

    static func makeTimeOnly() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }

    static func makeFileNameDate() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "yyyy-MM-dd-HH-mm"
        return formatter
    }
}
