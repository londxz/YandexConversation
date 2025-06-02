//
//  smslogic.swift
//  HackatonYandex
//
//  Created by Родион Холодов on 02.06.2025.
//

import UIKit

struct ChatMessage {
    let text: String
    let isIncoming: Bool // если нужно различать отправленные/полученные
}

class ChatMessageCell: UITableViewCell {
    private let messageLabel = UILabel()
    private let bubbleBackgroundView = UIView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none

        bubbleBackgroundView.layer.cornerRadius = 14
        bubbleBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(bubbleBackgroundView)

        messageLabel.numberOfLines = 0
        messageLabel.font = UIFont(name: "YSDisplay-Medium", size: 18)
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(messageLabel)

        NSLayoutConstraint.activate([
            messageLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            messageLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            messageLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 250),

            bubbleBackgroundView.topAnchor.constraint(equalTo: messageLabel.topAnchor, constant: -8),
            bubbleBackgroundView.leadingAnchor.constraint(equalTo: messageLabel.leadingAnchor, constant: -12),
            bubbleBackgroundView.bottomAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 8),
            bubbleBackgroundView.trailingAnchor.constraint(equalTo: messageLabel.trailingAnchor, constant: 12)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with message: ChatMessage) {
        messageLabel.text = message.text
        if message.isIncoming {
            messageLabel.textColor = .black
            bubbleBackgroundView.backgroundColor = UIColor(white: 0.9, alpha: 1)
            messageLabel.textAlignment = .left
            messageLabel.textAlignment = .left
            messageLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16).isActive = true
            messageLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -80).isActive = true
        } else {
            messageLabel.textColor = .white
            bubbleBackgroundView.backgroundColor = .systemBlue
            messageLabel.textAlignment = .right
            messageLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16).isActive = true
            messageLabel.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 80).isActive = true
        }
    }
}


