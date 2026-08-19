//
//  SettingsPresenter.swift
//  HackatonYandex
//
//  Created by Rodion Kholodov.
//

import Foundation

@MainActor
final class SettingsPresenter {
    private struct LanguageOption {
        let code: String
        let title: String
    }

    private static let languageOptions = [
        LanguageOption(code: "ru-RU", title: "Русский"),
        LanguageOption(code: "en-US", title: "English"),
        LanguageOption(code: "de-DE", title: "Deutsch"),
        LanguageOption(code: "fr-FR", title: "Français"),
        LanguageOption(code: "es-ES", title: "Español")
    ]

    private static let systemVoiceID = "system-default"

    private weak var view: SettingsView?
    private let fetchSettingsUseCase: FetchSettingsUseCase
    private let saveSettingsUseCase: SaveSettingsUseCase
    private let deleteAllUserDataUseCase: DeleteAllUserDataUseCase
    private let textToSpeechService: TextToSpeechService

    private var settings = AppSettings.defaultValue
    private var pendingSettingsToSave: AppSettings?
    private var saveTask: Task<Void, Never>?

    init(
        view: SettingsView,
        fetchSettingsUseCase: FetchSettingsUseCase,
        saveSettingsUseCase: SaveSettingsUseCase,
        deleteAllUserDataUseCase: DeleteAllUserDataUseCase,
        textToSpeechService: TextToSpeechService
    ) {
        self.view = view
        self.fetchSettingsUseCase = fetchSettingsUseCase
        self.saveSettingsUseCase = saveSettingsUseCase
        self.deleteAllUserDataUseCase = deleteAllUserDataUseCase
        self.textToSpeechService = textToSpeechService
    }

    func viewDidLoad() {
        view?.render(SettingsViewModel(title: "Настройки", state: .loading))

        Task { [weak self] in
            await self?.loadSettings()
        }
    }

    func didSelectRow(_ rowID: SettingsViewModel.RowID) {
        switch rowID {
        case .recognitionLanguage:
            presentLanguageSelection(
                rowID: rowID,
                title: "Язык распознавания",
                selectedCode: settings.recognitionLanguage
            )
        case .ttsLanguage:
            presentLanguageSelection(
                rowID: rowID,
                title: "Язык озвучивания",
                selectedCode: settings.ttsLanguage
            )
        case .ttsVoice:
            presentVoiceSelection()
        case .privacyInformation:
            view?.presentSettingsAlert(
                title: "Обработка данных",
                message: "Разговоры, фразы и настройки хранятся на устройстве. Аудиозапись удаляется сразу после распознавания. Синхронизация пока не подключена."
            )
        case .deleteLocalData:
            view?.presentDeleteDataConfirmation()
        case .speechRate,
             .transcriptFontScale,
             .autoStartMicrophone,
             .saveConversations,
             .sync,
             .localOnly:
            break
        }
    }

    func didSelectOption(
        rowID: SettingsViewModel.RowID,
        optionID: String
    ) {
        switch rowID {
        case .recognitionLanguage:
            settings.recognitionLanguage = optionID
        case .ttsLanguage:
            settings.ttsLanguage = optionID
            settings.ttsVoiceIdentifier = nil
        case .ttsVoice:
            settings.ttsVoiceIdentifier = optionID == Self.systemVoiceID ? nil : optionID
        default:
            return
        }

        renderContent()
        textToSpeechService.apply(settings: settings)
        scheduleSave()
    }

    func didChangeToggle(
        rowID: SettingsViewModel.RowID,
        isOn: Bool
    ) {
        switch rowID {
        case .autoStartMicrophone:
            settings.autoStartMicrophone = isOn
        case .saveConversations:
            settings.saveConversationsByDefault = isOn
        case .localOnly:
            settings.privacyMode = isOn ? .localOnly : .standard
            if isOn {
                settings.syncEnabled = false
            }
        case .sync:
            guard settings.privacyMode == .standard else { return }
            settings.syncEnabled = isOn
        default:
            return
        }

        renderContent()
        textToSpeechService.apply(settings: settings)
        scheduleSave()
    }

    func didFinishChangingSlider(
        rowID: SettingsViewModel.RowID,
        value: Float
    ) {
        switch rowID {
        case .speechRate:
            settings.speechRate = rounded(value, step: 0.05, range: 0.35...0.65)
        case .transcriptFontScale:
            settings.transcriptFontScale = rounded(value, step: 0.05, range: 0.85...1.60)
        default:
            return
        }

        renderContent()
        textToSpeechService.apply(settings: settings)
        scheduleSave()
    }

    func didConfirmDeleteAllData() {
        view?.render(SettingsViewModel(title: "Настройки", state: .loading))
        let activeSaveTask = saveTask
        pendingSettingsToSave = nil

        Task { [weak self] in
            guard let self else { return }

            do {
                await activeSaveTask?.value
                try await self.deleteAllUserDataUseCase.execute()
                self.settings = .defaultValue
                self.pendingSettingsToSave = nil
                self.textToSpeechService.apply(settings: self.settings)
                self.renderContent()
                self.view?.presentSettingsAlert(
                    title: "Данные удалены",
                    message: "История, сохранённые фразы и настройки удалены с устройства."
                )
            } catch {
                AppLogger.error("Failed to delete local data: \(error.localizedDescription)")
                self.renderContent()
                self.view?.presentSettingsAlert(
                    title: "Не удалось удалить данные",
                    message: "Попробуйте ещё раз."
                )
            }
        }
    }

    private func loadSettings() async {
        do {
            settings = try await fetchSettingsUseCase.execute()
            textToSpeechService.apply(settings: settings)
            renderContent()
        } catch {
            AppLogger.error("Failed to load settings: \(error.localizedDescription)")
            settings = .defaultValue
            textToSpeechService.apply(settings: settings)
            renderContent()
            view?.presentSettingsAlert(
                title: "Не удалось загрузить настройки",
                message: "Показаны значения по умолчанию."
            )
        }
    }

    private func renderContent() {
        let sections = [
            SettingsViewModel.Section(
                title: "Речь",
                footer: nil,
                rows: [
                    valueRow(
                        id: .recognitionLanguage,
                        title: "Язык распознавания",
                        value: languageTitle(for: settings.recognitionLanguage)
                    ),
                    valueRow(
                        id: .ttsLanguage,
                        title: "Язык озвучивания",
                        value: languageTitle(for: settings.ttsLanguage)
                    ),
                    valueRow(
                        id: .ttsVoice,
                        title: "Голос",
                        value: selectedVoiceTitle()
                    ),
                    sliderRow(
                        id: .speechRate,
                        title: "Скорость речи",
                        value: settings.speechRate,
                        range: 0.35...0.65,
                        step: 0.05,
                        valueText: String(format: "%.2f×", settings.speechRate),
                        valueFormat: .speechRate
                    )
                ]
            ),
            SettingsViewModel.Section(
                title: "Отображение",
                footer: "Размер применяется к расшифровке и крупному показу текста.",
                rows: [
                    sliderRow(
                        id: .transcriptFontScale,
                        title: "Размер текста",
                        value: settings.transcriptFontScale,
                        range: 0.85...1.60,
                        step: 0.05,
                        valueText: "\(Int((settings.transcriptFontScale * 100).rounded()))%",
                        valueFormat: .percentage
                    )
                ]
            ),
            SettingsViewModel.Section(
                title: "Разговор",
                footer: nil,
                rows: [
                    toggleRow(
                        id: .autoStartMicrophone,
                        title: "Автостарт микрофона",
                        subtitle: "Недоступно",
                        isOn: settings.autoStartMicrophone,
                        isEnabled: false
                    ),
                    toggleRow(
                        id: .saveConversations,
                        title: "Сохранять разговоры",
                        subtitle: "Добавлять новые разговоры в историю",
                        isOn: settings.saveConversationsByDefault
                    )
                ]
            ),
            SettingsViewModel.Section(
                title: "Конфиденциальность",
                footer: settings.privacyMode == .localOnly
                    ? "В локальном режиме данные не отправляются для синхронизации."
                    : nil,
                rows: [
                    toggleRow(
                        id: .localOnly,
                        title: "Только на устройстве",
                        subtitle: "Запретить синхронизацию данных",
                        isOn: settings.privacyMode == .localOnly
                    ),
                    SettingsViewModel.Row(
                        id: .sync,
                        title: "Синхронизация",
                        subtitle: "Будет доступна после подключения сервера",
                        accessory: .toggle(isOn: false),
                        isEnabled: false,
                        isDestructive: false
                    ),
                    valueRow(
                        id: .privacyInformation,
                        title: "Об обработке данных",
                        value: nil
                    )
                ]
            ),
            SettingsViewModel.Section(
                title: nil,
                footer: "Удаление нельзя отменить.",
                rows: [
                    SettingsViewModel.Row(
                        id: .deleteLocalData,
                        title: "Удалить данные с устройства",
                        subtitle: nil,
                        accessory: .none,
                        isEnabled: true,
                        isDestructive: true
                    )
                ]
            )
        ]

        view?.render(SettingsViewModel(title: "Настройки", state: .content(sections)))
    }

    private func presentLanguageSelection(
        rowID: SettingsViewModel.RowID,
        title: String,
        selectedCode: String
    ) {
        let options = Self.languageOptions.map {
            SettingsSelectionViewModel.Option(
                id: $0.code,
                title: $0.title,
                subtitle: $0.code
            )
        }

        view?.presentSelection(
            SettingsSelectionViewModel(
                rowID: rowID,
                title: title,
                selectedOptionID: selectedCode,
                options: options
            )
        )
    }

    private func presentVoiceSelection() {
        let systemOption = SettingsSelectionViewModel.Option(
            id: Self.systemVoiceID,
            title: "Системный голос",
            subtitle: nil
        )
        let voiceOptions = textToSpeechService
            .availableVoices(language: settings.ttsLanguage)
            .map {
                SettingsSelectionViewModel.Option(
                    id: $0.identifier,
                    title: $0.name,
                    subtitle: $0.language
                )
            }

        view?.presentSelection(
            SettingsSelectionViewModel(
                rowID: .ttsVoice,
                title: "Голос",
                selectedOptionID: settings.ttsVoiceIdentifier ?? Self.systemVoiceID,
                options: [systemOption] + voiceOptions
            )
        )
    }

    private func scheduleSave() {
        pendingSettingsToSave = settings
        guard saveTask == nil else { return }

        saveTask = Task { [weak self] in
            await self?.drainPendingSaves()
        }
    }

    private func drainPendingSaves() async {
        while let settingsToSave = pendingSettingsToSave {
            pendingSettingsToSave = nil

            do {
                try await saveSettingsUseCase.execute(settingsToSave)
            } catch {
                AppLogger.error("Failed to save settings: \(error.localizedDescription)")
                pendingSettingsToSave = nil
                view?.presentSettingsAlert(
                    title: "Не удалось сохранить настройки",
                    message: "Попробуйте изменить параметр ещё раз."
                )
                break
            }
        }

        saveTask = nil
    }

    private func languageTitle(for code: String) -> String {
        Self.languageOptions.first { $0.code == code }?.title ?? code
    }

    private func selectedVoiceTitle() -> String {
        guard let identifier = settings.ttsVoiceIdentifier else {
            return "Системный голос"
        }

        return textToSpeechService
            .availableVoices(language: settings.ttsLanguage)
            .first { $0.identifier == identifier }?
            .name ?? "Системный голос"
    }

    private func valueRow(
        id: SettingsViewModel.RowID,
        title: String,
        value: String?
    ) -> SettingsViewModel.Row {
        SettingsViewModel.Row(
            id: id,
            title: title,
            subtitle: nil,
            accessory: .disclosure(value: value),
            isEnabled: true,
            isDestructive: false
        )
    }

    private func toggleRow(
        id: SettingsViewModel.RowID,
        title: String,
        subtitle: String?,
        isOn: Bool,
        isEnabled: Bool = true
    ) -> SettingsViewModel.Row {
        SettingsViewModel.Row(
            id: id,
            title: title,
            subtitle: subtitle,
            accessory: .toggle(isOn: isOn),
            isEnabled: isEnabled,
            isDestructive: false
        )
    }

    private func sliderRow(
        id: SettingsViewModel.RowID,
        title: String,
        value: Float,
        range: ClosedRange<Float>,
        step: Float,
        valueText: String,
        valueFormat: SettingsViewModel.Slider.ValueFormat
    ) -> SettingsViewModel.Row {
        SettingsViewModel.Row(
            id: id,
            title: title,
            subtitle: nil,
            accessory: .slider(
                SettingsViewModel.Slider(
                    value: value,
                    minimumValue: range.lowerBound,
                    maximumValue: range.upperBound,
                    step: step,
                    valueText: valueText,
                    valueFormat: valueFormat
                )
            ),
            isEnabled: true,
            isDestructive: false
        )
    }

    private func rounded(
        _ value: Float,
        step: Float,
        range: ClosedRange<Float>
    ) -> Float {
        min(max((value / step).rounded() * step, range.lowerBound), range.upperBound)
    }
}
