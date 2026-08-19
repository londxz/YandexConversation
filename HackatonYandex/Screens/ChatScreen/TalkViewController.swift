//
//  TalkViewController.swift
//  HackatonYandex
//
//  Created by Rodion Kholodov.
//

import UIKit

@MainActor
protocol TalkViewControllerDelegate: AnyObject {
    func talkViewControllerDidAppearEmpty(_ viewController: TalkViewController)
    func talkViewController(_ viewController: TalkViewController, didRequestLargeText text: String)
    func talkViewController(_ viewController: TalkViewController, didRequestSpeak text: String)
}

class TalkViewController: UIViewController {
    weak var delegate: TalkViewControllerDelegate?

    private static let messageTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private var hasMessages = false
    private var transcriptFontScale: CGFloat = 1
    private var transcriptLabels: [UILabel: CGFloat] = [:]

    init() {
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .chatBackground
        setupMessagesView()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !hasMessages else { return }

        delegate?.talkViewControllerDidAppearEmpty(self)
    }

    func appendUserMessage(_ text: String, createdAt: Date = Date()) {
        appendOutgoingMessage(text, createdAt: createdAt)
    }

    func appendIncomingMessage(_ text: String, speakerLabel: String = "Говорящий 1") {
        appendIncomingBubble(text, speakerLabel: speakerLabel)
    }

    func applyTranscriptFontScale(_ scale: Float) {
        transcriptFontScale = CGFloat(min(max(scale, 0.85), 1.60))
        for (label, baseSize) in transcriptLabels {
            label.font = transcriptFont(baseSize: baseSize)
        }
    }

    func clearMessages() {
        guard isViewLoaded else {
            hasMessages = false
            return
        }

        stackView.arrangedSubviews.forEach { view in
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        transcriptLabels.removeAll()
        hasMessages = false
        scrollView.setContentOffset(.zero, animated: false)
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

    private func appendOutgoingMessage(_ text: String, createdAt: Date) {
        hasMessages = true

        let rowView = UIView()
        rowView.translatesAutoresizingMaskIntoConstraints = false

        let voiceButton = UIButton(type: .system)
        voiceButton.backgroundColor = .backgroundYandex
        voiceButton.layer.cornerRadius = 21
        voiceButton.accessibilityLabel = "Озвучить сообщение"
        voiceButton.translatesAutoresizingMaskIntoConstraints = false

        let voiceIconView = UIImageView(image: UIImage(named: "to_voice")?.withRenderingMode(.alwaysOriginal))
        voiceIconView.contentMode = .scaleAspectFit
        voiceIconView.isUserInteractionEnabled = false
        voiceIconView.translatesAutoresizingMaskIntoConstraints = false

        voiceButton.addAction(
            UIAction { [weak self] _ in
                guard let self else { return }
                self.delegate?.talkViewController(self, didRequestSpeak: text)
            },
            for: .touchUpInside
        )

        let bubbleView = UIView()
        bubbleView.layer.cornerRadius = 18
        bubbleView.layer.borderWidth = 1
        bubbleView.layer.borderColor = UIColor.outgoingMessageBorder.cgColor
        bubbleView.backgroundColor = .outgoingMessageBackground
        bubbleView.translatesAutoresizingMaskIntoConstraints = false

        let messageLabel = UILabel()
        messageLabel.text = text
        messageLabel.numberOfLines = 0
        messageLabel.textColor = .black
        messageLabel.font = transcriptFont(baseSize: 24)
        messageLabel.adjustsFontForContentSizeCategory = true
        transcriptLabels[messageLabel] = 24
        messageLabel.translatesAutoresizingMaskIntoConstraints = false

        let menuButton = UIButton(type: .system)
        menuButton.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        menuButton.tintColor = .black
        menuButton.transform = CGAffineTransform(rotationAngle: .pi / 2)
        menuButton.showsMenuAsPrimaryAction = true
        menuButton.menu = makeOutgoingMessageMenu(text)
        menuButton.accessibilityLabel = "Открыть меню сообщения"
        menuButton.translatesAutoresizingMaskIntoConstraints = false

        let timeLabel = UILabel()
        timeLabel.text = Self.messageTimeFormatter.string(from: createdAt)
        timeLabel.textColor = UIColor.black.withAlphaComponent(0.35)
        timeLabel.font = UIFont(name: "YSDisplay-Medium", size: 14)
            ?? .systemFont(ofSize: 14, weight: .medium)
        timeLabel.translatesAutoresizingMaskIntoConstraints = false

        bubbleView.addSubview(messageLabel)
        bubbleView.addSubview(menuButton)
        bubbleView.addSubview(timeLabel)
        voiceButton.addSubview(voiceIconView)
        rowView.addSubview(voiceButton)
        rowView.addSubview(bubbleView)
        stackView.addArrangedSubview(rowView)

        NSLayoutConstraint.activate([
            bubbleView.topAnchor.constraint(equalTo: rowView.topAnchor),
            bubbleView.trailingAnchor.constraint(equalTo: rowView.trailingAnchor),
            bubbleView.bottomAnchor.constraint(equalTo: rowView.bottomAnchor),
            bubbleView.widthAnchor.constraint(lessThanOrEqualTo: rowView.widthAnchor, multiplier: 0.78),

            voiceButton.leadingAnchor.constraint(greaterThanOrEqualTo: rowView.leadingAnchor),
            voiceButton.trailingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: -10),
            voiceButton.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor),
            voiceButton.widthAnchor.constraint(equalToConstant: 42),
            voiceButton.heightAnchor.constraint(equalTo: voiceButton.widthAnchor),

            voiceIconView.centerXAnchor.constraint(equalTo: voiceButton.centerXAnchor),
            voiceIconView.centerYAnchor.constraint(equalTo: voiceButton.centerYAnchor),
            voiceIconView.widthAnchor.constraint(equalToConstant: 17),
            voiceIconView.heightAnchor.constraint(equalTo: voiceIconView.widthAnchor),

            menuButton.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 10),
            menuButton.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -10),
            menuButton.widthAnchor.constraint(equalToConstant: 34),
            menuButton.heightAnchor.constraint(equalTo: menuButton.widthAnchor),

            messageLabel.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 16),
            messageLabel.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 18),
            messageLabel.trailingAnchor.constraint(equalTo: menuButton.leadingAnchor, constant: -8),
            messageLabel.bottomAnchor.constraint(lessThanOrEqualTo: timeLabel.topAnchor, constant: -4),

            timeLabel.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -18),
            timeLabel.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -12),
            timeLabel.leadingAnchor.constraint(greaterThanOrEqualTo: bubbleView.leadingAnchor, constant: 18)
        ])

        view.layoutIfNeeded()
        scrollToBottom()
    }

    private func appendIncomingBubble(_ text: String, speakerLabel: String?) {
        hasMessages = true

        let rowView = UIView()
        rowView.translatesAutoresizingMaskIntoConstraints = false

        let bubbleView = UIView()
        bubbleView.layer.cornerRadius = 14
        bubbleView.backgroundColor = .white
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
        messageLabel.font = transcriptFont(baseSize: 18)
        messageLabel.adjustsFontForContentSizeCategory = true
        transcriptLabels[messageLabel] = 18
        messageStack.addArrangedSubview(messageLabel)

        bubbleView.addSubview(messageStack)
        rowView.addSubview(bubbleView)
        stackView.addArrangedSubview(rowView)

        NSLayoutConstraint.activate([
            bubbleView.topAnchor.constraint(equalTo: rowView.topAnchor),
            bubbleView.bottomAnchor.constraint(equalTo: rowView.bottomAnchor),
            bubbleView.widthAnchor.constraint(lessThanOrEqualTo: rowView.widthAnchor, multiplier: 0.82),
            bubbleView.leadingAnchor.constraint(equalTo: rowView.leadingAnchor),

            messageStack.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 10),
            messageStack.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 12),
            messageStack.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -12),
            messageStack.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -10)
        ])

        view.layoutIfNeeded()
        scrollToBottom()
    }

    private func makeOutgoingMessageMenu(_ text: String) -> UIMenu {
        let largeTextAction = UIAction(
            title: "Показать крупно",
            image: UIImage(systemName: "textformat.size.larger")
        ) { [weak self] _ in
            guard let self else { return }
            self.delegate?.talkViewController(self, didRequestLargeText: text)
        }

        let speakAction = UIAction(
            title: "Озвучить",
            image: UIImage(named: "to_voice")
        ) { [weak self] _ in
            guard let self else { return }
            self.delegate?.talkViewController(self, didRequestSpeak: text)
        }

        let copyAction = UIAction(
            title: "Скопировать",
            image: UIImage(systemName: "doc.on.doc")
        ) { _ in
            UIPasteboard.general.string = text
        }

        return UIMenu(children: [largeTextAction, speakAction, copyAction])
    }

    private func scrollToBottom() {
        let bottomOffset = CGPoint(
            x: 0,
            y: max(0, scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom)
        )
        scrollView.setContentOffset(bottomOffset, animated: true)
    }

    private func transcriptFont(baseSize: CGFloat) -> UIFont {
        let size = baseSize * transcriptFontScale
        let baseFont = UIFont(name: "YSDisplay-Medium", size: size)
            ?? .systemFont(ofSize: size, weight: .medium)
        return UIFontMetrics(forTextStyle: .body).scaledFont(for: baseFont)
    }
}

private extension UIColor {
    static let outgoingMessageBackground = UIColor(
        red: 0.98,
        green: 0.95,
        blue: 0.82,
        alpha: 1
    )

    static let outgoingMessageBorder = UIColor(
        red: 0.72,
        green: 0.68,
        blue: 0.54,
        alpha: 0.45
    )
}
