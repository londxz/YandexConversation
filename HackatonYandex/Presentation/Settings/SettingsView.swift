//
//  SettingsView.swift
//  HackatonYandex
//
//  Created by Rodion Kholodov.
//

import Foundation

protocol SettingsView: AnyObject {
    func render(_ viewModel: SettingsViewModel)
    func presentSelection(_ viewModel: SettingsSelectionViewModel)
    func presentDeleteDataConfirmation()
    func presentSettingsAlert(title: String, message: String)
}

struct SettingsViewModel {
    enum State {
        case loading
        case content([Section])
    }

    struct Section {
        let title: String?
        let footer: String?
        let rows: [Row]
    }

    struct Row {
        let id: RowID
        let title: String
        let subtitle: String?
        let accessory: Accessory
        let isEnabled: Bool
        let isDestructive: Bool
    }

    struct Slider {
        enum ValueFormat {
            case speechRate
            case percentage
        }

        let value: Float
        let minimumValue: Float
        let maximumValue: Float
        let step: Float
        let valueText: String
        let valueFormat: ValueFormat
    }

    enum Accessory {
        case disclosure(value: String?)
        case toggle(isOn: Bool)
        case slider(Slider)
        case none
    }

    enum RowID: Hashable {
        case recognitionLanguage
        case ttsLanguage
        case ttsVoice
        case speechRate
        case transcriptFontScale
        case autoStartMicrophone
        case saveConversations
        case sync
        case localOnly
        case privacyInformation
        case deleteLocalData
    }

    let title: String
    let state: State
}

struct SettingsSelectionViewModel {
    struct Option {
        let id: String
        let title: String
        let subtitle: String?
    }

    let rowID: SettingsViewModel.RowID
    let title: String
    let selectedOptionID: String?
    let options: [Option]
}
