//
//  ChatComponent.swift
//  HackatonYandex
//
//  Created by Rodion Kholodov.
//

import UIKit

@MainActor
protocol ChatComponentDelegate: AnyObject {
    func chatComponentDidRequestQuickPhrases(_ component: ChatComponent)
    func chatComponentDidRequestStartVoiceRecording(_ component: ChatComponent)
    func chatComponentDidRequestStopVoiceRecording(_ component: ChatComponent)
    func chatComponent(_ component: ChatComponent, didSubmitText text: String)
}

class ChatComponent: UIView {
    weak var delegate: ChatComponentDelegate?

    let textField = UITextField()

    lazy var leftButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(named: "leftChatButton")?.withRenderingMode(.alwaysOriginal), for: .normal)
        btn.translatesAutoresizingMaskIntoConstraints = false

        return btn
    }()
    
    lazy var textRightButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(named: "rightChatButton")?.withRenderingMode(.alwaysOriginal), for: .normal)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.accessibilityLabel = "Отправить сообщение"
        btn.accessibilityHint = "Удерживайте кнопку, чтобы записать речь"

        return btn
    }()

    lazy var speakRightButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(named: "speakRightChatButton")?.withRenderingMode(.alwaysOriginal), for: .normal)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.isHidden = true
        btn.accessibilityLabel = "Остановить запись"

        return btn
    }()

    private let recognitionActivityIndicator = UIActivityIndicatorView(style: .medium)

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
        setupInteractions()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
        setupInteractions()
    }

    private func setupInteractions() {
        textField.delegate = self

        let longPressRecognizer = UILongPressGestureRecognizer(
            target: self,
            action: #selector(handleLongPress(_:))
        )
        longPressRecognizer.minimumPressDuration = 0.45
        longPressRecognizer.cancelsTouchesInView = true
        textRightButton.addGestureRecognizer(longPressRecognizer)

        textRightButton.addTarget(self, action: #selector(sendTextButtonTapped), for: .touchUpInside)
        speakRightButton.addTarget(self, action: #selector(stopVoiceRecordingButtonTapped), for: .touchUpInside)
        leftButton.addTarget(self, action: #selector(quickPhrasesButtonTapped), for: .touchUpInside)
    }

    private func setupView() {
        backgroundColor = .clear

        textField.attributedPlaceholder = NSAttributedString(
            string: "Сообщение...",
            attributes: [
                .foregroundColor: UIColor.black.withAlphaComponent(0.45)
            ]
        )
        textField.backgroundColor = .textField
        textField.tintColor = .black
        textField.layer.cornerRadius = 8
        textField.borderStyle = .none
        textField.layer.cornerRadius = 14
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.font = UIFont(name: "YSDisplay-Medium", size: 20)

        let paddingView = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: 0))
        textField.leftView = paddingView
        textField.leftViewMode = .always
        
        let stackView = UIStackView(
            arrangedSubviews: [leftButton, textField, textRightButton, speakRightButton]
        )
        stackView.axis = .horizontal
        stackView.spacing = 8
        stackView.alignment = .center
        stackView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),

            leftButton.widthAnchor.constraint(equalToConstant: 48),
            leftButton.heightAnchor.constraint(equalToConstant: 48),
            
            textField.heightAnchor.constraint(equalTo: heightAnchor, multiplier: 0.75),
            
            textRightButton.heightAnchor.constraint(equalTo: textField.heightAnchor),
            textRightButton.widthAnchor.constraint(equalTo: textRightButton.heightAnchor),

            speakRightButton.heightAnchor.constraint(equalTo: textField.heightAnchor),
            speakRightButton.widthAnchor.constraint(equalTo: speakRightButton.heightAnchor)
        ])

        speakRightButton.addSubview(recognitionActivityIndicator)
        recognitionActivityIndicator.translatesAutoresizingMaskIntoConstraints = false
        recognitionActivityIndicator.hidesWhenStopped = true
        NSLayoutConstraint.activate([
            recognitionActivityIndicator.centerXAnchor.constraint(equalTo: speakRightButton.centerXAnchor),
            recognitionActivityIndicator.centerYAnchor.constraint(equalTo: speakRightButton.centerYAnchor)
        ])
    }

    func applyVoiceInputState(_ state: ConversationVoiceInputState) {
        stopRecordingAnimation()
        recognitionActivityIndicator.stopAnimating()
        speakRightButton.alpha = 1
        speakRightButton.isEnabled = false
        speakRightButton.setImage(
            UIImage(named: "speakRightChatButton")?.withRenderingMode(.alwaysOriginal),
            for: .normal
        )

        switch state {
        case .idle:
            textRightButton.isHidden = false
            speakRightButton.isHidden = true
            textRightButton.isEnabled = true
        case .requestingPermission:
            textRightButton.isHidden = true
            speakRightButton.isHidden = false
            speakRightButton.accessibilityLabel = "Подготовка записи"
            speakRightButton.accessibilityValue = nil
        case .recording:
            textRightButton.isHidden = true
            speakRightButton.isHidden = false
            speakRightButton.isEnabled = true
            speakRightButton.accessibilityLabel = "Остановить запись"
            speakRightButton.accessibilityValue = "Идёт запись"
            startRecordingAnimation()
        case .recognizing:
            textRightButton.isHidden = true
            speakRightButton.isHidden = false
            speakRightButton.setImage(nil, for: .normal)
            speakRightButton.accessibilityLabel = "Распознавание речи"
            speakRightButton.accessibilityValue = "Обработка записи"
            recognitionActivityIndicator.startAnimating()
        }
    }

    private func startRecordingAnimation() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }

        let pulse = CABasicAnimation(keyPath: "transform.scale")
        pulse.fromValue = 1
        pulse.toValue = 1.15
        pulse.duration = 0.6
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        speakRightButton.layer.add(pulse, forKey: "recordingPulse")
    }

    private func stopRecordingAnimation() {
        speakRightButton.layer.removeAnimation(forKey: "recordingPulse")
    }

    private func submitTextFromField() {
        let text = textField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { return }

        delegate?.chatComponent(self, didSubmitText: text)
        textField.text = nil
        textField.resignFirstResponder()
    }
    
    @objc private func sendTextButtonTapped() {
        submitTextFromField()
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        delegate?.chatComponentDidRequestStartVoiceRecording(self)
    }

    @objc private func stopVoiceRecordingButtonTapped() {
        delegate?.chatComponentDidRequestStopVoiceRecording(self)
    }

    @objc private func quickPhrasesButtonTapped() {
        delegate?.chatComponentDidRequestQuickPhrases(self)
    }
}

extension ChatComponent: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        submitTextFromField()
        return true
    }
}
