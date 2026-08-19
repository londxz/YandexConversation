//
//  ConversationPresenterTests.swift
//  HackatonYandexTests
//
//  Created by Rodion Kholodov.
//

import XCTest
@testable import HackatonYandex

@MainActor
final class ConversationPresenterTests: XCTestCase {
    func testSubmittingTextRendersMessageWithoutOpeningLargeDisplay() {
        let context = makeContext()

        context.presenter.didSubmitText("  Нужна помощь  ")

        XCTAssertEqual(context.view.submittedTexts, ["Нужна помощь"])
        XCTAssertTrue(context.view.largeTexts.isEmpty)
    }

    func testSpeakRequestUsesTextToSpeechService() {
        let context = makeContext()

        context.presenter.didRequestSpeak("  Повторите, пожалуйста  ")

        XCTAssertEqual(context.textToSpeechService.spokenTexts, ["Повторите, пожалуйста"])
    }

    func testResumeConversationRestoresModeAndMessages() async {
        let repository = ConversationRepositoryStub()
        let conversation = Conversation(
            id: "conversation-id",
            title: "Прием у врача",
            mode: .listen,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20),
            isPinned: false,
            syncState: .localOnly
        )
        let message = ConversationMessage(
            id: "message-id",
            conversationId: conversation.id,
            text: "Что вас беспокоит?",
            source: .externalSpeech,
            speakerId: nil,
            speakerLabel: "Говорящий 1",
            isFinal: true,
            createdAt: Date(timeIntervalSince1970: 15),
            audioDurationMs: nil,
            syncState: .localOnly
        )
        repository.conversations = [conversation]
        repository.messages = [message]

        let context = makeContext(repository: repository)
        let restored = expectation(description: "Conversation restored")
        context.view.onDisplayMessages = { restored.fulfill() }

        context.presenter.didRequestResumeConversation(id: conversation.id)
        await fulfillment(of: [restored], timeout: 1)

        XCTAssertEqual(context.view.renderedModels.last?.mode, .listen)
        XCTAssertEqual(context.view.displayedMessages, [message])
        XCTAssertEqual(context.view.clearCallCount, 1)
    }

    private func makeContext(
        repository: ConversationRepositoryStub = ConversationRepositoryStub()
    ) -> (
        presenter: ConversationPresenter,
        view: ConversationViewSpy,
        textToSpeechService: TextToSpeechServiceSpy
    ) {
        let view = ConversationViewSpy()
        let settingsRepository = SettingsRepositoryStub()
        let textToSpeechService = TextToSpeechServiceSpy()
        let presenter = ConversationPresenter(
            view: view,
            microphonePermissionService: MicrophonePermissionServiceStub(),
            audioRecordingService: AudioRecordingServiceStub(),
            speechRecognitionService: SpeechRecognitionServiceStub(),
            textToSpeechService: textToSpeechService,
            fetchSettingsUseCase: FetchSettingsUseCase(repository: settingsRepository),
            fetchConversationUseCase: FetchConversationUseCase(repository: repository),
            fetchConversationMessagesUseCase: FetchConversationMessagesUseCase(repository: repository),
            saveConversationUseCase: SaveConversationUseCase(repository: repository),
            addConversationMessageUseCase: AddConversationMessageUseCase(repository: repository)
        )
        return (presenter, view, textToSpeechService)
    }
}
