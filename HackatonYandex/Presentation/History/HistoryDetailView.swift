//
//  HistoryDetailView.swift
//  HackatonYandex
//
//  Created by Rodion Kholodov.
//

import Foundation

protocol HistoryDetailView: AnyObject {
    func render(_ viewModel: HistoryDetailViewModel)
    func presentHistoryDetailError(_ message: String)
    func shareDetailTranscriptText(_ text: String)
    func shareDetailTranscriptFile(text: String, fileName: String)
}

struct HistoryDetailViewModel {
    struct Message {
        let text: String
        let speakerLabel: String?
        let dateText: String
        let isOutgoing: Bool
    }

    enum State {
        case loading
        case empty
        case content([Message])
        case error(String)
    }

    let title: String
    let state: State
}
