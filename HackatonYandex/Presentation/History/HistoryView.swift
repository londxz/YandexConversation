//
//  HistoryView.swift
//  HackatonYandex
//
//  Created by Rodion Kholodov.
//

import Foundation

@MainActor
protocol HistoryView: AnyObject {
    func render(_ viewModel: HistoryViewModel)
    func presentHistoryError(_ message: String)
    func shareTranscriptText(_ text: String)
    func shareTranscriptFile(text: String, fileName: String)
}

struct HistoryViewModel {
    struct Item {
        let id: String
        let title: String
        let subtitle: String
        let dateText: String
        let messageCountText: String
    }

    enum State {
        case loading
        case empty(String)
        case content([Item])
        case error(String)
    }

    let title: String
    let state: State
}
