//
//  ChatVCExtension.swift
//  HackatonYandex
//
//  Created by Родион Холодов on 01.06.2025.
//

import UIKit

extension ChatVC: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let touchedView = touch.view else { return true }
        return !touchedView.isDescendant(of: chatComponent)
            && !touchedView.isDescendant(of: quickPhrasePanel)
    }
}

extension ChatVC: SegmentControlComponentDelegate, TalkViewControllerDelegate, MicroEnabledViewDelegate {

    func segmentChanged(to index: Int) {
        presenter.didChangeSegment(index: index)
    }

    func showStartTypingHint() {
        presenter.didRequestStartTypingHint()
    }

    func showMicrophoneHint() {
        presenter.didRequestMicrophoneHint()
    }

    func didRequestRotationToggle() {
        presenter.didRequestRotationToggle()
    }

    func didRequestResetRotation() {
        presenter.didRequestResetRotation()
    }
}

extension ChatVC: ConversationView {
    func render(_ viewModel: ConversationViewModel) {
        currentConversationMode = viewModel.mode
        segmentControlComponent.setSelectedIndex(viewModel.mode.segmentIndex)

        if !viewModel.isInputVisible {
            hideQuickPhrasePanel(animated: false)
        }

        switch viewModel.mode {
        case .talk:
            switchToChild(talkVC)
        case .listen:
            switchToChild(listenVC)
        }

        UIView.animate(withDuration: 0.2) {
            self.chatComponent.alpha = viewModel.isInputVisible ? 1 : 0
            self.chatComponentHeightConstraint.constant = viewModel.isInputVisible ? 56 : 0
            self.view.layoutIfNeeded()
        }
        chatComponent.isUserInteractionEnabled = viewModel.isInputVisible
    }

    func displayStartTypingHint() {
        typingHint?.hide()

        let hint = StartTypingHint()
        hint.show(over: view, above: chatComponent)
        typingHint = hint
    }

    func displayMicrophoneHint() {
        microphoneHint?.hide()

        let hint = MicrophoneOnHint()
        hint.onTap = { [weak self] in
            self?.presenter.didTapMicrophoneHint()
        }

        microphoneHint = hint
        hint.show(over: self.view, under: segmentControlComponent)
    }

    func hideConversationHints() {
        typingHint?.hide()
        typingHint = nil

        microphoneHint?.hide()
        microphoneHint = nil
    }

    func presentMicrophoneOverlay() {
        microEnabledView?.removeFromSuperview()
        
        let overlay = MicroEnabledView()
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.alpha = 0
        overlay.transform = CGAffineTransform(scaleX: 1.1, y: 1.1) // чуть увеличен сначала

        view.addSubview(overlay)
        microEnabledView = overlay
        microEnabledView?.delegate = self
        
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: view.topAnchor),
            overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlay.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])

        UIView.animate(withDuration: 0.4,
                       delay: 0,
                       usingSpringWithDamping: 0.8,
                       initialSpringVelocity: 0.5,
                       options: [.curveEaseInOut],
                       animations: {
            overlay.alpha = 1
            overlay.transform = .identity
        }, completion: nil)
    }

    func toggleConversationDisplayRotation() {
        toggleRotation()
    }

    func resetConversationDisplay() {
        resetRotationIfNeeded()
    }

    func clearConversationMessages() {
        dismissMicrophoneOverlayIfNeeded()
        hideQuickPhrasePanel(animated: false)
        chatComponent.textField.text = nil
        chatComponent.resetVoiceInputState()
        talkVC.clearMessages()
        listenVC.clearTranscript()
    }
}

extension ChatVC: ChatComponentDelegate {
    func chatComponentDidRequestQuickPhrases(_ component: ChatComponent) {
        toggleQuickPhrasePanel()
    }

    func chatComponentDidRequestStartVoiceRecording(_ component: ChatComponent) {
        if !presenter.didRequestStartVoiceRecording() {
            component.resetVoiceInputState()
        }
    }

    func chatComponentDidRequestStopVoiceRecording(_ component: ChatComponent) {
        presenter.didRequestStopVoiceRecording()
    }

    func chatComponent(_ component: ChatComponent, didSubmitText text: String) {
        presenter.didSubmitText(text)
    }

    func displayRecognizedSpeech(_ text: String) {
        switch currentConversationMode {
        case .talk:
            talkVC.appendIncomingMessage(text)
        case .listen:
            listenVC.appendSpeech(text)
        }
    }

    func displayConversationError(_ message: String) {
        chatComponent.resetVoiceInputState()

        let alert = UIAlertController(
            title: "Что-то пошло не так",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Понятно", style: .default))
        present(alert, animated: true)
    }

    func displaySubmittedText(_ text: String) {
        talkVC.appendUserMessage(text)
    }
}
