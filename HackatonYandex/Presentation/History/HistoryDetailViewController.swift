//
//  HistoryDetailViewController.swift
//  HackatonYandex
//
//  Created by Rodion Kholodov.
//

import UIKit

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
        view.backgroundColor = .chatBackground
        navigationItem.title = historyTitle
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "square.and.arrow.up"),
            menu: makeShareMenu()
        )
        navigationItem.rightBarButtonItem?.accessibilityLabel = "Поделиться разговором"

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .chatBackground
        tableView.separatorStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(HistoryMessageBubbleCell.self, forCellReuseIdentifier: HistoryMessageBubbleCell.reuseID)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 96

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

    private func makeShareMenu() -> UIMenu {
        let shareAction = UIAction(
            title: "Поделиться",
            image: UIImage(systemName: "arrowshape.turn.up.right")
        ) { [weak self] _ in
            self?.presenter.didRequestShareTranscript()
        }

        let exportAction = UIAction(
            title: "Скачать",
            image: UIImage(systemName: "square.and.arrow.down")
        ) { [weak self] _ in
            self?.presenter.didRequestExportTranscript()
        }

        return UIMenu(children: [shareAction, exportAction])
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

    func presentHistoryDetailError(_ message: String) {
        let alert = UIAlertController(
            title: "Что-то пошло не так",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Понятно", style: .default))
        present(alert, animated: true)
    }

    func shareDetailTranscriptText(_ text: String) {
        presentActivityController(items: [text])
    }

    func shareDetailTranscriptFile(text: String, fileName: String) {
        do {
            let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
            presentActivityController(items: [fileURL])
        } catch {
            AppLogger.error("Failed to export transcript: \(error.localizedDescription)")
            presentHistoryDetailError("Не удалось подготовить файл.")
        }
    }
}

extension HistoryDetailViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        messages.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: HistoryMessageBubbleCell.reuseID, for: indexPath)
        guard let bubbleCell = cell as? HistoryMessageBubbleCell else {
            return cell
        }

        bubbleCell.configure(message: messages[indexPath.row])
        return bubbleCell
    }
}
