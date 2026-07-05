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
        completion: @escaping (Result<SpeechToTextModel, Error>) -> Void
    )
}

protocol TextToSpeechService: AnyObject {
    var isSpeaking: Bool { get }

    func speak(_ text: String, language: String)
    func stop()
}
