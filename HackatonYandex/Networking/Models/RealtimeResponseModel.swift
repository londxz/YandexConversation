//
//  RealtimeResponseModel.swift
//  HackatonYandex
//
//  Created by Родион Холодов on 02.06.2025.
//

struct RealtimeResponseModel: Codable {
    let status: String
    let dialogId: Int?
    let entriesCount: Int?
    let segmentsCount: Int?
    
    enum CodingKeys: String, CodingKey {
        case status
        case dialogId = "dialog_id"
        case entriesCount = "entries_count"
        case segmentsCount = "segments_count"
    }
}
