//
//  LargeTextDisplayPresenter.swift
//  HackatonYandex
//
//  Created by Rodion Kholodov.
//

import Foundation

@MainActor
final class LargeTextDisplayPresenter {
    private weak var view: LargeTextDisplayView?
    private let text: String
    private let fetchSettingsUseCase: FetchSettingsUseCase
    private let textToSpeechService: TextToSpeechService
    private var isRotated = false

    init(
        view: LargeTextDisplayView,
        text: String,
        fetchSettingsUseCase: FetchSettingsUseCase,
        textToSpeechService: TextToSpeechService
    ) {
        self.view = view
        self.text = text
        self.fetchSettingsUseCase = fetchSettingsUseCase
        self.textToSpeechService = textToSpeechService
    }

    func viewDidLoad() {
        render(fontScale: AppSettings.defaultValue.transcriptFontScale)

        Task { [weak self] in
            guard let self else { return }

            do {
                let settings = try await self.fetchSettingsUseCase.execute()
                self.textToSpeechService.apply(settings: settings)
                self.render(fontScale: settings.transcriptFontScale)
            } catch {
                AppLogger.error("Failed to load large text settings: \(error.localizedDescription)")
            }
        }
    }

    func didTapPlay() {
        textToSpeechService.speak(text)
    }

    func didTapRotate() {
        isRotated.toggle()
        view?.setDisplayRotated(isRotated)
    }

    func didTapClose() {
        didDismiss()
        view?.dismissLargeTextDisplay()
    }

    func didDismiss() {
        textToSpeechService.stop()
    }

    private func render(fontScale: Float) {
        view?.render(
            LargeTextDisplayViewModel(
                text: text,
                fontScale: min(max(fontScale, 0.85), 1.60)
            )
        )
    }
}
