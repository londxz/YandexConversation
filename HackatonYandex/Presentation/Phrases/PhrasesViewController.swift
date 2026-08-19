//
//  PhrasesViewController.swift
//  HackatonYandex
//
//  Created by Rodion Kholodov.
//

import UIKit

protocol PhrasesView: AnyObject {
    func render(_ viewModel: PhrasesViewModel)
}

struct PhrasesViewModel {
    struct Item {
        let id: String
        let title: String
        let isPinned: Bool
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

final class PhrasesPresenter {
    private weak var view: PhrasesView?
    private let fetchPhrasesUseCase: FetchPhrasesUseCase
    private let createPhraseUseCase: CreatePhraseUseCase
    private let savePhraseUseCase: SavePhraseUseCase
    private let deletePhraseUseCase: DeletePhraseUseCase
    private var phrases: [Phrase] = []

    init(
        view: PhrasesView,
        fetchPhrasesUseCase: FetchPhrasesUseCase,
        createPhraseUseCase: CreatePhraseUseCase,
        savePhraseUseCase: SavePhraseUseCase,
        deletePhraseUseCase: DeletePhraseUseCase
    ) {
        self.view = view
        self.fetchPhrasesUseCase = fetchPhrasesUseCase
        self.createPhraseUseCase = createPhraseUseCase
        self.savePhraseUseCase = savePhraseUseCase
        self.deletePhraseUseCase = deletePhraseUseCase
    }

    func viewDidLoad() {
        loadPhrases()
    }

    func didRequestRefresh() {
        loadPhrases()
    }

    func didCreatePhrase(text: String) {
        let normalizedText = normalize(text)
        guard !normalizedText.isEmpty else { return }

        Task { [weak self] in
            guard let self else { return }

            do {
                _ = try await createPhraseUseCase.execute(text: normalizedText)
                await MainActor.run {
                    self.loadPhrases()
                }
            } catch {
                AppLogger.error("Failed to create phrase: \(error.localizedDescription)")
                await renderError("Не удалось добавить фразу.")
            }
        }
    }

    func didUpdatePhrase(id: String, text: String) {
        let normalizedText = normalize(text)
        guard !normalizedText.isEmpty else { return }
        guard var phrase = phrases.first(where: { $0.id == id }) else { return }

        phrase.text = normalizedText
        phrase.updatedAt = Date()

        save(phrase, failureMessage: "Не удалось изменить фразу.")
    }

    func didTogglePin(id: String) {
        guard var phrase = phrases.first(where: { $0.id == id }) else { return }

        phrase.isFavorite.toggle()
        phrase.updatedAt = Date()

        save(phrase, failureMessage: "Не удалось обновить закрепление.")
    }

    func didDeletePhrase(id: String) {
        Task { [weak self] in
            guard let self else { return }

            do {
                try await deletePhraseUseCase.execute(id: id)
                await MainActor.run {
                    self.loadPhrases()
                }
            } catch {
                AppLogger.error("Failed to delete phrase: \(error.localizedDescription)")
                await renderError("Не удалось удалить фразу.")
            }
        }
    }

    private func loadPhrases() {
        view?.render(PhrasesViewModel(title: "Фразы", state: .loading))

        Task { [weak self] in
            guard let self else { return }

            do {
                let phrases = try await fetchPhrasesUseCase.execute()
                let items = phrases.map {
                    PhrasesViewModel.Item(
                        id: $0.id,
                        title: $0.text,
                        isPinned: $0.isFavorite
                    )
                }

                await MainActor.run {
                    self.phrases = phrases
                    self.view?.render(
                        PhrasesViewModel(
                            title: "Фразы",
                            state: items.isEmpty ? .empty : .content(items)
                        )
                    )
                }
            } catch {
                AppLogger.error("Failed to load phrases: \(error.localizedDescription)")
                await renderError("Не удалось загрузить фразы.")
            }
        }
    }

    private func save(_ phrase: Phrase, failureMessage: String) {
        Task { [weak self] in
            guard let self else { return }

            do {
                try await savePhraseUseCase.execute(phrase)
                await MainActor.run {
                    self.loadPhrases()
                }
            } catch {
                AppLogger.error("Failed to save phrase: \(error.localizedDescription)")
                await renderError(failureMessage)
            }
        }
    }

    @MainActor
    private func renderError(_ message: String) {
        view?.render(PhrasesViewModel(title: "Фразы", state: .error(message)))
    }

    private func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

final class PhrasesViewController: UIViewController {
    private let container: AppContainer
    private lazy var presenter = PhrasesPresenter(
        view: self,
        fetchPhrasesUseCase: container.fetchPhrasesUseCase,
        createPhraseUseCase: container.createPhraseUseCase,
        savePhraseUseCase: container.savePhraseUseCase,
        deletePhraseUseCase: container.deletePhraseUseCase
    )

    private var items: [PhrasesViewModel.Item] = []
    private let headerView = UIView()
    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let addButton = UIButton(type: .system)
    private let stateLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private var phraseDisplayOverlay: PhraseDisplayOverlayView?
    private var isPhraseDisplayRotated = false

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

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        presenter.didRequestRefresh()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        dismissPhraseOverlay(animated: false)
    }

    private func setupView() {
        view.backgroundColor = .backgroundYandex
        setupHeader()
        setupAddButton()
        setupTableView()
        setupStateViews()
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
            tableView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
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
        resetPhraseDisplayRotationIfNeeded(animated: false)
        phraseDisplayOverlay?.removeFromSuperview()

        let overlay = PhraseDisplayOverlayView(
            text: text,
            textToSpeechService: container.textToSpeechService
        )
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.alpha = 0
        overlay.transform = CGAffineTransform(scaleX: 1.04, y: 1.04)
        overlay.onDismiss = { [weak self] in
            self?.phraseDisplayOverlay = nil
            self?.resetPhraseDisplayRotationIfNeeded(animated: true)
        }
        overlay.onRotate = { [weak self] in
            self?.togglePhraseDisplayRotation()
        }

        view.addSubview(overlay)
        phraseDisplayOverlay = overlay

        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: view.topAnchor),
            overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlay.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])

        UIView.animate(
            withDuration: 0.28,
            delay: 0,
            usingSpringWithDamping: 0.88,
            initialSpringVelocity: 0.3,
            options: [.curveEaseInOut]
        ) {
            overlay.alpha = 1
            overlay.transform = .identity
        }
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

    private func dismissPhraseOverlay(animated: Bool) {
        guard let overlay = phraseDisplayOverlay else {
            resetPhraseDisplayRotationIfNeeded(animated: animated)
            return
        }

        let animations = {
            overlay.alpha = 0
            overlay.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
        }

        let completion: (Bool) -> Void = { [weak self] _ in
            overlay.removeFromSuperview()
            self?.phraseDisplayOverlay = nil
            self?.resetPhraseDisplayRotationIfNeeded(animated: animated)
        }

        if animated {
            UIView.animate(
                withDuration: 0.2,
                delay: 0,
                options: [.curveEaseInOut],
                animations: animations,
                completion: completion
            )
        } else {
            animations()
            completion(true)
        }
    }

    private func togglePhraseDisplayRotation() {
        isPhraseDisplayRotated.toggle()

        UIView.animate(withDuration: 0.3) {
            self.view.transform = self.isPhraseDisplayRotated
                ? CGAffineTransform(rotationAngle: .pi)
                : .identity
        }
    }

    private func resetPhraseDisplayRotationIfNeeded(animated: Bool) {
        guard isPhraseDisplayRotated else { return }

        isPhraseDisplayRotated = false
        let changes = {
            self.view.transform = .identity
        }

        if animated {
            UIView.animate(withDuration: 0.3, animations: changes)
        } else {
            changes()
        }
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
            self?.presenter.didDeletePhrase(id: item.id)
        }

        return UIMenu(children: [
            editAction,
            pinAction,
            exportAction,
            shareAction,
            deleteAction
        ])
    }
}

extension PhrasesViewController: PhrasesView {
    func render(_ viewModel: PhrasesViewModel) {
        titleLabel.text = viewModel.title

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
            stateLabel.text = "Фраз пока нет"
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
        menuButton.menu = menu
    }

    private func setupView() {
        backgroundColor = .backgroundYandex
        contentView.backgroundColor = .backgroundYandex
        selectionStyle = .default

        pinButton.tintColor = .black
        pinButton.accessibilityLabel = "Закрепить фразу"
        pinButton.addTarget(self, action: #selector(pinTapped), for: .touchUpInside)
        pinButton.translatesAutoresizingMaskIntoConstraints = false

        phraseLabel.numberOfLines = 0
        phraseLabel.textColor = .black
        phraseLabel.font = UIFont(name: "YSDisplay-Medium", size: 17)
            ?? .systemFont(ofSize: 17, weight: .medium)
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

private final class PhraseDisplayOverlayView: UIView {
    private let text: String
    private let textToSpeechService: TextToSpeechService
    private let playButton = UIButton(type: .system)
    var onDismiss: (() -> Void)?
    var onRotate: (() -> Void)?

    init(text: String, textToSpeechService: TextToSpeechService) {
        self.text = text
        self.textToSpeechService = textToSpeechService
        super.init(frame: .zero)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        backgroundColor = .backgroundYandex

        let textLabel = UILabel()
        textLabel.text = text
        textLabel.numberOfLines = 0
        textLabel.textAlignment = .center
        textLabel.adjustsFontSizeToFitWidth = true
        textLabel.minimumScaleFactor = 0.45
        textLabel.font = UIFont(name: "YSDisplay-Bold", size: 40)
            ?? .systemFont(ofSize: 40, weight: .bold)
        textLabel.translatesAutoresizingMaskIntoConstraints = false

        let playImage = UIImage(named: "playButtonIcon")?.withRenderingMode(.alwaysOriginal)
        var playConfiguration = UIButton.Configuration.filled()
        playConfiguration.title = "Воспроизвести"
        playConfiguration.image = playImage
        playConfiguration.imagePlacement = .leading
        playConfiguration.imagePadding = 8
        playConfiguration.baseForegroundColor = .black
        playConfiguration.baseBackgroundColor = .yellowYandex
        playConfiguration.cornerStyle = .large
        playButton.configuration = playConfiguration
        playButton.titleLabel?.font = UIFont(name: "YSDisplay-Medium", size: 18)
        playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)
        playButton.translatesAutoresizingMaskIntoConstraints = false

        let closeButton = UIButton(type: .system)
        closeButton.setImage(
            UIImage(named: "dismisIconMicroOnScreen")?.withRenderingMode(.alwaysOriginal),
            for: .normal
        )
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        let rotateButton = UIButton(type: .system)
        rotateButton.setImage(
            UIImage(named: "rotateIconMicroOnScreen")?.withRenderingMode(.alwaysOriginal),
            for: .normal
        )
        rotateButton.addTarget(self, action: #selector(rotateTapped), for: .touchUpInside)
        rotateButton.translatesAutoresizingMaskIntoConstraints = false

        addSubview(textLabel)
        addSubview(playButton)
        addSubview(closeButton)
        addSubview(rotateButton)

        NSLayoutConstraint.activate([
            textLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            textLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            textLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            textLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),

            playButton.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -12),
            playButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            playButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            playButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            playButton.heightAnchor.constraint(equalToConstant: 64),

            closeButton.heightAnchor.constraint(equalToConstant: 56),
            closeButton.widthAnchor.constraint(equalToConstant: 56),
            closeButton.trailingAnchor.constraint(equalTo: playButton.trailingAnchor),
            closeButton.bottomAnchor.constraint(equalTo: playButton.topAnchor, constant: -24),

            rotateButton.heightAnchor.constraint(equalToConstant: 56),
            rotateButton.widthAnchor.constraint(equalToConstant: 56),
            rotateButton.leadingAnchor.constraint(equalTo: playButton.leadingAnchor),
            rotateButton.bottomAnchor.constraint(equalTo: playButton.topAnchor, constant: -24)
        ])
    }

    @objc private func playTapped() {
        textToSpeechService.speak(text)
    }

    @objc private func rotateTapped() {
        onRotate?()
    }

    @objc private func closeTapped() {
        textToSpeechService.stop()
        UIView.animate(
            withDuration: 0.2,
            delay: 0,
            options: [.curveEaseInOut]
        ) {
            self.alpha = 0
            self.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
        } completion: { _ in
            self.removeFromSuperview()
            self.onDismiss?()
        }
    }
}
