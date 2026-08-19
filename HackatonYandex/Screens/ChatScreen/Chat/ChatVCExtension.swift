//
//  ChatVCExtension.swift
//  HackatonYandex
//
//  Created by Rodion Kholodov.
//

import UIKit

extension ChatVC: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let touchedView = touch.view else { return true }
        return !touchedView.isDescendant(of: chatComponent)
            && !touchedView.isDescendant(of: quickPhrasePanel)
    }
}

extension ChatVC: SegmentControlComponentDelegate, TalkViewControllerDelegate {

    func segmentChanged(to index: Int) {
        presenter.didChangeSegment(index: index)
    }

    func talkViewControllerDidAppearEmpty(_ viewController: TalkViewController) {
        presenter.didShowEmptyTalkScreen()
    }

    func talkViewController(_ viewController: TalkViewController, didRequestLargeText text: String) {
        presenter.didRequestLargeText(text)
    }

    func talkViewController(_ viewController: TalkViewController, didRequestSpeak text: String) {
        presenter.didRequestSpeak(text)
    }
}

extension ChatVC: ConversationView {
    func render(_ viewModel: ConversationViewModel) {
        currentConversationMode = viewModel.mode
        segmentControlComponent.setSelectedIndex(viewModel.mode.segmentIndex)
        talkVC.applyTranscriptFontScale(viewModel.transcriptFontScale)
        listenVC.applyTranscriptFontScale(viewModel.transcriptFontScale)

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

    func displayLargeText(_ text: String) {
        dismissLargeTextDisplayIfNeeded()

        let displayViewController = LargeTextDisplayViewController(text: text, container: container)
        displayViewController.onDismiss = { [weak self, weak displayViewController] in
            guard self?.largeTextDisplayViewController === displayViewController else { return }
            self?.largeTextDisplayViewController = nil
        }
        largeTextDisplayViewController = displayViewController
        displayViewController.attach(to: self)
    }

    func dismissLargeTextDisplay() {
        dismissLargeTextDisplayIfNeeded()
    }

    func clearConversationMessages() {
        dismissLargeTextDisplayIfNeeded()
        hideQuickPhrasePanel(animated: false)
        chatComponent.textField.text = nil
        chatComponent.resetVoiceInputState()
        talkVC.clearMessages()
        listenVC.clearTranscript()
    }

    func displayConversationMessages(_ messages: [ConversationMessage]) {
        for message in messages {
            switch currentConversationMode {
            case .talk:
                switch message.source {
                case .userTyped, .userVoice, .quickPhrase:
                    talkVC.appendUserMessage(message.text, createdAt: message.createdAt)
                case .externalSpeech, .system:
                    talkVC.appendIncomingMessage(
                        message.text,
                        speakerLabel: message.speakerLabel ?? "Говорящий"
                    )
                }
            case .listen:
                listenVC.appendSpeech(
                    message.text,
                    speakerLabel: message.speakerLabel ?? "Говорящий"
                )
            }
        }
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
