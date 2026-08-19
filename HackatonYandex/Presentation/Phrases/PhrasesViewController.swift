//
//  PhrasesViewController.swift
//  HackatonYandex
//
//  Created by Rodion Kholodov.
//

import UIKit

final class PhrasesViewController: UIViewController {
    private let container: AppContainer
    private lazy var presenter = PhrasesPresenter(
        view: self,
        fetchPhrasesUseCase: container.fetchPhrasesUseCase,
        createPhraseUseCase: container.createPhraseUseCase,
        savePhraseUseCase: container.savePhraseUseCase,
        deletePhraseUseCase: container.deletePhraseUseCase,
        fetchPhraseFoldersUseCase: container.fetchPhraseFoldersUseCase,
        createPhraseFolderUseCase: container.createPhraseFolderUseCase,
        savePhraseFolderUseCase: container.savePhraseFolderUseCase,
        deletePhraseFolderUseCase: container.deletePhraseFolderUseCase
    )

    private var items: [PhrasesViewModel.Item] = []
    private var folders: [PhrasesViewModel.FolderItem] = []
    private let headerView = UIView()
    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let searchBar = UISearchBar()
    private let folderButton = UIButton(type: .system)
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let addButton = UIButton(type: .system)
    private let stateLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private var largeTextDisplayViewController: LargeTextDisplayViewController?
    private var hasAppeared = false

    init(container: AppContainer) {
        self.container = container
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

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if hasAppeared {
            presenter.didRequestRefresh()
        } else {
            hasAppeared = true
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        largeTextDisplayViewController?.dismissImmediately()
        largeTextDisplayViewController = nil
    }

    private func setupView() {
        view.backgroundColor = .backgroundYandex
        setupHeader()
        setupPhraseControls()
        setupAddButton()
        setupTableView()
        setupStateViews()
    }

    private func setupPhraseControls() {
        searchBar.placeholder = "Поиск"
        searchBar.searchBarStyle = .minimal
        searchBar.delegate = self
        searchBar.accessibilityLabel = "Поиск по заготовленным фразам"
        searchBar.translatesAutoresizingMaskIntoConstraints = false

        var configuration = UIButton.Configuration.gray()
        configuration.image = UIImage(systemName: "folder")
        configuration.imagePadding = 8
        configuration.title = "Все фразы"
        configuration.baseForegroundColor = .label
        configuration.cornerStyle = .small
        folderButton.configuration = configuration
        folderButton.contentHorizontalAlignment = .leading
        folderButton.showsMenuAsPrimaryAction = true
        folderButton.accessibilityLabel = "Выбрать папку"
        folderButton.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(searchBar)
        view.addSubview(folderButton)

        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            searchBar.heightAnchor.constraint(equalToConstant: 52),

            folderButton.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 2),
            folderButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            folderButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            folderButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func setupHeader() {
        headerView.translatesAutoresizingMaskIntoConstraints = false
        headerView.backgroundColor = .backgroundYandex

        backButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        backButton.tintColor = .black
        backButton.accessibilityLabel = "Назад"
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        backButton.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.text = "Фразы"
        titleLabel.textAlignment = .center
        titleLabel.font = UIFont(name: "YSDisplay-Medium", size: 17)
            ?? .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .black
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(headerView)
        headerView.addSubview(backButton)
        headerView.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 48),

            backButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            backButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16),
            backButton.widthAnchor.constraint(equalToConstant: 44),
            backButton.heightAnchor.constraint(equalTo: backButton.widthAnchor),

            titleLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: backButton.trailingAnchor, constant: 12)
        ])
    }

    private func setupAddButton() {
        var configuration = UIButton.Configuration.filled()
        configuration.title = "Добавить фразу"
        configuration.image = UIImage(systemName: "plus.circle.fill")
        configuration.imagePadding = 8
        configuration.baseForegroundColor = .black
        configuration.baseBackgroundColor = .yellowYandex
        configuration.cornerStyle = .large

        addButton.configuration = configuration
        addButton.titleLabel?.font = UIFont(name: "YSDisplay-Medium", size: 17)
            ?? .systemFont(ofSize: 17, weight: .medium)
        addButton.accessibilityLabel = "Добавить фразу"
        addButton.addTarget(self, action: #selector(addPhraseTapped), for: .touchUpInside)
        addButton.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(addButton)

        NSLayoutConstraint.activate([
            addButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            addButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            addButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            addButton.heightAnchor.constraint(equalToConstant: 53)
        ])
    }

    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .backgroundYandex
        tableView.separatorStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(PhraseCell.self, forCellReuseIdentifier: PhraseCell.reuseID)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 72

        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: folderButton.bottomAnchor, constant: 4),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: addButton.topAnchor, constant: -8)
        ])
    }

    private func setupStateViews() {
        stateLabel.numberOfLines = 0
        stateLabel.textAlignment = .center
        stateLabel.textColor = .secondaryLabel
        stateLabel.font = UIFont(name: "YSDisplay-Medium", size: 20)
            ?? .systemFont(ofSize: 20, weight: .medium)
        stateLabel.translatesAutoresizingMaskIntoConstraints = false

        activityIndicator.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stateLabel)
        view.addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            stateLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stateLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            stateLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),

            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    @objc private func backTapped() {
        if let navigationController, navigationController.viewControllers.first !== self {
            navigationController.popViewController(animated: true)
        } else {
            tabBarController?.selectedIndex = 0
        }
    }

    @objc private func addPhraseTapped() {
        presentPhraseEditor(
            title: "Новая фраза",
            initialText: nil
        ) { [weak self] text in
            self?.presenter.didCreatePhrase(text: text)
        }
    }

    private func presentPhraseEditor(
        title: String,
        initialText: String?,
        onSave: @escaping (String) -> Void
    ) {
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        alert.addTextField { textField in
            textField.text = initialText
            textField.placeholder = "Текст фразы"
            textField.clearButtonMode = .whileEditing
            textField.returnKeyType = .done
        }

        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        alert.addAction(UIAlertAction(title: "Сохранить", style: .default) { _ in
            onSave(alert.textFields?.first?.text ?? "")
        })

        present(alert, animated: true)
    }

    private func showPhrase(_ text: String) {
        largeTextDisplayViewController?.dismissImmediately()

        let displayViewController = LargeTextDisplayViewController(text: text, container: container)
        displayViewController.onDismiss = { [weak self, weak displayViewController] in
            guard self?.largeTextDisplayViewController === displayViewController else { return }
            self?.largeTextDisplayViewController = nil
        }
        largeTextDisplayViewController = displayViewController
        displayViewController.attach(to: self)
    }

    private func sharePhrase(_ text: String, sourceView: UIView) {
        let activityVC = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        activityVC.popoverPresentationController?.sourceView = sourceView
        activityVC.popoverPresentationController?.sourceRect = sourceView.bounds
        present(activityVC, animated: true)
    }

    private func exportPhrase(_ text: String, sourceView: UIView) {
        do {
            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("phrase-\(UUID().uuidString).txt")
            try text.write(to: fileURL, atomically: true, encoding: .utf8)

            let activityVC = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
            activityVC.popoverPresentationController?.sourceView = sourceView
            activityVC.popoverPresentationController?.sourceRect = sourceView.bounds
            present(activityVC, animated: true)
        } catch {
            AppLogger.error("Failed to export phrase: \(error.localizedDescription)")
            presentError("Не удалось подготовить файл.")
        }
    }

    private func presentError(_ message: String) {
        let alert = UIAlertController(
            title: "Что-то пошло не так",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Понятно", style: .default))
        present(alert, animated: true)
    }

    private func makeFolderMenu(selectedTitle: String) -> UIMenu {
        let allAction = UIAction(
            title: "Все фразы",
            image: UIImage(systemName: "tray.full"),
            state: selectedTitle == "Все фразы" ? .on : .off
        ) { [weak self] _ in
            self?.presenter.didSelectFolder(id: nil)
        }
        let folderActions = folders.map { folder in
            UIAction(
                title: folder.title,
                image: UIImage(systemName: "folder"),
                state: folder.isSelected ? .on : .off
            ) { [weak self] _ in
                self?.presenter.didSelectFolder(id: folder.id)
            }
        }
        let createAction = UIAction(
            title: "Новая папка",
            image: UIImage(systemName: "folder.badge.plus")
        ) { [weak self] _ in
            self?.presentFolderEditor(title: "Новая папка", initialTitle: nil) { title in
                self?.presenter.didCreateFolder(title: title)
            }
        }
        let manageAction = UIAction(
            title: "Управлять папками",
            image: UIImage(systemName: "folder.badge.gearshape")
        ) { [weak self] _ in
            self?.presentFolderManager()
        }

        return UIMenu(children: [
            UIMenu(options: .displayInline, children: [allAction] + folderActions),
            UIMenu(options: .displayInline, children: [createAction, manageAction])
        ])
    }

    private func makeMoveMenu(for item: PhrasesViewModel.Item) -> UIMenu {
        let withoutFolder = UIAction(
            title: "Без папки",
            image: UIImage(systemName: "tray"),
            state: item.folderId == nil ? .on : .off
        ) { [weak self] _ in
            self?.presenter.didMovePhrase(id: item.id, toFolderId: nil)
        }
        let folderActions = folders.map { folder in
            UIAction(
                title: folder.title,
                image: UIImage(systemName: "folder"),
                state: item.folderId == folder.id ? .on : .off
            ) { [weak self] _ in
                self?.presenter.didMovePhrase(id: item.id, toFolderId: folder.id)
            }
        }
        return UIMenu(
            title: "Переместить в папку",
            image: UIImage(systemName: "folder"),
            children: [withoutFolder] + folderActions
        )
    }

    private func presentFolderEditor(
        title: String,
        initialTitle: String?,
        onSave: @escaping (String) -> Void
    ) {
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        alert.addTextField { textField in
            textField.text = initialTitle
            textField.placeholder = "Название папки"
            textField.clearButtonMode = .whileEditing
            textField.returnKeyType = .done
        }
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        alert.addAction(UIAlertAction(title: "Сохранить", style: .default) { _ in
            onSave(alert.textFields?.first?.text ?? "")
        })
        present(alert, animated: true)
    }

    private func presentFolderManager() {
        guard !folders.isEmpty else {
            presentFolderEditor(title: "Новая папка", initialTitle: nil) { [weak self] title in
                self?.presenter.didCreateFolder(title: title)
            }
            return
        }

        let sheet = UIAlertController(title: "Папки", message: nil, preferredStyle: .actionSheet)
        for folder in folders {
            sheet.addAction(UIAlertAction(title: folder.title, style: .default) { [weak self] _ in
                self?.presentFolderActions(folder)
            })
        }
        sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        sheet.popoverPresentationController?.sourceView = folderButton
        sheet.popoverPresentationController?.sourceRect = folderButton.bounds
        present(sheet, animated: true)
    }

    private func presentFolderActions(_ folder: PhrasesViewModel.FolderItem) {
        let sheet = UIAlertController(title: folder.title, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Переименовать", style: .default) { [weak self] _ in
            self?.presentFolderEditor(title: "Название папки", initialTitle: folder.title) { title in
                self?.presenter.didRenameFolder(id: folder.id, title: title)
            }
        })
        sheet.addAction(UIAlertAction(title: "Удалить", style: .destructive) { [weak self] _ in
            self?.presentFolderDeleteConfirmation(folder)
        })
        sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        sheet.popoverPresentationController?.sourceView = folderButton
        sheet.popoverPresentationController?.sourceRect = folderButton.bounds
        present(sheet, animated: true)
    }

    private func presentFolderDeleteConfirmation(_ folder: PhrasesViewModel.FolderItem) {
        let alert = UIAlertController(
            title: "Удалить папку?",
            message: "Фразы останутся и перейдут в раздел без папки.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        alert.addAction(UIAlertAction(title: "Удалить", style: .destructive) { [weak self] _ in
            self?.presenter.didDeleteFolder(id: folder.id)
        })
        present(alert, animated: true)
    }

    private func presentPhraseDeleteConfirmation(_ item: PhrasesViewModel.Item) {
        let alert = UIAlertController(
            title: "Удалить фразу?",
            message: item.title,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        alert.addAction(UIAlertAction(title: "Удалить", style: .destructive) { [weak self] _ in
            self?.presenter.didDeletePhrase(id: item.id)
        })
        present(alert, animated: true)
    }

    private func makeMenu(
        for item: PhrasesViewModel.Item,
        sourceView: UIView
    ) -> UIMenu {
        let editAction = UIAction(
            title: "Изменить текст",
            image: UIImage(systemName: "pencil")
        ) { [weak self] _ in
            self?.presentPhraseEditor(
                title: "Изменить фразу",
                initialText: item.title
            ) { text in
                self?.presenter.didUpdatePhrase(id: item.id, text: text)
            }
        }

        let pinAction = UIAction(
            title: item.isPinned ? "Открепить" : "Отметить",
            image: UIImage(named: item.isPinned ? "pin" : "pin_filled")
        ) { [weak self] _ in
            self?.presenter.didTogglePin(id: item.id)
        }

        let exportAction = UIAction(
            title: "Скачать",
            image: UIImage(systemName: "square.and.arrow.down")
        ) { [weak self, weak sourceView] _ in
            guard let sourceView else { return }
            self?.exportPhrase(item.title, sourceView: sourceView)
        }

        let shareAction = UIAction(
            title: "Поделиться",
            image: UIImage(systemName: "arrowshape.turn.up.right")
        ) { [weak self, weak sourceView] _ in
            guard let sourceView else { return }
            self?.sharePhrase(item.title, sourceView: sourceView)
        }

        let deleteAction = UIAction(
            title: "Удалить",
            image: UIImage(systemName: "trash"),
            attributes: .destructive
        ) { [weak self] _ in
            self?.presentPhraseDeleteConfirmation(item)
        }

        return UIMenu(children: [
            editAction,
            pinAction,
            makeMoveMenu(for: item),
            exportAction,
            shareAction,
            deleteAction
        ])
    }
}

extension PhrasesViewController: PhrasesView {
    func render(_ viewModel: PhrasesViewModel) {
        titleLabel.text = viewModel.title
        folders = viewModel.folders
        var configuration = folderButton.configuration
        configuration?.title = viewModel.selectedFolderTitle
        folderButton.configuration = configuration
        folderButton.accessibilityValue = viewModel.selectedFolderTitle
        folderButton.menu = makeFolderMenu(selectedTitle: viewModel.selectedFolderTitle)

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

    func presentPhrasesError(_ message: String) {
        presentError(message)
    }
}

extension PhrasesViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        presenter.didUpdateSearchQuery(searchText)
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
}

extension PhrasesViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: PhraseCell.reuseID, for: indexPath)
        guard let phraseCell = cell as? PhraseCell else {
            return cell
        }

        let item = items[indexPath.row]
        phraseCell.configure(
            text: item.title,
            isPinned: item.isPinned,
            menu: makeMenu(for: item, sourceView: phraseCell.menuButton)
        )
        phraseCell.onPinTap = { [weak self] in
            self?.presenter.didTogglePin(id: item.id)
        }

        return phraseCell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        showPhrase(items[indexPath.row].title)
    }
}

private final class PhraseCell: UITableViewCell {
    static let reuseID = "PhraseCell"

    var onPinTap: (() -> Void)?

    let menuButton = UIButton(type: .system)
    private let pinButton = UIButton(type: .system)
    private let phraseLabel = UILabel()
    private let separatorView = UIView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onPinTap = nil
        menuButton.menu = nil
    }

    func configure(
        text: String,
        isPinned: Bool,
        menu: UIMenu
    ) {
        phraseLabel.text = text
        pinButton.setImage(
            UIImage(named: isPinned ? "pin_filled" : "pin")?.withRenderingMode(.alwaysOriginal),
            for: .normal
        )
        pinButton.accessibilityLabel = isPinned ? "Снять отметку с фразы" : "Отметить фразу"
        pinButton.accessibilityValue = isPinned ? "Отмечена" : "Не отмечена"
        menuButton.menu = menu
    }

    private func setupView() {
        backgroundColor = .backgroundYandex
        contentView.backgroundColor = .backgroundYandex
        selectionStyle = .default

        pinButton.tintColor = .black
        pinButton.addTarget(self, action: #selector(pinTapped), for: .touchUpInside)
        pinButton.translatesAutoresizingMaskIntoConstraints = false

        phraseLabel.numberOfLines = 0
        phraseLabel.textColor = .black
        phraseLabel.font = UIFont(name: "YSDisplay-Medium", size: 17)
            ?? .systemFont(ofSize: 17, weight: .medium)
        phraseLabel.adjustsFontForContentSizeCategory = true
        phraseLabel.translatesAutoresizingMaskIntoConstraints = false

        menuButton.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        menuButton.tintColor = .black
        menuButton.showsMenuAsPrimaryAction = true
        menuButton.accessibilityLabel = "Открыть меню фразы"
        menuButton.transform = CGAffineTransform(rotationAngle: .pi / 2)
        menuButton.translatesAutoresizingMaskIntoConstraints = false

        separatorView.backgroundColor = .separator
        separatorView.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(pinButton)
        contentView.addSubview(phraseLabel)
        contentView.addSubview(menuButton)
        contentView.addSubview(separatorView)

        NSLayoutConstraint.activate([
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 72),

            pinButton.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 15),
            pinButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 21),
            pinButton.widthAnchor.constraint(equalToConstant: 32),
            pinButton.heightAnchor.constraint(equalTo: pinButton.widthAnchor),

            menuButton.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 11),
            menuButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -13),
            menuButton.widthAnchor.constraint(equalToConstant: 40),
            menuButton.heightAnchor.constraint(equalTo: menuButton.widthAnchor),

            phraseLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            phraseLabel.leadingAnchor.constraint(equalTo: pinButton.trailingAnchor, constant: 8),
            phraseLabel.trailingAnchor.constraint(equalTo: menuButton.leadingAnchor, constant: -8),
            phraseLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14),

            separatorView.leadingAnchor.constraint(equalTo: phraseLabel.leadingAnchor),
            separatorView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            separatorView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            separatorView.heightAnchor.constraint(equalToConstant: 0.5)
        ])
    }

    @objc private func pinTapped() {
        onPinTap?()
    }
}
