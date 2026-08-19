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

enum MicrophonePermissionStatus {
    case undetermined
    case granted
    case denied
}

protocol MicrophonePermissionService: AnyObject {
    var authorizationStatus: MicrophonePermissionStatus { get }
    func requestPermission(completion: @escaping (Bool) -> Void)
}

enum SpeechRecognitionProcessingMode: Equatable {
    case onDeviceOnly
    case allowSystemNetworkFallback
}

protocol SpeechRecognitionService: AnyObject {
    func transcribeAudio(
        fileURL: URL,
        language: String,
        conversationId: String,
        processingMode: SpeechRecognitionProcessingMode,
        completion: @escaping (Result<SpeechToTextModel, Error>) -> Void
    )
    func cancelTranscription()
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
