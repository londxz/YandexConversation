//
//  SettingsViewController.swift
//  HackatonYandex
//
//  Created by Rodion Kholodov.
//

import UIKit

final class SettingsViewController: UIViewController {
    private let container: AppContainer
    private lazy var presenter = SettingsPresenter(
        view: self,
        fetchSettingsUseCase: container.fetchSettingsUseCase,
        saveSettingsUseCase: container.saveSettingsUseCase,
        deleteAllUserDataUseCase: container.deleteAllUserDataUseCase,
        textToSpeechService: container.textToSpeechService
    )

    private var sections: [SettingsViewModel.Section] = []
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let activityIndicator = UIActivityIndicatorView(style: .medium)

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
        tableView.separatorColor = UIColor.separator.withAlphaComponent(0.45)
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
        tableView.contentInset = UIEdgeInsets(top: 18, left: 0, bottom: 24, right: 0)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 64
        tableView.keyboardDismissMode = .interactive
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(SettingsValueCell.self, forCellReuseIdentifier: SettingsValueCell.reuseID)
        tableView.register(SettingsSwitchCell.self, forCellReuseIdentifier: SettingsSwitchCell.reuseID)
        tableView.register(SettingsSliderCell.self, forCellReuseIdentifier: SettingsSliderCell.reuseID)

        activityIndicator.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(tableView)
        view.addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func row(at indexPath: IndexPath) -> SettingsViewModel.Row {
        sections[indexPath.section].rows[indexPath.row]
    }
}

extension SettingsViewController: SettingsView {
    func render(_ viewModel: SettingsViewModel) {
        navigationItem.title = viewModel.title

        switch viewModel.state {
        case .loading:
            sections = []
            tableView.reloadData()
            tableView.isHidden = true
            activityIndicator.startAnimating()
        case .content(let sections):
            self.sections = sections
            activityIndicator.stopAnimating()
            tableView.isHidden = false
            tableView.reloadData()
        }
    }

    func presentSelection(_ viewModel: SettingsSelectionViewModel) {
        let alert = UIAlertController(title: viewModel.title, message: nil, preferredStyle: .actionSheet)

        for option in viewModel.options {
            let isSelected = option.id == viewModel.selectedOptionID
            let title = isSelected ? "\(option.title) ✓" : option.title
            alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                self?.presenter.didSelectOption(rowID: viewModel.rowID, optionID: option.id)
            })
        }

        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        alert.popoverPresentationController?.sourceView = view
        alert.popoverPresentationController?.sourceRect = CGRect(
            x: view.bounds.midX,
            y: view.bounds.maxY - 80,
            width: 0,
            height: 0
        )
        present(alert, animated: true)
    }

    func presentDeleteDataConfirmation() {
        let alert = UIAlertController(
            title: "Удалить данные с устройства?",
            message: "Будут удалены история разговоров, сохранённые фразы и настройки. Это действие нельзя отменить.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        alert.addAction(UIAlertAction(title: "Удалить", style: .destructive) { [weak self] _ in
            self?.presenter.didConfirmDeleteAllData()
        })
        present(alert, animated: true)
    }

    func presentSettingsAlert(title: String, message: String) {
        guard presentedViewController == nil else { return }

        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Понятно", style: .default))
        present(alert, animated: true)
    }
}

extension SettingsViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].rows.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections[section].title
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        sections[section].footer
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = row(at: indexPath)

        switch row.accessory {
        case .toggle(let isOn):
            let cell = tableView.dequeueReusableCell(withIdentifier: SettingsSwitchCell.reuseID, for: indexPath)
            guard let switchCell = cell as? SettingsSwitchCell else { return cell }
            switchCell.configure(with: row, isOn: isOn) { [weak self] isOn in
                self?.presenter.didChangeToggle(rowID: row.id, isOn: isOn)
            }
            return switchCell

        case .slider(let sliderViewModel):
            let cell = tableView.dequeueReusableCell(withIdentifier: SettingsSliderCell.reuseID, for: indexPath)
            guard let sliderCell = cell as? SettingsSliderCell else { return cell }
            sliderCell.configure(with: row, sliderViewModel: sliderViewModel) { [weak self] value in
                self?.presenter.didFinishChangingSlider(rowID: row.id, value: value)
            }
            return sliderCell

        case .disclosure, .none:
            let cell = tableView.dequeueReusableCell(withIdentifier: SettingsValueCell.reuseID, for: indexPath)
            guard let valueCell = cell as? SettingsValueCell else { return cell }
            valueCell.configure(with: row)
            return valueCell
        }
    }
}

extension SettingsViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        let row = row(at: indexPath)
        guard row.isEnabled else { return false }

        switch row.accessory {
        case .disclosure, .none:
            return true
        case .toggle, .slider:
            return false
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        presenter.didSelectRow(row(at: indexPath).id)
    }
}
