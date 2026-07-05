//
//  AppError.swift
//  HackatonYandex
//
//  Created by Rodion Kholodov.
//

import Foundation

enum AppError: Error, Equatable {
    case invalidURL
    case emptyResponse
    case decodingFailed
    case networkUnavailable
    case serverError(statusCode: Int)
    case apiError(code: String, message: String, requestID: String?)
    case speechUnavailable
    case permissionDenied
    case unknown
}
