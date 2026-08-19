//
//  ListenViewController.swift
//  HackatonYandex
//
//  Created by Rodion Kholodov.
//

import UIKit

final class ListenViewController: UIViewController {
    var presenter: ListenPresenter?

    private let statusLabel = UILabel()
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private let emptyStateLabel = UILabel()
    private let listeningControlButton = UIButton(type: .system)
    private var partialMessageView: UIView?
    private weak var partialTextLabel: UILabel?
    private var transcriptFontScale: CGFloat = 1
    private var transcriptLabels: [UILabel] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .backgroundYandex
        setupStatusLabel()
        setupTranscriptView()
        setupListeningControl()
        presenter?.viewDidLoad()
    }

    func appendSpeech(_ text: String, speakerLabel: String = "Говорящий 1") {
        clearPartialSpeech()
        let message = makeMessageView(
            text: text,
            speakerLabel: speakerLabel,
            isPartial: false
        )
        stackView.addArrangedSubview(message.view)
        transcriptLabels.append(message.textLabel)
        updateEmptyState()
        view.layoutIfNeeded()
        scrollToBottom()
    }

    func clearTranscript() {
        guard isViewLoaded else { return }

        stackView.arrangedSubviews.forEach { arrangedView in
            stackView.removeArrangedSubview(arrangedView)
            arrangedView.removeFromSuperview()
        }
        partialMessageView = nil
        partialTextLabel = nil
        transcriptLabels.removeAll()
        updateEmptyState()
        scrollView.setContentOffset(.zero, animated: false)
        presenter?.clearTranscriptState()
    }

    func applyTranscriptFontScale(_ scale: Float) {
        transcriptFontScale = CGFloat(min(max(scale, 0.85), 1.60))
        transcriptLabels.forEach { $0.font = transcriptFont() }
        partialTextLabel?.font = transcriptFont()
    }

    @objc private func listeningControlTapped() {
        presenter?.didTapPauseResume()
    }

    private func setupStatusLabel() {
        statusLabel.numberOfLines = 2
        statusLabel.textAlignment = .center
        statusLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 2),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            statusLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 24)
        ])
    }

    private func setupTranscriptView() {
        scrollView.alwaysBounceVertical = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        stackView.axis = .vertical
        stackView.spacing = 20
        stackView.translatesAutoresizingMaskIntoConstraints = false

        emptyStateLabel.text = "Речь вокруг вас появится здесь"
        emptyStateLabel.numberOfLines = 0
        emptyStateLabel.textAlignment = .center
        emptyStateLabel.textColor = .secondaryLabel
        emptyStateLabel.font = UIFont(name: "YSDisplay-Medium", size: 22)
            ?? .systemFont(ofSize: 22, weight: .medium)
        emptyStateLabel.adjustsFontForContentSizeCategory = true
        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(scrollView)
        scrollView.addSubview(stackView)
        view.addSubview(emptyStateLabel)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 12),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -84),
            stackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            emptyStateLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyStateLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            emptyStateLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32)
        ])
    }

    private func setupListeningControl() {
        listeningControlButton.backgroundColor = UIColor.systemGray6
        listeningControlButton.tintColor = .label
        listeningControlButton.layer.cornerRadius = 26
        listeningControlButton.addTarget(
            self,
            action: #selector(listeningControlTapped),
            for: .touchUpInside
        )
        listeningControlButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(listeningControlButton)

        NSLayoutConstraint.activate([
            listeningControlButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            listeningControlButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            listeningControlButton.widthAnchor.constraint(equalToConstant: 52),
            listeningControlButton.heightAnchor.constraint(equalToConstant: 52)
        ])
    }

    private func makeMessageView(
        text: String,
        speakerLabel: String,
        isPartial: Bool
    ) -> (view: UIView, textLabel: UILabel) {
        let speakerLabelView = UILabel()
        speakerLabelView.text = speakerLabel
        speakerLabelView.textColor = .systemBlue
        speakerLabelView.font = UIFont(name: "YSDisplay-Medium", size: 13)
            ?? .systemFont(ofSize: 13, weight: .medium)
        speakerLabelView.adjustsFontForContentSizeCategory = true

        let textLabel = UILabel()
        textLabel.text = text
        textLabel.numberOfLines = 0
        textLabel.textColor = isPartial ? .secondaryLabel : .label
        textLabel.font = transcriptFont()
        textLabel.adjustsFontForContentSizeCategory = true
        textLabel.accessibilityLabel = "\(speakerLabel). \(text)"

        let messageStack = UIStackView(arrangedSubviews: [speakerLabelView, textLabel])
        messageStack.axis = .vertical
        messageStack.spacing = 4
        messageStack.alpha = isPartial ? 0.72 : 1
        messageStack.translatesAutoresizingMaskIntoConstraints = false
        return (messageStack, textLabel)
    }

    private func updateEmptyState() {
        emptyStateLabel.isHidden = !stackView.arrangedSubviews.isEmpty
    }

    private func scrollToBottom() {
        let bottomOffset = CGPoint(
            x: 0,
            y: max(
                0,
                scrollView.contentSize.height
                    - scrollView.bounds.height
                    + scrollView.adjustedContentInset.bottom
            )
        )
        scrollView.setContentOffset(bottomOffset, animated: true)
    }

    private func transcriptFont() -> UIFont {
        let size = 24 * transcriptFontScale
        let baseFont = UIFont(name: "YSDisplay-Medium", size: size)
            ?? .systemFont(ofSize: size, weight: .medium)
        return UIFontMetrics(forTextStyle: .body).scaledFont(for: baseFont)
    }
}

extension ListenViewController: ListenView {
    func render(_ viewModel: ListenViewModel) {
        statusLabel.text = viewModel.statusText
        switch viewModel.state {
        case .listening:
            statusLabel.textColor = UIColor(red: 0.16, green: 0.58, blue: 0.05, alpha: 1)
        case .reconnecting, .connecting, .requestingPermission, .pausing:
            statusLabel.textColor = .systemOrange
        case .failed:
            statusLabel.textColor = .systemRed
        case .idle, .paused:
            statusLabel.textColor = .secondaryLabel
        }

        let symbolName = viewModel.showsPauseAction ? "pause.fill" : "mic.fill"
        let configuration = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        listeningControlButton.setImage(
            UIImage(systemName: symbolName, withConfiguration: configuration),
            for: .normal
        )
        listeningControlButton.isEnabled = viewModel.isControlEnabled
        listeningControlButton.alpha = viewModel.isControlEnabled ? 1 : 0.5
        listeningControlButton.accessibilityLabel = viewModel.showsPauseAction
            ? "Приостановить прослушивание"
            : "Возобновить прослушивание"
    }

    func displayPartialSpeech(_ segment: RealtimeSpeechSegment) {
        if let partialTextLabel {
            partialTextLabel.text = segment.text
            partialTextLabel.accessibilityLabel = "\(segment.speakerLabel). \(segment.text)"
        } else {
            let message = makeMessageView(
                text: segment.text,
                speakerLabel: segment.speakerLabel,
                isPartial: true
            )
            partialMessageView = message.view
            partialTextLabel = message.textLabel
            stackView.addArrangedSubview(message.view)
        }
        updateEmptyState()
        view.layoutIfNeeded()
        scrollToBottom()
    }

    func displayFinalSpeech(_ segment: RealtimeSpeechSegment) {
        appendSpeech(segment.text, speakerLabel: segment.speakerLabel)
        UIAccessibility.post(notification: .announcement, argument: segment.text)
    }

    func clearPartialSpeech() {
        guard let partialMessageView else { return }
        stackView.removeArrangedSubview(partialMessageView)
        partialMessageView.removeFromSuperview()
        self.partialMessageView = nil
        partialTextLabel = nil
        updateEmptyState()
    }
}
