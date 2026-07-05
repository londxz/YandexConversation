//
//  SettingsViewController.swift
//  HackatonYandex
//
//  Created by Rodion Kholodov.
//

import UIKit

protocol SettingsView: AnyObject {
    func render(_ viewModel: SettingsViewModel)
}

struct SettingsViewModel {
    struct Item {
        let title: String
        let value: String
    }

    let title: String
    let items: [Item]
}

final class SettingsPresenter {
    private weak var view: SettingsView?
    private let settings: AppSettings

    init(view: SettingsView, settings: AppSettings = .defaultValue) {
        self.view = view
        self.settings = settings
    }

    func viewDidLoad() {
        let items = [
            SettingsViewModel.Item(title: "Язык распознавания", value: settings.recognitionLanguage),
            SettingsViewModel.Item(title: "Язык озвучивания", value: settings.ttsLanguage),
            SettingsViewModel.Item(title: "Автостарт микрофона", value: settings.autoStartMicrophone ? "Вкл" : "Выкл"),
            SettingsViewModel.Item(title: "Сохранять разговоры", value: settings.saveConversationsByDefault ? "Вкл" : "Выкл"),
            SettingsViewModel.Item(title: "Синхронизация", value: settings.syncEnabled ? "Вкл" : "Выкл")
        ]

        view?.render(SettingsViewModel(title: "Настройки", items: items))
    }
}

final class SettingsViewController: UIViewController {
    private let container: AppContainer
    private lazy var presenter = SettingsPresenter(view: self)
    private var viewModel = SettingsViewModel(title: "Настройки", items: [])

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

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

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .backgroundYandex
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "SettingsCell")
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }
}

extension SettingsViewController: SettingsView {
    func render(_ viewModel: SettingsViewModel) {
        self.viewModel = viewModel
        navigationItem.title = viewModel.title
        tableView.reloadData()
    }
}

extension SettingsViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SettingsCell", for: indexPath)
        let item = viewModel.items[indexPath.row]

        var content = cell.defaultContentConfiguration()
        content.text = item.title
        content.secondaryText = item.value
        content.textProperties.font = UIFont(name: "YSDisplay-Medium", size: 17) ?? .systemFont(ofSize: 17, weight: .medium)
        content.secondaryTextProperties.color = .secondaryLabel
        cell.contentConfiguration = content
        cell.backgroundColor = .backgroundYandex
        cell.selectionStyle = .none
        return cell
    }
}

extension SettingsViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        false
    }
}
