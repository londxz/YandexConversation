//
//  DefaultMicrophonePermissionService.swift
//  HackatonYandex
//
//  Created by Rodion Kholodov.
//

import AVFoundation
import Foundation

final class DefaultMicrophonePermissionService: MicrophonePermissionService {
    private let audioSession: AVAudioSession

    init(audioSession: AVAudioSession = .sharedInstance()) {
        self.audioSession = audioSession
    }

    func requestPermission(completion: @escaping (Bool) -> Void) {
        switch audioSession.recordPermission {
        case .granted:
            completion(true)
        case .denied:
            completion(false)
        case .undetermined:
            audioSession.requestRecordPermission { isGranted in
                completion(isGranted)
            }
        @unknown default:
            completion(false)
        }
    }
}
