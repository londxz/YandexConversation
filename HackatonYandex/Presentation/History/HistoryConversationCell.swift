//
//  HistoryConversationCell.swift
//  HackatonYandex
//
//  Created by Rodion Kholodov.
//

import UIKit

final class HistoryConversationCell: UITableViewCell {
    static let reuseID = "HistoryConversationCell"

    private let titleLabel = UILabel()
    private let metaLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let menuButton = UIButton(type: .system)
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
        menuButton.menu = nil
    }

    func configure(item: HistoryViewModel.Item, menu: UIMenu) {
        titleLabel.text = item.title
        metaLabel.text = "\(item.dateText) • \(item.messageCountText)"
        subtitleLabel.text = item.subtitle
        menuButton.menu = menu
    }

    private func setupView() {
        backgroundColor = .backgroundYandex
        contentView.backgroundColor = .backgroundYandex
        selectionStyle = .default

        titleLabel.numberOfLines = 2
        titleLabel.textColor = .black
        titleLabel.font = UIFont(name: "YSDisplay-Medium", size: 17)
            ?? .systemFont(ofSize: 17, weight: .medium)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        metaLabel.numberOfLines = 1
        metaLabel.textColor = .secondaryLabel
        metaLabel.font = UIFont(name: "YSText-Regular", size: 13)
            ?? .systemFont(ofSize: 13)
        metaLabel.translatesAutoresizingMaskIntoConstraints = false

        subtitleLabel.numberOfLines = 2
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.font = UIFont(name: "YSText-Regular", size: 14)
            ?? .systemFont(ofSize: 14)
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        menuButton.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        menuButton.tintColor = .black
        menuButton.showsMenuAsPrimaryAction = true
        menuButton.transform = CGAffineTransform(rotationAngle: .pi / 2)
        menuButton.accessibilityLabel = "Открыть меню разговора"
        menuButton.translatesAutoresizingMaskIntoConstraints = false

        separatorView.backgroundColor = .separator
        separatorView.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(titleLabel)
        contentView.addSubview(metaLabel)
        contentView.addSubview(subtitleLabel)
        contentView.addSubview(menuButton)
        contentView.addSubview(separatorView)

        NSLayoutConstraint.activate([
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 94),

            menuButton.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 13),
            menuButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            menuButton.widthAnchor.constraint(equalToConstant: 40),
            menuButton.heightAnchor.constraint(equalTo: menuButton.widthAnchor),

            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 32),
            titleLabel.trailingAnchor.constraint(equalTo: menuButton.leadingAnchor, constant: -8),

            metaLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            metaLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            metaLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            subtitleLabel.topAnchor.constraint(equalTo: metaLabel.bottomAnchor, constant: 4),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            subtitleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14),

            separatorView.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            separatorView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            separatorView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            separatorView.heightAnchor.constraint(equalToConstant: 0.5)
        ])
    }
}
