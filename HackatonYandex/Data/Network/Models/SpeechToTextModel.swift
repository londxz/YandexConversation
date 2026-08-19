//
//  SpeechToTextModel.swift
//  HackatonYandex
//
//  Created by Rodion Kholodov.
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
