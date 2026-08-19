//
//  LargeTextDisplayPresenterTests.swift
//  HackatonYandexTests
//
//  Created by Rodion Kholodov.
//

import XCTest
@testable import HackatonYandex

@MainActor
final class LargeTextDisplayPresenterTests: XCTestCase {
    func testActionsControlSpeechRotationAndDismissal() {
        let view = LargeTextDisplayViewSpy()
        let speech = TextToSpeechServiceSpy()
        let presenter = LargeTextDisplayPresenter(
            view: view,
            text: "Пожалуйста, напишите ответ",
            fetchSettingsUseCase: FetchSettingsUseCase(repository: SettingsRepositoryStub()),
            textToSpeechService: speech
        )

        presenter.viewDidLoad()
        presenter.didTapPlay()
        presenter.didTapRotate()
        presenter.didTapRotate()
        presenter.didTapClose()

        XCTAssertEqual(view.models.first?.text, "Пожалуйста, напишите ответ")
        XCTAssertEqual(speech.spokenTexts, ["Пожалуйста, напишите ответ"])
        XCTAssertEqual(view.rotations, [true, false])
        XCTAssertEqual(speech.stopCallCount, 1)
        XCTAssertEqual(view.dismissCallCount, 1)
    }
}
