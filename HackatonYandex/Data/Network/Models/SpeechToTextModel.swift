//
//  SpeechToTextModel.swift
//  HackatonYandex
//
//  Created by Родион Холодов on 02.06.2025.
//

struct SpeechToTextModel: Decodable {
    let text: String
    let language: String?
    let durationMs: Int?
    let confidence: Double?

    enum CodingKeys: String, CodingKey {
        case text
        case language
        case durationMs = "duration_ms"
        case confidence
    }
}
