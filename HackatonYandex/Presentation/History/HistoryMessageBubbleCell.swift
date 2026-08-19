//
//  HistoryMessageBubbleCell.swift
//  HackatonYandex
//
//  Created by Rodion Kholodov.
//

import UIKit

final class HistoryMessageBubbleCell: UITableViewCell {
    static let reuseID = "HistoryMessageBubbleCell"

    private let bubbleView = UIView()
    private let speakerLabel = UILabel()
    private let messageLabel = UILabel()
    private let timeLabel = UILabel()
    private var leadingConstraint: NSLayoutConstraint?
    private var trailingConstraint: NSLayoutConstraint?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(message: HistoryDetailViewModel.Message) {
        speakerLabel.text = message.speakerLabel
        speakerLabel.isHidden = message.speakerLabel == nil || message.isOutgoing
        messageLabel.text = message.text
        timeLabel.text = message.dateText

        bubbleView.backgroundColor = message.isOutgoing ? .outgoingMessageBackground : .white
        bubbleView.layer.borderWidth = message.isOutgoing ? 1 : 0
        bubbleView.layer.borderColor = UIColor.outgoingMessageBorder.cgColor

        leadingConstraint?.isActive = !message.isOutgoing
        trailingConstraint?.isActive = message.isOutgoing
    }

    private func setupView() {
        backgroundColor = .chatBackground
        contentView.backgroundColor = .chatBackground
        selectionStyle = .none

        bubbleView.layer.cornerRadius = 18
        bubbleView.translatesAutoresizingMaskIntoConstraints = false

        speakerLabel.textColor = .systemBlue
        speakerLabel.font = UIFont(name: "YSDisplay-Medium", size: 13)
            ?? .systemFont(ofSize: 13, weight: .medium)
        speakerLabel.translatesAutoresizingMaskIntoConstraints = false

        messageLabel.numberOfLines = 0
        messageLabel.textColor = .black
        messageLabel.font = UIFont(name: "YSDisplay-Medium", size: 22)
            ?? .systemFont(ofSize: 22, weight: .medium)
        messageLabel.translatesAutoresizingMaskIntoConstraints = false

        timeLabel.textColor = UIColor.black.withAlphaComponent(0.35)
        timeLabel.font = UIFont(name: "YSDisplay-Medium", size: 14)
            ?? .systemFont(ofSize: 14, weight: .medium)
        timeLabel.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(bubbleView)
        bubbleView.addSubview(speakerLabel)
        bubbleView.addSubview(messageLabel)
        bubbleView.addSubview(timeLabel)

        leadingConstraint = bubbleView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12)
        trailingConstraint = bubbleView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12)

        NSLayoutConstraint.activate([
            bubbleView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            bubbleView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            bubbleView.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.78),

            speakerLabel.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 12),
            speakerLabel.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 16),
            speakerLabel.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -16),

            messageLabel.topAnchor.constraint(equalTo: speakerLabel.bottomAnchor, constant: 4),
            messageLabel.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 16),
            messageLabel.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -16),
            messageLabel.bottomAnchor.constraint(lessThanOrEqualTo: timeLabel.topAnchor, constant: -6),

            timeLabel.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -16),
            timeLabel.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -10),
            timeLabel.leadingAnchor.constraint(greaterThanOrEqualTo: bubbleView.leadingAnchor, constant: 16)
        ])
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
