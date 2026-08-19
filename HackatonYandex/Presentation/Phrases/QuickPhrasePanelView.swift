//
//  QuickPhrasePanelView.swift
//  HackatonYandex
//
//  Created by Rodion Kholodov.
//

import UIKit

@MainActor
protocol QuickPhrasePanelViewInput: AnyObject {
    func render(_ viewModel: QuickPhrasePanelViewModel)
}

struct QuickPhrasePanelViewModel {
    struct Item {
        let id: String
        let title: String
    }

    enum State {
        case loading
        case empty
        case content([Item])
        case error(String)
    }

    let state: State
}

@MainActor
final class QuickPhrasePanelPresenter {
    private weak var view: QuickPhrasePanelViewInput?
    private let fetchPhrasesUseCase: FetchPhrasesUseCase
    private let recordPhraseUsageUseCase: RecordPhraseUsageUseCase
    private var phrases: [Phrase] = []

    init(
        view: QuickPhrasePanelViewInput,
        fetchPhrasesUseCase: FetchPhrasesUseCase,
        recordPhraseUsageUseCase: RecordPhraseUsageUseCase
    ) {
        self.view = view
        self.fetchPhrasesUseCase = fetchPhrasesUseCase
        self.recordPhraseUsageUseCase = recordPhraseUsageUseCase
    }

    func loadPhrases() {
        view?.render(QuickPhrasePanelViewModel(state: .loading))

        Task { [weak self] in
            guard let self else { return }

            do {
                let phrases = try await fetchPhrasesUseCase.execute()
                let items = phrases.map {
                    QuickPhrasePanelViewModel.Item(
                        id: $0.id,
                        title: $0.text
                    )
                }

                await MainActor.run {
                    self.phrases = phrases
                    self.view?.render(
                        QuickPhrasePanelViewModel(
                            state: items.isEmpty ? .empty : .content(items)
                        )
                    )
                }
            } catch {
                AppLogger.error("Failed to load quick phrases: \(error.localizedDescription)")
                await MainActor.run {
                    self.view?.render(
                        QuickPhrasePanelViewModel(
                            state: .error("Не удалось загрузить фразы.")
                        )
                    )
                }
            }
        }
    }

    func didUsePhrase(id: String) {
        guard let phrase = phrases.first(where: { $0.id == id }) else {
            return
        }

        Task { [recordPhraseUsageUseCase] in
            do {
                try await recordPhraseUsageUseCase.execute(phrase)
            } catch {
                AppLogger.error("Failed to record phrase usage: \(error.localizedDescription)")
            }
        }
    }
}

final class QuickPhrasePanelView: UIView {
    var onSelectPhrase: ((String) -> Void)?

    private lazy var presenter = QuickPhrasePanelPresenter(
        view: self,
        fetchPhrasesUseCase: fetchPhrasesUseCase,
        recordPhraseUsageUseCase: recordPhraseUsageUseCase
    )

    private let fetchPhrasesUseCase: FetchPhrasesUseCase
    private let recordPhraseUsageUseCase: RecordPhraseUsageUseCase
    private var items: [QuickPhrasePanelViewModel.Item] = []

    private let collectionView: UICollectionView
    private let stateLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)

    init(
        fetchPhrasesUseCase: FetchPhrasesUseCase,
        recordPhraseUsageUseCase: RecordPhraseUsageUseCase
    ) {
        self.fetchPhrasesUseCase = fetchPhrasesUseCase
        self.recordPhraseUsageUseCase = recordPhraseUsageUseCase

        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 0
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)

        super.init(frame: .zero)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reloadPhrases() {
        presenter.loadPhrases()
    }

    private func setupView() {
        backgroundColor = .white
        layer.borderWidth = 0.5
        layer.borderColor = UIColor.separator.cgColor

        collectionView.backgroundColor = .white
        collectionView.alwaysBounceVertical = true
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(QuickPhrasePanelCell.self, forCellWithReuseIdentifier: QuickPhrasePanelCell.reuseID)
        collectionView.translatesAutoresizingMaskIntoConstraints = false

        stateLabel.numberOfLines = 0
        stateLabel.textAlignment = .center
        stateLabel.textColor = .secondaryLabel
        stateLabel.font = UIFont(name: "YSDisplay-Medium", size: 17)
            ?? .systemFont(ofSize: 17, weight: .medium)
        stateLabel.translatesAutoresizingMaskIntoConstraints = false

        activityIndicator.translatesAutoresizingMaskIntoConstraints = false

        addSubview(collectionView)
        addSubview(stateLabel)
        addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stateLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            stateLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            stateLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            stateLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),

            activityIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
}

extension QuickPhrasePanelView: QuickPhrasePanelViewInput {
    func render(_ viewModel: QuickPhrasePanelViewModel) {
        switch viewModel.state {
        case .loading:
            items = []
            collectionView.reloadData()
            collectionView.isHidden = true
            stateLabel.isHidden = true
            activityIndicator.startAnimating()
        case .empty:
            items = []
            collectionView.reloadData()
            collectionView.isHidden = true
            activityIndicator.stopAnimating()
            stateLabel.text = "Фраз пока нет"
            stateLabel.isHidden = false
        case .content(let items):
            self.items = items
            activityIndicator.stopAnimating()
            stateLabel.isHidden = true
            collectionView.isHidden = false
            collectionView.reloadData()
        case .error(let message):
            items = []
            collectionView.reloadData()
            collectionView.isHidden = true
            activityIndicator.stopAnimating()
            stateLabel.text = message
            stateLabel.isHidden = false
        }
    }
}

extension QuickPhrasePanelView: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: QuickPhrasePanelCell.reuseID,
            for: indexPath
        )

        guard let phraseCell = cell as? QuickPhrasePanelCell else {
            return cell
        }

        phraseCell.configure(text: items[indexPath.item].title)
        return phraseCell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let item = items[indexPath.item]
        presenter.didUsePhrase(id: item.id)
        onSelectPhrase?(item.title)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        let width = floor(collectionView.bounds.width / 3)
        return CGSize(width: width, height: 102)
    }
}

private final class QuickPhrasePanelCell: UICollectionViewCell {
    static let reuseID = "QuickPhrasePanelCell"

    private let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(text: String) {
        titleLabel.text = text
    }

    private func setupView() {
        backgroundColor = .white
        contentView.backgroundColor = .white
        contentView.layer.borderWidth = 0.5
        contentView.layer.borderColor = UIColor.separator.cgColor

        titleLabel.numberOfLines = 3
        titleLabel.textAlignment = .center
        titleLabel.textColor = .black
        titleLabel.font = UIFont(name: "YSDisplay-Medium", size: 17)
            ?? .systemFont(ofSize: 17, weight: .medium)
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.75
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8)
        ])
    }
}
