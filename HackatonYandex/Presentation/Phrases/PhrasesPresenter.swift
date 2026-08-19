//
//  PhrasesPresenter.swift
//  HackatonYandex
//
//  Created by Rodion Kholodov.
//

import Foundation

@MainActor
final class PhrasesPresenter {
    private weak var view: PhrasesView?
    private let fetchPhrasesUseCase: FetchPhrasesUseCase
    private let createPhraseUseCase: CreatePhraseUseCase
    private let savePhraseUseCase: SavePhraseUseCase
    private let deletePhraseUseCase: DeletePhraseUseCase
    private let fetchPhraseFoldersUseCase: FetchPhraseFoldersUseCase
    private let createPhraseFolderUseCase: CreatePhraseFolderUseCase
    private let savePhraseFolderUseCase: SavePhraseFolderUseCase
    private let deletePhraseFolderUseCase: DeletePhraseFolderUseCase

    private var phrases: [Phrase] = []
    private var folders: [PhraseFolder] = []
    private var searchQuery = ""
    private var selectedFolderId: String?

    init(
        view: PhrasesView,
        fetchPhrasesUseCase: FetchPhrasesUseCase,
        createPhraseUseCase: CreatePhraseUseCase,
        savePhraseUseCase: SavePhraseUseCase,
        deletePhraseUseCase: DeletePhraseUseCase,
        fetchPhraseFoldersUseCase: FetchPhraseFoldersUseCase,
        createPhraseFolderUseCase: CreatePhraseFolderUseCase,
        savePhraseFolderUseCase: SavePhraseFolderUseCase,
        deletePhraseFolderUseCase: DeletePhraseFolderUseCase
    ) {
        self.view = view
        self.fetchPhrasesUseCase = fetchPhrasesUseCase
        self.createPhraseUseCase = createPhraseUseCase
        self.savePhraseUseCase = savePhraseUseCase
        self.deletePhraseUseCase = deletePhraseUseCase
        self.fetchPhraseFoldersUseCase = fetchPhraseFoldersUseCase
        self.createPhraseFolderUseCase = createPhraseFolderUseCase
        self.savePhraseFolderUseCase = savePhraseFolderUseCase
        self.deletePhraseFolderUseCase = deletePhraseFolderUseCase
    }

    func viewDidLoad() {
        loadData()
    }

    func didRequestRefresh() {
        loadData()
    }

    func didUpdateSearchQuery(_ query: String) {
        searchQuery = normalize(query)
        renderContent()
    }

    func didSelectFolder(id: String?) {
        selectedFolderId = id
        renderContent()
    }

    func didCreatePhrase(text: String) {
        let text = normalize(text)
        guard !text.isEmpty else { return }

        performReloadingOperation(
            failureMessage: "Не удалось добавить фразу."
        ) { [createPhraseUseCase, selectedFolderId] in
            _ = try await createPhraseUseCase.execute(text: text, folderId: selectedFolderId)
        }
    }

    func didUpdatePhrase(id: String, text: String) {
        let text = normalize(text)
        guard !text.isEmpty, var phrase = phrase(id: id) else { return }
        phrase.text = text
        phrase.updatedAt = Date()
        save(phrase, failureMessage: "Не удалось изменить фразу.")
    }

    func didTogglePin(id: String) {
        guard var phrase = phrase(id: id) else { return }
        phrase.isFavorite.toggle()
        phrase.updatedAt = Date()
        save(phrase, failureMessage: "Не удалось обновить отметку.")
    }

    func didMovePhrase(id: String, toFolderId folderId: String?) {
        guard var phrase = phrase(id: id) else { return }
        phrase.folderId = folderId
        phrase.updatedAt = Date()
        save(phrase, failureMessage: "Не удалось переместить фразу.")
    }

    func didDeletePhrase(id: String) {
        performReloadingOperation(
            failureMessage: "Не удалось удалить фразу."
        ) { [deletePhraseUseCase] in
            try await deletePhraseUseCase.execute(id: id)
        }
    }

    func didCreateFolder(title: String) {
        let title = normalize(title)
        guard validateFolderTitle(title) else { return }
        let sortOrder = (folders.map(\.sortOrder).max() ?? -1) + 1

        performReloadingOperation(
            failureMessage: "Не удалось создать папку."
        ) { [createPhraseFolderUseCase] in
            _ = try await createPhraseFolderUseCase.execute(title: title, sortOrder: sortOrder)
        }
    }

    func didRenameFolder(id: String, title: String) {
        let title = normalize(title)
        guard validateFolderTitle(title, excluding: id) else { return }
        guard var folder = folders.first(where: { $0.id == id }) else { return }
        folder.title = title

        performReloadingOperation(
            failureMessage: "Не удалось переименовать папку."
        ) { [savePhraseFolderUseCase] in
            try await savePhraseFolderUseCase.execute(folder)
        }
    }

    func didDeleteFolder(id: String) {
        if selectedFolderId == id {
            selectedFolderId = nil
        }

        performReloadingOperation(
            failureMessage: "Не удалось удалить папку."
        ) { [deletePhraseFolderUseCase] in
            try await deletePhraseFolderUseCase.execute(id: id)
        }
    }

    private func loadData() {
        view?.render(makeViewModel(state: .loading))

        Task { [weak self, fetchPhrasesUseCase, fetchPhraseFoldersUseCase] in
            guard let self else { return }

            do {
                async let phrases = fetchPhrasesUseCase.execute()
                async let folders = fetchPhraseFoldersUseCase.execute()
                self.phrases = try await phrases
                self.folders = try await folders

                if let selectedFolderId,
                   !self.folders.contains(where: { $0.id == selectedFolderId }) {
                    self.selectedFolderId = nil
                }
                self.renderContent()
            } catch {
                AppLogger.error("Failed to load phrases: \(error.localizedDescription)")
                self.view?.render(
                    self.makeViewModel(state: .error("Не удалось загрузить фразы."))
                )
            }
        }
    }

    private func renderContent() {
        let filtered = phrases.filter { phrase in
            let matchesFolder = selectedFolderId == nil || phrase.folderId == selectedFolderId
            let matchesQuery = searchQuery.isEmpty
                || phrase.text.localizedCaseInsensitiveContains(searchQuery)
            return matchesFolder && matchesQuery
        }
        let items = filtered.map {
            PhrasesViewModel.Item(
                id: $0.id,
                title: $0.text,
                isPinned: $0.isFavorite,
                folderId: $0.folderId
            )
        }
        let emptyMessage = searchQuery.isEmpty ? "Фраз пока нет" : "Ничего не найдено"
        view?.render(
            makeViewModel(state: items.isEmpty ? .empty(emptyMessage) : .content(items))
        )
    }

    private func makeViewModel(state: PhrasesViewModel.State) -> PhrasesViewModel {
        let selectedTitle = folders.first(where: { $0.id == selectedFolderId })?.title ?? "Все фразы"
        let folderItems = folders.map {
            PhrasesViewModel.FolderItem(
                id: $0.id,
                title: $0.title,
                isSelected: $0.id == selectedFolderId
            )
        }
        return PhrasesViewModel(
            title: "Фразы",
            selectedFolderTitle: selectedTitle,
            folders: folderItems,
            state: state
        )
    }

    private func save(_ phrase: Phrase, failureMessage: String) {
        performReloadingOperation(failureMessage: failureMessage) { [savePhraseUseCase] in
            try await savePhraseUseCase.execute(phrase)
        }
    }

    private func performReloadingOperation(
        failureMessage: String,
        operation: @escaping () async throws -> Void
    ) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await operation()
                self.loadData()
            } catch {
                AppLogger.error("Phrase operation failed: \(error.localizedDescription)")
                self.view?.presentPhrasesError(failureMessage)
            }
        }
    }

    private func validateFolderTitle(_ title: String, excluding id: String? = nil) -> Bool {
        guard !title.isEmpty else { return false }
        let duplicate = folders.contains {
            $0.id != id && $0.title.compare(title, options: .caseInsensitive) == .orderedSame
        }
        if duplicate {
            view?.presentPhrasesError("Папка с таким названием уже существует.")
            return false
        }
        return true
    }

    private func phrase(id: String) -> Phrase? {
        phrases.first(where: { $0.id == id })
    }

    private func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
