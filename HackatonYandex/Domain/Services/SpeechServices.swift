//
//  SpeechServices.swift
//  HackatonYandex
//
//  Created by Rodion Kholodov.
//

import Foundation

protocol AudioRecordingService: AnyObject {
    func startRecording() throws
    func stopRecording() -> URL?
    func discardRecording(at fileURL: URL)
}

protocol MicrophonePermissionService: AnyObject {
    func requestPermission(completion: @escaping (Bool) -> Void)
}

protocol SpeechRecognitionService: AnyObject {
    func transcribeAudio(
        fileURL: URL,
        language: String,
        completion: @escaping (Result<SpeechToTextModel, Error>) -> Void
    )
}

struct TextToSpeechVoice: Equatable {
    let identifier: String
    let name: String
    let language: String
}

protocol TextToSpeechService: AnyObject {
    var isSpeaking: Bool { get }

    func speak(_ text: String)
    func stop()
    func availableVoices(language: String) -> [TextToSpeechVoice]
    func apply(settings: AppSettings)
}
