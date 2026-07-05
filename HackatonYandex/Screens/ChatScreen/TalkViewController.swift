//
//  TalkViewController.swift
//  HackatonYandex
//
//  Created by Родион Холодов on 01.06.2025.
//

import UIKit

protocol TalkViewControllerDelegate: AnyObject {
    func showStartTypingHint()
    func showMicrophoneHint()
}

class TalkViewController: UIViewController {
    weak var delegate: TalkViewControllerDelegate?

    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private var hasMessages = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .chatBackground
        setupMessagesView()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !hasMessages else { return }

        delegate?.showStartTypingHint()
        delegate?.showMicrophoneHint()
    }

    func appendUserMessage(_ text: String) {
        appendMessage(text, speakerLabel: nil, isIncoming: false)
    }

    func appendIncomingMessage(_ text: String, speakerLabel: String = "Говорящий 1") {
        appendMessage(text, speakerLabel: speakerLabel, isIncoming: true)
    }

    private func setupMessagesView() {
        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .interactive
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        stackView.axis = .vertical
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(scrollView)
        scrollView.addSubview(stackView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 12),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 12),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -12),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -12),
            stackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -24)
        ])
    }

    private func appendMessage(_ text: String, speakerLabel: String?, isIncoming: Bool) {
        hasMessages = true

        let rowView = UIView()
        rowView.translatesAutoresizingMaskIntoConstraints = false

        let bubbleView = UIView()
        bubbleView.layer.cornerRadius = 14
        bubbleView.backgroundColor = isIncoming ? .white : .yellowYandex
        bubbleView.translatesAutoresizingMaskIntoConstraints = false

        let messageStack = UIStackView()
        messageStack.axis = .vertical
        messageStack.spacing = 4
        messageStack.translatesAutoresizingMaskIntoConstraints = false

        if let speakerLabel {
            let speakerLabelView = UILabel()
            speakerLabelView.text = speakerLabel
            speakerLabelView.textColor = .systemBlue
            speakerLabelView.font = UIFont(name: "YSDisplay-Medium", size: 13) ?? .systemFont(ofSize: 13, weight: .medium)
            messageStack.addArrangedSubview(speakerLabelView)
        }

        let messageLabel = UILabel()
        messageLabel.text = text
        messageLabel.numberOfLines = 0
        messageLabel.textColor = .black
        messageLabel.font = UIFont(name: "YSDisplay-Medium", size: 18) ?? .systemFont(ofSize: 18, weight: .medium)
        messageStack.addArrangedSubview(messageLabel)

        bubbleView.addSubview(messageStack)
        rowView.addSubview(bubbleView)
        stackView.addArrangedSubview(rowView)

        let horizontalConstraint = isIncoming
            ? bubbleView.leadingAnchor.constraint(equalTo: rowView.leadingAnchor)
            : bubbleView.trailingAnchor.constraint(equalTo: rowView.trailingAnchor)

        NSLayoutConstraint.activate([
            bubbleView.topAnchor.constraint(equalTo: rowView.topAnchor),
            bubbleView.bottomAnchor.constraint(equalTo: rowView.bottomAnchor),
            bubbleView.widthAnchor.constraint(lessThanOrEqualTo: rowView.widthAnchor, multiplier: 0.82),
            horizontalConstraint,

            messageStack.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 10),
            messageStack.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 12),
            messageStack.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -12),
            messageStack.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -10)
        ])

        view.layoutIfNeeded()
        scrollToBottom()
    }

    private func scrollToBottom() {
        let bottomOffset = CGPoint(
            x: 0,
            y: max(0, scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom)
        )
        scrollView.setContentOffset(bottomOffset, animated: true)
    }
}
