//
//  HistoryViewController.swift
//  HackatonYandex
//
//  Created by Rodion Kholodov.
//

import UIKit

protocol HistoryView: AnyObject {
    func render(_ viewModel: HistoryViewModel)
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
        case empty
        case content([Item])
        case error(String)
    }

    let title: String
    let state: State
}

final class HistoryPresenter {
    private weak var view: HistoryView?
    private let fetchConversationHistoryUseCase: FetchConversationHistoryUseCase
    private let fetchConversationMessagesUseCase: FetchConversationMessagesUseCase
    private let deleteConversationUseCase: DeleteConversationUseCase
    private let dateFormatter: DateFormatter

    init(
        view: HistoryView,
        fetchConversationHistoryUseCase: FetchConversationHistoryUseCase,
        fetchConversationMessagesUseCase: FetchConversationMessagesUseCase,
        deleteConversationUseCase: DeleteConversationUseCase,
        dateFormatter: DateFormatter = HistoryDateFormatter.make()
    ) {
        self.view = view
        self.fetchConversationHistoryUseCase = fetchConversationHistoryUseCase
        self.fetchConversationMessagesUseCase = fetchConversationMessagesUseCase
        self.deleteConversationUseCase = deleteConversationUseCase
        self.dateFormatter = dateFormatter
    }

    func viewDidLoad() {
        loadHistory()
    }

    func didRequestRefresh() {
        loadHistory()
    }

    func didRequestDeleteConversation(id: String) {
        Task { [weak self] in
            guard let self else { return }

            do {
                try await deleteConversationUseCase.execute(conversationId: id)
                await MainActor.run {
                    self.loadHistory()
                }
            } catch {
                AppLogger.error("Failed to delete conversation: \(error.localizedDescription)")
                await MainActor.run {
                    self.view?.render(
                        HistoryViewModel(
                            title: "История",
                            state: .error("Не удалось удалить разговор.")
                        )
                    )
                }
            }
        }
    }

    private func loadHistory() {
        view?.render(HistoryViewModel(title: "История", state: .loading))

        Task { [weak self] in
            guard let self else { return }

            do {
                let conversations = try await fetchConversationHistoryUseCase.execute()
                var items: [HistoryViewModel.Item] = []

                for conversation in conversations {
                    let messages = try await fetchConversationMessagesUseCase.execute(
                        conversationId: conversation.id
                    )

                    guard let lastMessage = messages.last else {
                        continue
                    }

                    items.append(
                        HistoryViewModel.Item(
                            id: conversation.id,
                            title: conversation.title,
                            subtitle: lastMessage.text,
                            dateText: dateFormatter.string(from: conversation.updatedAt),
                            messageCountText: Self.makeMessageCountText(messages.count)
                        )
                    )
                }

                let renderedItems = items

                await MainActor.run {
                    self.view?.render(
                        HistoryViewModel(
                            title: "История",
                            state: renderedItems.isEmpty ? .empty : .content(renderedItems)
                        )
                    )
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
}

final class HistoryViewController: UIViewController {
    private let container: AppContainer
    private lazy var presenter = HistoryPresenter(
        view: self,
        fetchConversationHistoryUseCase: container.fetchConversationHistoryUseCase,
        fetchConversationMessagesUseCase: container.fetchConversationMessagesUseCase,
        deleteConversationUseCase: container.deleteConversationUseCase
    )

    private var items: [HistoryViewModel.Item] = []
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let stateLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let refreshControl = UIRefreshControl()

    init(container: AppContainer) {
        self.container = container
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        self.container = AppContainer()
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        presenter.viewDidLoad()
    }

    private func setupView() {
        view.backgroundColor = .backgroundYandex
        navigationItem.title = "История"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "xmark"),
            style: .plain,
            target: self,
            action: #selector(closeTapped)
        )
        navigationItem.leftBarButtonItem?.accessibilityLabel = "Закрыть историю"

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .backgroundYandex
        tableView.separatorStyle = .singleLine
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "HistoryCell")
        tableView.refreshControl = refreshControl
        refreshControl.addTarget(self, action: #selector(refreshPulled), for: .valueChanged)

        stateLabel.numberOfLines = 0
        stateLabel.textAlignment = .center
        stateLabel.textColor = .secondaryLabel
        stateLabel.font = UIFont(name: "YSDisplay-Medium", size: 20)
            ?? .systemFont(ofSize: 20, weight: .medium)
        stateLabel.translatesAutoresizingMaskIntoConstraints = false

        activityIndicator.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(tableView)
        view.addSubview(stateLabel)
        view.addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stateLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stateLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            stateLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),

            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func refreshPulled() {
        presenter.didRequestRefresh()
    }
}

extension HistoryViewController: HistoryView {
    func render(_ viewModel: HistoryViewModel) {
        navigationItem.title = viewModel.title
        refreshControl.endRefreshing()

        switch viewModel.state {
        case .loading:
            items = []
            tableView.reloadData()
            tableView.isHidden = true
            stateLabel.isHidden = true
            activityIndicator.startAnimating()
        case .empty:
            items = []
            tableView.reloadData()
            tableView.isHidden = true
            activityIndicator.stopAnimating()
            stateLabel.text = "История пока пустая"
            stateLabel.isHidden = false
        case .content(let items):
            self.items = items
            activityIndicator.stopAnimating()
            stateLabel.isHidden = true
            tableView.isHidden = false
            tableView.reloadData()
        case .error(let message):
            items = []
            tableView.reloadData()
            tableView.isHidden = true
            activityIndicator.stopAnimating()
            stateLabel.text = message
            stateLabel.isHidden = false
        }
    }
}

extension HistoryViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "HistoryCell", for: indexPath)
        let item = items[indexPath.row]

        var content = cell.defaultContentConfiguration()
        content.text = item.title
        content.secondaryText = "\(item.dateText) • \(item.messageCountText)\n\(item.subtitle)"
        content.textProperties.font = UIFont(name: "YSDisplay-Medium", size: 17)
            ?? .systemFont(ofSize: 17, weight: .medium)
        content.secondaryTextProperties.font = UIFont(name: "YSText-Regular", size: 14)
            ?? .systemFont(ofSize: 14)
        content.secondaryTextProperties.color = .secondaryLabel
        content.secondaryTextProperties.numberOfLines = 2
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        cell.backgroundColor = .backgroundYandex
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let item = items[indexPath.row]
        let detailVC = HistoryDetailViewController(
            conversationId: item.id,
            title: item.title,
            fetchConversationMessagesUseCase: container.fetchConversationMessagesUseCase
        )

        navigationController?.pushViewController(detailVC, animated: true)
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let item = items[indexPath.row]
        let deleteAction = UIContextualAction(style: .destructive, title: "Удалить") { [weak self] _, _, completion in
            self?.presenter.didRequestDeleteConversation(id: item.id)
            completion(true)
        }

        return UISwipeActionsConfiguration(actions: [deleteAction])
    }
}

protocol HistoryDetailView: AnyObject {
    func render(_ viewModel: HistoryDetailViewModel)
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

final class HistoryDetailPresenter {
    private weak var view: HistoryDetailView?
    private let conversationId: String
    private let title: String
    private let fetchConversationMessagesUseCase: FetchConversationMessagesUseCase
    private let dateFormatter: DateFormatter

    init(
        view: HistoryDetailView,
        conversationId: String,
        title: String,
        fetchConversationMessagesUseCase: FetchConversationMessagesUseCase,
        dateFormatter: DateFormatter = HistoryDateFormatter.makeTimeOnly()
    ) {
        self.view = view
        self.conversationId = conversationId
        self.title = title
        self.fetchConversationMessagesUseCase = fetchConversationMessagesUseCase
        self.dateFormatter = dateFormatter
    }

    func viewDidLoad() {
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
                        isOutgoing: $0.source == .userTyped || $0.source == .quickPhrase
                    )
                }

                await MainActor.run {
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
}

final class HistoryDetailViewController: UIViewController {
    private lazy var presenter = HistoryDetailPresenter(
        view: self,
        conversationId: conversationId,
        title: historyTitle,
        fetchConversationMessagesUseCase: fetchConversationMessagesUseCase
    )

    private let conversationId: String
    private let historyTitle: String
    private let fetchConversationMessagesUseCase: FetchConversationMessagesUseCase
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let stateLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private var messages: [HistoryDetailViewModel.Message] = []

    init(
        conversationId: String,
        title: String,
        fetchConversationMessagesUseCase: FetchConversationMessagesUseCase
    ) {
        self.conversationId = conversationId
        self.historyTitle = title
        self.fetchConversationMessagesUseCase = fetchConversationMessagesUseCase
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        presenter.viewDidLoad()
    }

    private func setupView() {
        view.backgroundColor = .backgroundYandex
        navigationItem.title = historyTitle

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .backgroundYandex
        tableView.separatorStyle = .none
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "HistoryMessageCell")

        stateLabel.numberOfLines = 0
        stateLabel.textAlignment = .center
        stateLabel.textColor = .secondaryLabel
        stateLabel.font = UIFont(name: "YSDisplay-Medium", size: 20)
            ?? .systemFont(ofSize: 20, weight: .medium)
        stateLabel.translatesAutoresizingMaskIntoConstraints = false

        activityIndicator.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(tableView)
        view.addSubview(stateLabel)
        view.addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stateLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stateLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            stateLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),

            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
}

extension HistoryDetailViewController: HistoryDetailView {
    func render(_ viewModel: HistoryDetailViewModel) {
        navigationItem.title = viewModel.title

        switch viewModel.state {
        case .loading:
            messages = []
            tableView.reloadData()
            tableView.isHidden = true
            stateLabel.isHidden = true
            activityIndicator.startAnimating()
        case .empty:
            messages = []
            tableView.reloadData()
            tableView.isHidden = true
            activityIndicator.stopAnimating()
            stateLabel.text = "В этом разговоре нет сообщений"
            stateLabel.isHidden = false
        case .content(let messages):
            self.messages = messages
            activityIndicator.stopAnimating()
            stateLabel.isHidden = true
            tableView.isHidden = false
            tableView.reloadData()
        case .error(let message):
            messages = []
            tableView.reloadData()
            tableView.isHidden = true
            activityIndicator.stopAnimating()
            stateLabel.text = message
            stateLabel.isHidden = false
        }
    }
}

extension HistoryDetailViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        messages.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "HistoryMessageCell", for: indexPath)
        let message = messages[indexPath.row]

        var content = cell.defaultContentConfiguration()
        content.text = message.text
        content.secondaryText = [
            message.speakerLabel,
            message.dateText
        ]
            .compactMap { $0 }
            .joined(separator: " • ")
        content.textProperties.font = UIFont(name: "YSDisplay-Medium", size: 18)
            ?? .systemFont(ofSize: 18, weight: .medium)
        content.textProperties.numberOfLines = 0
        content.secondaryTextProperties.font = UIFont(name: "YSText-Regular", size: 13)
            ?? .systemFont(ofSize: 13)
        content.secondaryTextProperties.color = .secondaryLabel
        cell.contentConfiguration = content
        cell.backgroundColor = message.isOutgoing ? .yellowYandex.withAlphaComponent(0.25) : .backgroundYandex
        cell.selectionStyle = .none
        return cell
    }
}

private enum HistoryDateFormatter {
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
}
