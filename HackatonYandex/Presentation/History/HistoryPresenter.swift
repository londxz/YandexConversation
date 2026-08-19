//
//  HistoryPresenter.swift
//  HackatonYandex
//
//  Created by Rodion Kholodov.
//

import Foundation

final class HistoryPresenter {
    private struct Record {
        var conversation: Conversation
        let messages: [ConversationMessage]

        var lastMessage: ConversationMessage? {
            messages.last
        }
    }

    private weak var view: HistoryView?
    private let fetchConversationHistoryUseCase: FetchConversationHistoryUseCase
    private let fetchConversationMessagesUseCase: FetchConversationMessagesUseCase
    private let saveConversationUseCase: SaveConversationUseCase
    private let deleteConversationUseCase: DeleteConversationUseCase
    private let dateFormatter: DateFormatter
    private let timeFormatter: DateFormatter
    private let fileNameDateFormatter: DateFormatter
    private var records: [Record] = []
    private var searchQuery = ""

    init(
        view: HistoryView,
        fetchConversationHistoryUseCase: FetchConversationHistoryUseCase,
        fetchConversationMessagesUseCase: FetchConversationMessagesUseCase,
        saveConversationUseCase: SaveConversationUseCase,
        deleteConversationUseCase: DeleteConversationUseCase,
        dateFormatter: DateFormatter = HistoryDateFormatter.make(),
        timeFormatter: DateFormatter = HistoryDateFormatter.makeTimeOnly(),
        fileNameDateFormatter: DateFormatter = HistoryDateFormatter.makeFileNameDate()
    ) {
        self.view = view
        self.fetchConversationHistoryUseCase = fetchConversationHistoryUseCase
        self.fetchConversationMessagesUseCase = fetchConversationMessagesUseCase
        self.saveConversationUseCase = saveConversationUseCase
        self.deleteConversationUseCase = deleteConversationUseCase
        self.dateFormatter = dateFormatter
        self.timeFormatter = timeFormatter
        self.fileNameDateFormatter = fileNameDateFormatter
    }

    func viewDidLoad() {
        loadHistory()
    }

    func didRequestRefresh() {
        loadHistory()
    }

    func didUpdateSearchQuery(_ query: String) {
        searchQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        renderRecords()
    }

    func didRenameConversation(id: String, title: String) {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else { return }
        guard var record = records.first(where: { $0.conversation.id == id }) else { return }

        record.conversation.title = normalizedTitle
        record.conversation.updatedAt = Date()
        save(record.conversation, failureMessage: "Не удалось переименовать разговор.")
    }

    func didRequestDeleteConversation(id: String) {
        Task { [weak self] in
            guard let self else { return }

            do {
                try await deleteConversationUseCase.execute(conversationId: id)
                await MainActor.run {
                    self.records.removeAll { $0.conversation.id == id }
                    self.renderRecords()
                }
            } catch {
                AppLogger.error("Failed to delete conversation: \(error.localizedDescription)")
                await MainActor.run {
                    self.view?.presentHistoryError("Не удалось удалить разговор.")
                }
            }
        }
    }

    func didRequestShareConversation(id: String) {
        guard let record = records.first(where: { $0.conversation.id == id }) else { return }
        guard !record.messages.isEmpty else {
            view?.presentHistoryError("В разговоре нет сообщений для отправки.")
            return
        }

        view?.shareTranscriptText(makeTranscript(for: record))
    }

    func didRequestExportConversation(id: String) {
        guard let record = records.first(where: { $0.conversation.id == id }) else { return }
        guard !record.messages.isEmpty else {
            view?.presentHistoryError("В разговоре нет сообщений для скачивания.")
            return
        }

        view?.shareTranscriptFile(
            text: makeTranscript(for: record),
            fileName: makeFileName(for: record.conversation)
        )
    }

    private func loadHistory() {
        view?.render(HistoryViewModel(title: "История", state: .loading))

        Task { [weak self] in
            guard let self else { return }

            do {
                let conversations = try await fetchConversationHistoryUseCase.execute()
                var loadedRecords: [Record] = []

                for conversation in conversations {
                    let messages = try await fetchConversationMessagesUseCase.execute(
                        conversationId: conversation.id
                    )

                    guard !messages.isEmpty else {
                        continue
                    }

                    loadedRecords.append(
                        Record(
                            conversation: conversation,
                            messages: messages
                        )
                    )
                }

                let recordsSnapshot = loadedRecords

                await MainActor.run {
                    self.records = recordsSnapshot
                    self.renderRecords()
                }
            } catch {
                AppLogger.error("Failed to load conversation history: \(error.localizedDescription)")
                await MainActor.run {
                    self.view?.render(
                        HistoryViewModel(
                            title: "История",
                            state: .error("Не удалось загрузить историю.")
                        )
                    )
                }
            }
        }
    }

    private func save(_ conversation: Conversation, failureMessage: String) {
        Task { [weak self] in
            guard let self else { return }

            do {
                try await saveConversationUseCase.execute(conversation)
                await MainActor.run {
                    self.loadHistory()
                }
            } catch {
                AppLogger.error("Failed to save conversation: \(error.localizedDescription)")
                await MainActor.run {
                    self.view?.presentHistoryError(failureMessage)
                }
            }
        }
    }

    private func renderRecords() {
        let filteredRecords = filtered(records)
        let items = filteredRecords.compactMap(makeItem)
        let emptyText = searchQuery.isEmpty ? "История пока пустая" : "Ничего не найдено"

        view?.render(
            HistoryViewModel(
                title: "История",
                state: items.isEmpty ? .empty(emptyText) : .content(items)
            )
        )
    }

    private func filtered(_ records: [Record]) -> [Record] {
        guard !searchQuery.isEmpty else {
            return records
        }

        return records.filter { record in
            record.conversation.title.localizedCaseInsensitiveContains(searchQuery)
                || record.messages.contains { message in
                    message.text.localizedCaseInsensitiveContains(searchQuery)
                }
        }
    }

    private func makeItem(from record: Record) -> HistoryViewModel.Item? {
        guard let lastMessage = record.lastMessage else {
            return nil
        }

        return HistoryViewModel.Item(
            id: record.conversation.id,
            title: record.conversation.title,
            subtitle: lastMessage.text,
            dateText: dateFormatter.string(from: record.conversation.updatedAt),
            messageCountText: Self.makeMessageCountText(record.messages.count)
        )
    }

    private func makeTranscript(for record: Record) -> String {
        let title = record.conversation.title
        let createdAt = dateFormatter.string(from: record.conversation.createdAt)
        let lines = record.messages.map { message in
            let time = timeFormatter.string(from: message.createdAt)
            let author = Self.makeAuthorText(for: message)
            return "[\(time)] \(author): \(message.text)"
        }

        return ([title, createdAt, ""] + lines).joined(separator: "\n")
    }

    private func makeFileName(for conversation: Conversation) -> String {
        let date = fileNameDateFormatter.string(from: conversation.createdAt)
        let title = Self.makeSafeFileName(conversation.title)
        return "\(date)-\(title).txt"
    }

    private static func makeAuthorText(for message: ConversationMessage) -> String {
        switch message.source {
        case .userTyped, .userVoice, .quickPhrase:
            return "Я"
        case .externalSpeech:
            return message.speakerLabel ?? "Говорящий"
        case .system:
            return "Система"
        }
    }

    private static func makeMessageCountText(_ count: Int) -> String {
        let suffix: String

        if count % 10 == 1 && count % 100 != 11 {
            suffix = "сообщение"
        } else if (2...4).contains(count % 10) && !(12...14).contains(count % 100) {
            suffix = "сообщения"
        } else {
            suffix = "сообщений"
        }

        return "\(count) \(suffix)"
    }

    static func makeSafeFileName(_ title: String) -> String {
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let normalized = title
            .replacingOccurrences(of: " ", with: "-")
            .unicodeScalars
            .map { allowedCharacters.contains($0) ? String($0) : "-" }
            .joined()

        let fileName = normalized.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return fileName.isEmpty ? "conversation" : String(fileName.prefix(42))
    }
}
