//
//  HistoryDetailPresenter.swift
//  HackatonYandex
//
//  Created by Rodion Kholodov.
//

import Foundation

@MainActor
final class HistoryDetailPresenter {
    private weak var view: HistoryDetailView?
    private let conversationId: String
    private let title: String
    private let fetchConversationMessagesUseCase: FetchConversationMessagesUseCase
    private let dateFormatter: DateFormatter
    private let fileNameDateFormatter: DateFormatter
    private var messages: [ConversationMessage] = []

    init(
        view: HistoryDetailView,
        conversationId: String,
        title: String,
        fetchConversationMessagesUseCase: FetchConversationMessagesUseCase,
        dateFormatter: DateFormatter = HistoryDateFormatter.makeTimeOnly(),
        fileNameDateFormatter: DateFormatter = HistoryDateFormatter.makeFileNameDate()
    ) {
        self.view = view
        self.conversationId = conversationId
        self.title = title
        self.fetchConversationMessagesUseCase = fetchConversationMessagesUseCase
        self.dateFormatter = dateFormatter
        self.fileNameDateFormatter = fileNameDateFormatter
    }

    func viewDidLoad() {
        loadMessages()
    }

    func didRequestShareTranscript() {
        guard !messages.isEmpty else {
            view?.presentHistoryDetailError("В разговоре нет сообщений для отправки.")
            return
        }

        view?.shareDetailTranscriptText(makeTranscript())
    }

    func didRequestExportTranscript() {
        guard !messages.isEmpty else {
            view?.presentHistoryDetailError("В разговоре нет сообщений для скачивания.")
            return
        }

        view?.shareDetailTranscriptFile(
            text: makeTranscript(),
            fileName: makeFileName()
        )
    }

    func didRequestContinueConversation() {
        guard !messages.isEmpty else {
            view?.presentHistoryDetailError("В разговоре нет сообщений для продолжения.")
            return
        }

        view?.continueConversation(id: conversationId)
    }

    private func loadMessages() {
        view?.render(HistoryDetailViewModel(title: title, state: .loading))

        Task { [weak self] in
            guard let self else { return }

            do {
                let messages = try await fetchConversationMessagesUseCase.execute(
                    conversationId: conversationId
                )
                let viewMessages = messages.map {
                    HistoryDetailViewModel.Message(
                        text: $0.text,
                        speakerLabel: $0.speakerLabel,
                        dateText: self.dateFormatter.string(from: $0.createdAt),
                        isOutgoing: Self.isOutgoing($0)
                    )
                }

                await MainActor.run {
                    self.messages = messages
                    self.view?.render(
                        HistoryDetailViewModel(
                            title: self.title,
                            state: viewMessages.isEmpty ? .empty : .content(viewMessages)
                        )
                    )
                }
            } catch {
                AppLogger.error("Failed to load conversation messages: \(error.localizedDescription)")
                await MainActor.run {
                    self.view?.render(
                        HistoryDetailViewModel(
                            title: self.title,
                            state: .error("Не удалось загрузить разговор.")
                        )
                    )
                }
            }
        }
    }

    private func makeTranscript() -> String {
        let lines = messages.map { message in
            let time = dateFormatter.string(from: message.createdAt)
            let author = Self.makeAuthorText(for: message)
            return "[\(time)] \(author): \(message.text)"
        }

        return ([title, ""] + lines).joined(separator: "\n")
    }

    private func makeFileName() -> String {
        let date = fileNameDateFormatter.string(from: Date())
        let safeTitle = HistoryPresenter.makeSafeFileName(title)
        return "\(date)-\(safeTitle).txt"
    }

    private static func isOutgoing(_ message: ConversationMessage) -> Bool {
        message.source == .userTyped
            || message.source == .userVoice
            || message.source == .quickPhrase
    }

    private static func makeAuthorText(for message: ConversationMessage) -> String {
        if isOutgoing(message) {
            return "Я"
        }

        return message.speakerLabel ?? "Говорящий"
    }
}
