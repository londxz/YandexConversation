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
    private var settings = AppSettings.defaultValue

    init(speechSynthesizer: AVSpeechSynthesizer = AVSpeechSynthesizer()) {
        self.speechSynthesizer = speechSynthesizer
    }

    var isSpeaking: Bool {
        speechSynthesizer.isSpeaking
    }

    func speak(_ text: String) {
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: text)
        if let voiceIdentifier = settings.ttsVoiceIdentifier,
           let selectedVoice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
            utterance.voice = selectedVoice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: settings.ttsLanguage)
        }
        utterance.rate = min(
            max(settings.speechRate, AVSpeechUtteranceMinimumSpeechRate),
            AVSpeechUtteranceMaximumSpeechRate
        )
        speechSynthesizer.speak(utterance)
    }

    func stop() {
        speechSynthesizer.stopSpeaking(at: .immediate)
    }

    func availableVoices(language: String) -> [TextToSpeechVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == language }
            .map {
                TextToSpeechVoice(
                    identifier: $0.identifier,
                    name: $0.name,
                    language: $0.language
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func apply(settings: AppSettings) {
        self.settings = settings
    }
}
