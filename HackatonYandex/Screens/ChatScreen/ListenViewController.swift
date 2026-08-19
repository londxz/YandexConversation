//
//  ListenViewController.swift
//  HackatonYandex
//
//  Created by Rodion Kholodov.
//

import UIKit

class ListenViewController: UIViewController {
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private let emptyStateLabel = UILabel()
    private var transcriptFontScale: CGFloat = 1
    private var transcriptLabels: [UILabel] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .backgroundYandex
        setupTranscriptView()
    }

    func appendSpeech(_ text: String, speakerLabel: String = "Говорящий 1") {
        emptyStateLabel.isHidden = true

        let speakerLabelView = UILabel()
        speakerLabelView.text = speakerLabel
        speakerLabelView.textColor = .systemBlue
        speakerLabelView.font = UIFont(name: "YSDisplay-Medium", size: 13) ?? .systemFont(ofSize: 13, weight: .medium)

        let textLabel = UILabel()
        textLabel.text = text
        textLabel.numberOfLines = 0
        textLabel.textColor = .black
        textLabel.font = transcriptFont()
        textLabel.adjustsFontForContentSizeCategory = true
        transcriptLabels.append(textLabel)

        let messageStack = UIStackView(arrangedSubviews: [speakerLabelView, textLabel])
        messageStack.axis = .vertical
        messageStack.spacing = 4
        messageStack.translatesAutoresizingMaskIntoConstraints = false

        stackView.addArrangedSubview(messageStack)
        view.layoutIfNeeded()
        scrollToBottom()
    }

    func clearTranscript() {
        guard isViewLoaded else { return }

        stackView.arrangedSubviews.forEach { view in
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        transcriptLabels.removeAll()
        emptyStateLabel.isHidden = false
        scrollView.setContentOffset(.zero, animated: false)
    }

    func applyTranscriptFontScale(_ scale: Float) {
        transcriptFontScale = CGFloat(min(max(scale, 0.85), 1.60))
        transcriptLabels.forEach { $0.font = transcriptFont() }
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
        emptyStateLabel.font = UIFont(name: "YSDisplay-Medium", size: 22) ?? .systemFont(ofSize: 22, weight: .medium)
        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(scrollView)
        scrollView.addSubview(stackView)
        view.addSubview(emptyStateLabel)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -16),
            stackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            emptyStateLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyStateLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            emptyStateLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32)
        ])
    }

    private func scrollToBottom() {
        let bottomOffset = CGPoint(
            x: 0,
            y: max(0, scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom)
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
