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

    var authorizationStatus: MicrophonePermissionStatus {
        switch audioSession.recordPermission {
        case .granted:
            return .granted
        case .denied:
            return .denied
        case .undetermined:
            return .undetermined
        @unknown default:
            return .denied
        }
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
