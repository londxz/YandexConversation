//
//  LargeTextDisplayView.swift
//  HackatonYandex
//
//  Created by Rodion Kholodov.
//

import Foundation

@MainActor
protocol LargeTextDisplayView: AnyObject {
    func render(_ viewModel: LargeTextDisplayViewModel)
    func setDisplayRotated(_ isRotated: Bool)
    func dismissLargeTextDisplay()
}

struct LargeTextDisplayViewModel {
    let text: String
    let fontScale: Float
}
