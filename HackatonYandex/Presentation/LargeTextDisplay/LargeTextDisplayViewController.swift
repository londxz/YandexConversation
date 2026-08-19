//
//  LargeTextDisplayViewController.swift
//  HackatonYandex
//
//  Created by Rodion Kholodov.
//

import UIKit

final class LargeTextDisplayViewController: UIViewController {
    private let container: AppContainer
    private let text: String
    private lazy var presenter = LargeTextDisplayPresenter(
        view: self,
        text: text,
        fetchSettingsUseCase: container.fetchSettingsUseCase,
        textToSpeechService: container.textToSpeechService
    )

    private let scrollView = UIScrollView()
    private let scrollContentView = UIView()
    private let textLabel = UILabel()
    private let playButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private let rotateButton = UIButton(type: .system)
    private(set) var isDismissing = false
    var onDismiss: (() -> Void)?

    init(text: String, container: AppContainer) {
        self.text = text
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

    func attach(to parent: UIViewController) {
        parent.addChild(self)
        view.translatesAutoresizingMaskIntoConstraints = false
        parent.view.addSubview(view)

        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: parent.view.topAnchor),
            view.leadingAnchor.constraint(equalTo: parent.view.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: parent.view.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: parent.view.safeAreaLayoutGuide.bottomAnchor)
        ])

        didMove(toParent: parent)
        animatePresentation()
    }

    func dismissImmediately() {
        guard parent != nil else { return }
        presenter.didDismiss()
        view.transform = .identity
        removeFromParentHierarchy()
    }

    private func setupView() {
        view.backgroundColor = .backgroundYandex
        view.accessibilityViewIsModal = true

        scrollView.alwaysBounceVertical = false
        scrollView.showsVerticalScrollIndicator = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        textLabel.numberOfLines = 0
        textLabel.textAlignment = .center
        textLabel.textColor = .label
        textLabel.adjustsFontForContentSizeCategory = true
        textLabel.translatesAutoresizingMaskIntoConstraints = false

        var playConfiguration = UIButton.Configuration.filled()
        playConfiguration.title = "Воспроизвести"
        playConfiguration.image = UIImage(named: "playButtonIcon")?.withRenderingMode(.alwaysOriginal)
        playConfiguration.imagePlacement = .leading
        playConfiguration.imagePadding = 8
        playConfiguration.baseForegroundColor = .black
        playConfiguration.baseBackgroundColor = .yellowYandex
        playConfiguration.cornerStyle = .large
        playButton.configuration = playConfiguration
        playButton.accessibilityLabel = "Озвучить текст"
        playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)
        playButton.translatesAutoresizingMaskIntoConstraints = false

        closeButton.setImage(
            UIImage(named: "dismisIconMicroOnScreen")?.withRenderingMode(.alwaysOriginal),
            for: .normal
        )
        closeButton.accessibilityLabel = "Закрыть крупный текст"
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        rotateButton.setImage(
            UIImage(named: "rotateIconMicroOnScreen")?.withRenderingMode(.alwaysOriginal),
            for: .normal
        )
        rotateButton.accessibilityLabel = "Перевернуть экран"
        rotateButton.addTarget(self, action: #selector(rotateTapped), for: .touchUpInside)
        rotateButton.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(scrollView)
        scrollView.addSubview(scrollContentView)
        scrollContentView.addSubview(textLabel)
        view.addSubview(playButton)
        view.addSubview(closeButton)
        view.addSubview(rotateButton)

        scrollContentView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            playButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            playButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            playButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            playButton.heightAnchor.constraint(equalToConstant: 64),

            closeButton.trailingAnchor.constraint(equalTo: playButton.trailingAnchor),
            closeButton.bottomAnchor.constraint(equalTo: playButton.topAnchor, constant: -24),
            closeButton.widthAnchor.constraint(equalToConstant: 56),
            closeButton.heightAnchor.constraint(equalTo: closeButton.widthAnchor),

            rotateButton.leadingAnchor.constraint(equalTo: playButton.leadingAnchor),
            rotateButton.bottomAnchor.constraint(equalTo: playButton.topAnchor, constant: -24),
            rotateButton.widthAnchor.constraint(equalToConstant: 56),
            rotateButton.heightAnchor.constraint(equalTo: rotateButton.widthAnchor),

            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: closeButton.topAnchor, constant: -20),

            scrollContentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            scrollContentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            scrollContentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            scrollContentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            scrollContentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            scrollContentView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.frameLayoutGuide.heightAnchor),

            textLabel.topAnchor.constraint(greaterThanOrEqualTo: scrollContentView.topAnchor, constant: 12),
            textLabel.leadingAnchor.constraint(equalTo: scrollContentView.leadingAnchor, constant: 24),
            textLabel.trailingAnchor.constraint(equalTo: scrollContentView.trailingAnchor, constant: -24),
            textLabel.bottomAnchor.constraint(lessThanOrEqualTo: scrollContentView.bottomAnchor, constant: -12),
            textLabel.centerYAnchor.constraint(equalTo: scrollContentView.centerYAnchor)
        ])
    }

    private func animatePresentation() {
        guard !UIAccessibility.isReduceMotionEnabled else {
            view.alpha = 1
            view.transform = .identity
            UIAccessibility.post(notification: .screenChanged, argument: textLabel)
            return
        }

        view.alpha = 0
        view.transform = CGAffineTransform(scaleX: 1.04, y: 1.04)
        UIView.animate(
            withDuration: 0.28,
            delay: 0,
            usingSpringWithDamping: 0.88,
            initialSpringVelocity: 0.3,
            options: [.curveEaseInOut]
        ) {
            self.view.alpha = 1
            self.view.transform = .identity
        } completion: { _ in
            UIAccessibility.post(notification: .screenChanged, argument: self.textLabel)
        }
    }

    private func removeFromParentHierarchy() {
        willMove(toParent: nil)
        view.removeFromSuperview()
        removeFromParent()
        onDismiss?()
    }

    @objc private func playTapped() {
        presenter.didTapPlay()
    }

    @objc private func closeTapped() {
        presenter.didTapClose()
    }

    @objc private func rotateTapped() {
        presenter.didTapRotate()
    }
}

extension LargeTextDisplayViewController: LargeTextDisplayView {
    func render(_ viewModel: LargeTextDisplayViewModel) {
        textLabel.text = viewModel.text
        let size = 40 * CGFloat(viewModel.fontScale)
        let baseFont = UIFont(name: "YSDisplay-Bold", size: size)
            ?? .systemFont(ofSize: size, weight: .bold)
        textLabel.font = UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: baseFont)
    }

    func setDisplayRotated(_ isRotated: Bool) {
        let changes = {
            self.view.transform = isRotated
                ? CGAffineTransform(rotationAngle: .pi)
                : .identity
        }

        if UIAccessibility.isReduceMotionEnabled {
            changes()
        } else {
            UIView.animate(withDuration: 0.3, animations: changes)
        }

        rotateButton.accessibilityLabel = isRotated
            ? "Вернуть экран"
            : "Перевернуть экран"
    }

    func dismissLargeTextDisplay() {
        guard !isDismissing else { return }
        isDismissing = true

        let changes = {
            self.view.alpha = 0
            self.view.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
        }
        let completion: (Bool) -> Void = { [weak self] _ in
            self?.removeFromParentHierarchy()
        }

        if UIAccessibility.isReduceMotionEnabled {
            changes()
            completion(true)
        } else {
            UIView.animate(
                withDuration: 0.2,
                delay: 0,
                options: [.curveEaseInOut],
                animations: changes,
                completion: completion
            )
        }
    }
}
