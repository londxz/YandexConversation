//
//  SettingsCells.swift
//  HackatonYandex
//
//  Created by Rodion Kholodov.
//

import UIKit

final class SettingsValueCell: UITableViewCell {
    static let reuseID = "SettingsValueCell"

    func configure(with row: SettingsViewModel.Row) {
        var content = UIListContentConfiguration.subtitleCell()
        content.text = row.title
        content.secondaryText = row.subtitle
        content.textProperties.font = Self.scaledFont(named: "YSDisplay-Medium", size: 17, textStyle: .body, fallbackWeight: .medium)
        content.textProperties.color = row.isDestructive ? .systemRed : .label
        content.textProperties.numberOfLines = 0
        content.secondaryTextProperties.font = Self.scaledFont(named: "YSText-Regular", size: 14, textStyle: .subheadline, fallbackWeight: .regular)
        content.secondaryTextProperties.color = .secondaryLabel
        content.secondaryTextProperties.numberOfLines = 0

        if case .disclosure(let value) = row.accessory {
            content.secondaryText = value ?? row.subtitle
            accessoryType = .disclosureIndicator
        } else {
            accessoryType = .none
        }

        contentConfiguration = content
        backgroundColor = .backgroundYandex
        selectionStyle = row.isEnabled ? .default : .none
        isUserInteractionEnabled = row.isEnabled
        contentView.alpha = row.isEnabled ? 1 : 0.45
        accessibilityTraits = row.isEnabled ? [.button] : [.notEnabled]
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        contentConfiguration = nil
        accessoryType = .none
        isUserInteractionEnabled = true
        contentView.alpha = 1
        accessibilityTraits = []
    }

    private static func scaledFont(named name: String, size: CGFloat, textStyle: UIFont.TextStyle, fallbackWeight: UIFont.Weight) -> UIFont {
        let baseFont = UIFont(name: name, size: size) ?? UIFont.systemFont(ofSize: size, weight: fallbackWeight)
        return UIFontMetrics(forTextStyle: textStyle).scaledFont(for: baseFont)
    }
}

final class SettingsSwitchCell: UITableViewCell {
    static let reuseID = "SettingsSwitchCell"

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let toggle = UISwitch()
    private var onValueChanged: ((Bool) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    func configure(with row: SettingsViewModel.Row, isOn: Bool, onValueChanged: @escaping (Bool) -> Void) {
        titleLabel.text = row.title
        subtitleLabel.text = row.subtitle
        subtitleLabel.isHidden = row.subtitle == nil
        toggle.setOn(isOn, animated: false)
        toggle.isEnabled = row.isEnabled
        self.onValueChanged = onValueChanged
        contentView.alpha = row.isEnabled ? 1 : 0.45
        isUserInteractionEnabled = row.isEnabled
        isAccessibilityElement = false
        toggle.accessibilityLabel = row.title
        toggle.accessibilityHint = row.subtitle
        toggle.accessibilityValue = isOn ? "Включено" : "Выключено"
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onValueChanged = nil
        contentView.alpha = 1
        isUserInteractionEnabled = true
    }

    private func setupView() {
        backgroundColor = .backgroundYandex
        selectionStyle = .none

        titleLabel.font = Self.scaledFont(named: "YSDisplay-Medium", size: 17, textStyle: .body, fallbackWeight: .medium)
        titleLabel.numberOfLines = 0
        titleLabel.adjustsFontForContentSizeCategory = true

        subtitleLabel.font = Self.scaledFont(named: "YSText-Regular", size: 14, textStyle: .subheadline, fallbackWeight: .regular)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 0
        subtitleLabel.adjustsFontForContentSizeCategory = true

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = 3
        textStack.translatesAutoresizingMaskIntoConstraints = false

        toggle.onTintColor = .yellowYandex
        toggle.addTarget(self, action: #selector(toggleChanged), for: .valueChanged)
        toggle.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(textStack)
        contentView.addSubview(toggle)

        NSLayoutConstraint.activate([
            textStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            textStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -16),
            textStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            toggle.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            toggle.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20)
        ])
    }

    @objc private func toggleChanged() {
        toggle.accessibilityValue = toggle.isOn ? "Включено" : "Выключено"
        onValueChanged?(toggle.isOn)
    }

    private static func scaledFont(named name: String, size: CGFloat, textStyle: UIFont.TextStyle, fallbackWeight: UIFont.Weight) -> UIFont {
        let baseFont = UIFont(name: name, size: size) ?? UIFont.systemFont(ofSize: size, weight: fallbackWeight)
        return UIFontMetrics(forTextStyle: textStyle).scaledFont(for: baseFont)
    }
}

final class SettingsSliderCell: UITableViewCell {
    static let reuseID = "SettingsSliderCell"

    private let titleLabel = UILabel()
    private let valueLabel = UILabel()
    private let slider = UISlider()
    private var step: Float = 0.05
    private var valueFormat: SettingsViewModel.Slider.ValueFormat = .percentage
    private var onEditingEnded: ((Float) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    func configure(with row: SettingsViewModel.Row, sliderViewModel: SettingsViewModel.Slider, onEditingEnded: @escaping (Float) -> Void) {
        titleLabel.text = row.title
        valueLabel.text = sliderViewModel.valueText
        slider.minimumValue = sliderViewModel.minimumValue
        slider.maximumValue = sliderViewModel.maximumValue
        slider.setValue(sliderViewModel.value, animated: false)
        slider.isEnabled = row.isEnabled
        step = sliderViewModel.step
        valueFormat = sliderViewModel.valueFormat
        self.onEditingEnded = onEditingEnded
        contentView.alpha = row.isEnabled ? 1 : 0.45
        isAccessibilityElement = false
        slider.accessibilityLabel = row.title
        slider.accessibilityValue = sliderViewModel.valueText
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onEditingEnded = nil
        contentView.alpha = 1
    }

    private func setupView() {
        backgroundColor = .backgroundYandex
        selectionStyle = .none

        titleLabel.font = Self.scaledFont(named: "YSDisplay-Medium", size: 17, textStyle: .body, fallbackWeight: .medium)
        titleLabel.adjustsFontForContentSizeCategory = true
        valueLabel.font = Self.scaledFont(named: "YSText-Regular", size: 15, textStyle: .subheadline, fallbackWeight: .regular)
        valueLabel.textColor = .secondaryLabel
        valueLabel.textAlignment = .right
        valueLabel.adjustsFontForContentSizeCategory = true

        slider.minimumTrackTintColor = .black
        slider.maximumTrackTintColor = .systemGray4
        slider.thumbTintColor = .yellowYandex
        slider.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)
        slider.addTarget(self, action: #selector(sliderEditingEnded), for: [.touchUpInside, .touchUpOutside, .touchCancel])

        [titleLabel, valueLabel, slider].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: valueLabel.leadingAnchor, constant: -12),
            valueLabel.firstBaselineAnchor.constraint(equalTo: titleLabel.firstBaselineAnchor),
            valueLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            valueLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 56),
            slider.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            slider.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            slider.trailingAnchor.constraint(equalTo: valueLabel.trailingAnchor),
            slider.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])
    }

    @objc private func sliderChanged() {
        let steppedValue = (slider.value / step).rounded() * step
        slider.value = steppedValue
        let text = formattedValue(steppedValue)
        valueLabel.text = text
        slider.accessibilityValue = text
    }

    @objc private func sliderEditingEnded() {
        onEditingEnded?(slider.value)
    }

    private func formattedValue(_ value: Float) -> String {
        switch valueFormat {
        case .speechRate:
            return String(format: "%.2f×", value)
        case .percentage:
            return "\(Int((value * 100).rounded()))%"
        }
    }

    private static func scaledFont(named name: String, size: CGFloat, textStyle: UIFont.TextStyle, fallbackWeight: UIFont.Weight) -> UIFont {
        let baseFont = UIFont(name: name, size: size) ?? UIFont.systemFont(ofSize: size, weight: fallbackWeight)
        return UIFontMetrics(forTextStyle: textStyle).scaledFont(for: baseFont)
    }
}
