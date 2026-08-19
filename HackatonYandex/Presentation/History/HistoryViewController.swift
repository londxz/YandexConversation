//
//  HistoryViewController.swift
//  HackatonYandex
//
//  Created by Rodion Kholodov.
//

import UIKit

final class HistoryViewController: UIViewController {
    private let container: AppContainer
    private lazy var presenter = HistoryPresenter(
        view: self,
        fetchConversationHistoryUseCase: container.fetchConversationHistoryUseCase,
        fetchConversationMessagesUseCase: container.fetchConversationMessagesUseCase,
        saveConversationUseCase: container.saveConversationUseCase,
        deleteConversationUseCase: container.deleteConversationUseCase
    )

    private var items: [HistoryViewModel.Item] = []
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let stateLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let refreshControl = UIRefreshControl()
    private let searchController = UISearchController(searchResultsController: nil)
    private var hasLoadedHistory = false

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
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if hasLoadedHistory {
            presenter.didRequestRefresh()
        } else {
            hasLoadedHistory = true
            presenter.viewDidLoad()
        }
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

        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Поиск"
        searchController.searchBar.accessibilityLabel = "Поиск по истории разговоров"
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .backgroundYandex
        tableView.separatorStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(HistoryConversationCell.self, forCellReuseIdentifier: HistoryConversationCell.reuseID)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 92
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

    private func makeMenu(for item: HistoryViewModel.Item) -> UIMenu {
        let renameAction = UIAction(
            title: "Изменить название",
            image: UIImage(systemName: "pencil")
        ) { [weak self] _ in
            self?.presentRenameAlert(for: item)
        }

        let exportAction = UIAction(
            title: "Скачать",
            image: UIImage(systemName: "square.and.arrow.down")
        ) { [weak self] _ in
            self?.presenter.didRequestExportConversation(id: item.id)
        }

        let shareAction = UIAction(
            title: "Поделиться",
            image: UIImage(systemName: "arrowshape.turn.up.right")
        ) { [weak self] _ in
            self?.presenter.didRequestShareConversation(id: item.id)
        }

        let deleteAction = UIAction(
            title: "Удалить",
            image: UIImage(systemName: "trash"),
            attributes: .destructive
        ) { [weak self] _ in
            self?.presentDeleteConfirmation(for: item)
        }

        return UIMenu(children: [
            renameAction,
            exportAction,
            shareAction,
            deleteAction
        ])
    }

    private func presentRenameAlert(for item: HistoryViewModel.Item) {
        let alert = UIAlertController(title: "Название разговора", message: nil, preferredStyle: .alert)
        alert.addTextField { textField in
            textField.text = item.title
            textField.placeholder = "Название"
            textField.clearButtonMode = .whileEditing
            textField.returnKeyType = .done
        }

        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        alert.addAction(UIAlertAction(title: "Сохранить", style: .default) { [weak self, weak alert] _ in
            self?.presenter.didRenameConversation(
                id: item.id,
                title: alert?.textFields?.first?.text ?? ""
            )
        })

        present(alert, animated: true)
    }

    private func presentDeleteConfirmation(for item: HistoryViewModel.Item) {
        let alert = UIAlertController(
            title: "Удалить разговор?",
            message: "Это действие удалит разговор и все его сообщения с устройства.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        alert.addAction(UIAlertAction(title: "Удалить", style: .destructive) { [weak self] _ in
            self?.presenter.didRequestDeleteConversation(id: item.id)
        })

        present(alert, animated: true)
    }

    private func presentActivityController(items: [Any]) {
        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
        activityVC.popoverPresentationController?.sourceView = view
        activityVC.popoverPresentationController?.sourceRect = CGRect(
            x: view.bounds.midX,
            y: view.bounds.midY,
            width: 0,
            height: 0
        )
        present(activityVC, animated: true)
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
        case .empty(let message):
            items = []
            tableView.reloadData()
            tableView.isHidden = true
            activityIndicator.stopAnimating()
            stateLabel.text = message
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

    func presentHistoryError(_ message: String) {
        let alert = UIAlertController(
            title: "Что-то пошло не так",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Понятно", style: .default))
        present(alert, animated: true)
    }

    func shareTranscriptText(_ text: String) {
        presentActivityController(items: [text])
    }

    func shareTranscriptFile(text: String, fileName: String) {
        do {
            let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
            presentActivityController(items: [fileURL])
        } catch {
            AppLogger.error("Failed to export transcript: \(error.localizedDescription)")
            presentHistoryError("Не удалось подготовить файл.")
        }
    }
}

extension HistoryViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        presenter.didUpdateSearchQuery(searchController.searchBar.text ?? "")
    }
}

extension HistoryViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: HistoryConversationCell.reuseID, for: indexPath)
        guard let historyCell = cell as? HistoryConversationCell else {
            return cell
        }

        let item = items[indexPath.row]
        historyCell.configure(item: item, menu: makeMenu(for: item))
        return historyCell
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
            self?.presentDeleteConfirmation(for: item)
            completion(true)
        }

        return UISwipeActionsConfiguration(actions: [deleteAction])
    }
}
