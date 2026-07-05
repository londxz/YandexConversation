//
//  DefaultTextToSpeechService.swift
//  HackatonYandex
//
//  Created by Rodion Kholodov.
//

import AVFoundation
import Foundation

final class DefaultTextToSpeechService: TextToSpeechService {
    private let speechSynthesizer: AVSpeechSynthesizer

    init(speechSynthesizer: AVSpeechSynthesizer = AVSpeechSynthesizer()) {
        self.speechSynthesizer = speechSynthesizer
    }

    var isSpeaking: Bool {
        speechSynthesizer.isSpeaking
    }

    func speak(_ text: String, language: String) {
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        speechSynthesizer.speak(utterance)
    }

    func stop() {
        speechSynthesizer.stopSpeaking(at: .immediate)
    }
}
