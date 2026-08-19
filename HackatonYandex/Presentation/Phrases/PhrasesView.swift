//
//  PhrasesView.swift
//  HackatonYandex
//
//  Created by Rodion Kholodov.
//

import Foundation

@MainActor
protocol PhrasesView: AnyObject {
    func render(_ viewModel: PhrasesViewModel)
    func presentPhrasesError(_ message: String)
}

struct PhrasesViewModel {
    struct Item {
        let id: String
        let title: String
        let isPinned: Bool
        let folderId: String?
    }

    struct FolderItem {
        let id: String
        let title: String
        let isSelected: Bool
    }

    enum State {
        case loading
        case empty(String)
        case content([Item])
        case error(String)
    }

    let title: String
    let selectedFolderTitle: String
    let folders: [FolderItem]
    let state: State
}
