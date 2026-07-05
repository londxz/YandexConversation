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
        let title: String
        let isFavorite: Bool
    }

    let title: String
    let items: [Item]
}

final class PhrasesPresenter {
    private weak var view: PhrasesView?

    init(view: PhrasesView) {
        self.view = view
    }

    func viewDidLoad() {
        let items = Phrase.starterPhrases.map {
            PhrasesViewModel.Item(title: $0.text, isFavorite: $0.isFavorite)
        }

        view?.render(PhrasesViewModel(title: "Фразы", items: items))
    }
}

final class PhrasesViewController: UIViewController {
    private let container: AppContainer
    private lazy var presenter = PhrasesPresenter(view: self)
    private var viewModel = PhrasesViewModel(title: "Фразы", items: [])

    private let tableView = UITableView(frame: .zero, style: .plain)

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
        tableView.separatorStyle = .singleLine
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "PhraseCell")

        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }
}

extension PhrasesViewController: PhrasesView {
    func render(_ viewModel: PhrasesViewModel) {
        self.viewModel = viewModel
        navigationItem.title = viewModel.title
        tableView.reloadData()
    }
}

extension PhrasesViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "PhraseCell", for: indexPath)
        let item = viewModel.items[indexPath.row]

        var content = cell.defaultContentConfiguration()
        content.text = item.title
        content.textProperties.font = UIFont(name: "YSDisplay-Medium", size: 17) ?? .systemFont(ofSize: 17, weight: .medium)
        content.textProperties.numberOfLines = 0
        cell.contentConfiguration = content
        cell.accessoryType = item.isFavorite ? .checkmark : .none
        cell.backgroundColor = .backgroundYandex
        cell.selectionStyle = .default
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let item = viewModel.items[indexPath.row]
        let displayVC = PhraseDisplayViewController(
            text: item.title,
            textToSpeechService: container.textToSpeechService
        )
        displayVC.modalPresentationStyle = .fullScreen
        present(displayVC, animated: true)
    }
}

private final class PhraseDisplayViewController: UIViewController {
    private let text: String
    private let textToSpeechService: TextToSpeechService

    init(text: String, textToSpeechService: TextToSpeechService) {
        self.text = text
        self.textToSpeechService = textToSpeechService
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
    }

    private func setupView() {
        view.backgroundColor = .backgroundYandex

        let textLabel = UILabel()
        textLabel.text = text
        textLabel.numberOfLines = 0
        textLabel.textAlignment = .center
        textLabel.adjustsFontSizeToFitWidth = true
        textLabel.minimumScaleFactor = 0.45
        textLabel.font = UIFont(name: "YSDisplay-Bold", size: 40) ?? .systemFont(ofSize: 40, weight: .bold)
        textLabel.translatesAutoresizingMaskIntoConstraints = false

        let playButton = UIButton(type: .system)
        var playConfiguration = UIButton.Configuration.filled()
        playConfiguration.title = "Воспроизвести"
        playConfiguration.baseForegroundColor = .black
        playConfiguration.baseBackgroundColor = .yellowYandex
        playConfiguration.cornerStyle = .large
        playButton.configuration = playConfiguration
        playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)
        playButton.translatesAutoresizingMaskIntoConstraints = false

        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = .black
        closeButton.backgroundColor = .textField
        closeButton.layer.cornerRadius = 24
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(textLabel)
        view.addSubview(playButton)
        view.addSubview(closeButton)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            closeButton.widthAnchor.constraint(equalToConstant: 48),
            closeButton.heightAnchor.constraint(equalTo: closeButton.widthAnchor),

            textLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            textLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            textLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            playButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            playButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            playButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            playButton.heightAnchor.constraint(equalToConstant: 64)
        ])
    }

    @objc private func playTapped() {
        textToSpeechService.speak(text, language: "ru-RU")
    }

    @objc private func closeTapped() {
        textToSpeechService.stop()
        dismiss(animated: true)
    }
}
