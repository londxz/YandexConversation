//
//  DefaultAudioRecorderService.swift
//  HackatonYandex
//
//  Created by Rodion Kholodov.
//

import AVFoundation
import Foundation

final class DefaultAudioRecorderService: AudioRecordingService {
    private let audioSession: AVAudioSession
    private let fileManager: FileManager
    private var audioRecorder: AVAudioRecorder?
    private var audioFilename: URL?

    init(
        audioSession: AVAudioSession = .sharedInstance(),
        fileManager: FileManager = .default
    ) {
        self.audioSession = audioSession
        self.fileManager = fileManager
    }

    func startRecording() throws {
        try audioSession.setCategory(.playAndRecord, mode: .default)
        try audioSession.setActive(true)

        let filename = "recording_\(UUID().uuidString.prefix(8)).wav"
        let fileURL = fileManager.temporaryDirectory.appendingPathComponent(filename)
        audioFilename = fileURL

        let settings = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false
        ] as [String: Any]

        audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
        audioRecorder?.record()
    }

    func stopRecording() -> URL? {
        audioRecorder?.stop()
        audioRecorder = nil
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        return audioFilename
    }

    func discardRecording(at fileURL: URL) {
        try? fileManager.removeItem(at: fileURL)

        if audioFilename == fileURL {
            audioFilename = nil
        }
    }
}
