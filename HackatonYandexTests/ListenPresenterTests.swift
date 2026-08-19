//
//  ListenPresenterTests.swift
//  HackatonYandexTests
//
//  Created by Rodion Kholodov.
//

import XCTest
@testable import HackatonYandex

@MainActor
final class ListenPresenterTests: XCTestCase {
    func testAutoStartBeginsAudioCaptureAndRealtimeSession() async {
        let context = makeContext()
        let started = expectation(description: "Listening started")
        context.view.onRender = { model in
            if model.state == .connecting {
                started.fulfill()
            }
        }

        context.presenter.activate(
            configuration: context.configuration,
            autoStart: true
        )

        await fulfillment(of: [started], timeout: 1)
        XCTAssertEqual(context.audioCapture.startCallCount, 1)
        XCTAssertEqual(context.speechClient.configurations, [context.configuration])
        XCTAssertEqual(context.delegate.microphoneActivity.last, true)
    }

    func testPartialIsRenderedButOnlyFinalIsForwardedForPersistence() async {
        let context = makeContext()
        let started = expectation(description: "Listening started")
        context.view.onRender = { model in
            if model.state == .connecting {
                started.fulfill()
            }
        }
        context.presenter.activate(configuration: context.configuration, autoStart: true)
        await fulfillment(of: [started], timeout: 1)

        let partial = makeSegment(id: nil, sequence: 1, text: "Добрый")
        let final = makeSegment(id: UUID().uuidString, sequence: 2, text: "Добрый день")
        let finalized = expectation(description: "Final segment rendered")
        context.view.onRender = nil
        context.speechClient.emit(.partial(partial))
        context.speechClient.emit(.final(final))
        DispatchQueue.main.async {
            finalized.fulfill()
        }

        await fulfillment(of: [finalized], timeout: 1)
        XCTAssertEqual(context.view.partialSegments, [partial])
        XCTAssertEqual(context.view.finalSegments, [final])
        XCTAssertEqual(
            context.delegate.finalizedSegments,
            [.init(segment: final, conversationId: context.configuration.conversationId)]
        )
    }

    func testPauseStopsCaptureAndWaitsForStoppedEvent() async {
        let context = makeContext()
        let started = expectation(description: "Listening started")
        context.view.onRender = { model in
            if model.state == .connecting {
                started.fulfill()
            }
        }
        context.presenter.activate(configuration: context.configuration, autoStart: true)
        await fulfillment(of: [started], timeout: 1)

        context.speechClient.emit(.connected)
        let connected = expectation(description: "Connected event applied")
        DispatchQueue.main.async { connected.fulfill() }
        await fulfillment(of: [connected], timeout: 1)
        context.presenter.didTapPauseResume()

        XCTAssertEqual(context.audioCapture.stopCallCount, 2)
        XCTAssertEqual(context.speechClient.stopCallCount, 1)
        XCTAssertEqual(context.view.models.last?.state, .pausing)

        context.speechClient.emit(.stopped)
        let stopped = expectation(description: "Stopped event applied")
        DispatchQueue.main.async { stopped.fulfill() }
        await fulfillment(of: [stopped], timeout: 1)
        XCTAssertEqual(context.view.models.last?.state, .paused)
    }

    func testBackendFirstRealtimeUsesLocalClientForStrictPrivacy() async {
        let remote = RealtimeSpeechClientSpy()
        let local = RealtimeSpeechClientSpy()
        let client = BackendFirstRealtimeSpeechClient(
            remoteClient: remote,
            localClient: local
        )
        let configuration = RealtimeSpeechConfiguration(
            conversationId: UUID().uuidString,
            language: "ru-RU",
            processingMode: .onDeviceOnly
        )
        let localStarted = expectation(description: "Local client started")
        let localReceivedAudio = expectation(description: "Local client received audio")
        local.onStart = { localStarted.fulfill() }
        local.onAudioChunk = { localReceivedAudio.fulfill() }

        client.start(configuration: configuration)
        client.appendAudioChunk(Data([1, 2]))

        await fulfillment(of: [localStarted, localReceivedAudio], timeout: 1)

        XCTAssertTrue(remote.configurations.isEmpty)
        XCTAssertTrue(remote.audioChunks.isEmpty)
        XCTAssertEqual(local.configurations, [configuration])
        XCTAssertEqual(local.audioChunks, [Data([1, 2])])
    }

    func testBackendFirstRealtimeFallsBackAndReplaysRecentAudio() async {
        let remote = RealtimeSpeechClientSpy()
        let local = RealtimeSpeechClientSpy()
        let client = BackendFirstRealtimeSpeechClient(
            remoteClient: remote,
            localClient: local
        )
        let configuration = RealtimeSpeechConfiguration(
            conversationId: UUID().uuidString,
            language: "ru-RU",
            processingMode: .allowSystemNetworkFallback
        )
        let firstChunk = Data([1, 2])
        let secondChunk = Data([3, 4])
        let remoteStarted = expectation(description: "Remote client started")
        let remoteReceivedAudio = expectation(description: "Remote client received audio")
        let localStarted = expectation(description: "Local fallback started")
        let replayedAudio = expectation(description: "Buffered audio replayed")
        replayedAudio.expectedFulfillmentCount = 2
        remote.onStart = { remoteStarted.fulfill() }
        remote.onAudioChunk = { remoteReceivedAudio.fulfill() }
        local.onStart = { localStarted.fulfill() }
        local.onAudioChunk = { replayedAudio.fulfill() }

        client.start(configuration: configuration)
        client.appendAudioChunk(firstChunk)
        await fulfillment(of: [remoteStarted, remoteReceivedAudio], timeout: 1)
        remote.emit(.failure(AppError.networkUnavailable))
        await fulfillment(of: [localStarted], timeout: 1)
        client.appendAudioChunk(secondChunk)
        local.emit(.connected)

        await fulfillment(of: [replayedAudio], timeout: 1)

        XCTAssertEqual(remote.configurations, [configuration])
        XCTAssertEqual(local.configurations, [configuration])
        XCTAssertEqual(local.audioChunks, [firstChunk, secondChunk])
    }

    func testBackendFirstRealtimeDoesNotStartFallbackAfterStop() async {
        let remote = RealtimeSpeechClientSpy()
        let local = RealtimeSpeechClientSpy()
        let client = BackendFirstRealtimeSpeechClient(
            remoteClient: remote,
            localClient: local
        )
        let configuration = RealtimeSpeechConfiguration(
            conversationId: UUID().uuidString,
            language: "ru-RU",
            processingMode: .allowSystemNetworkFallback
        )
        let remoteStarted = expectation(description: "Remote client started")
        let remoteStopped = expectation(description: "Remote client stopped")
        let sessionStopped = expectation(description: "Composite session stopped")
        remote.onStart = { remoteStarted.fulfill() }
        remote.onStop = { remoteStopped.fulfill() }
        client.eventHandler = { event in
            if case .stopped = event {
                sessionStopped.fulfill()
            }
        }

        client.start(configuration: configuration)
        await fulfillment(of: [remoteStarted], timeout: 1)
        client.stop()
        await fulfillment(of: [remoteStopped], timeout: 1)
        remote.emit(.failure(AppError.networkUnavailable))

        await fulfillment(of: [sessionStopped], timeout: 1)
        XCTAssertTrue(local.configurations.isEmpty)
    }

    private func makeContext() -> Context {
        let view = ListenViewSpy()
        let permission = MicrophonePermissionServiceStub()
        let audioCapture = RealtimeAudioCaptureServiceStub()
        let speechClient = RealtimeSpeechClientSpy()
        let delegate = ListenPresenterDelegateSpy()
        let presenter = ListenPresenter(
            view: view,
            microphonePermissionService: permission,
            audioCaptureService: audioCapture,
            speechClient: speechClient
        )
        presenter.delegate = delegate
        return Context(
            presenter: presenter,
            view: view,
            audioCapture: audioCapture,
            speechClient: speechClient,
            delegate: delegate,
            configuration: RealtimeSpeechConfiguration(
                conversationId: UUID().uuidString,
                language: "ru-RU",
                processingMode: .allowSystemNetworkFallback
            )
        )
    }

    private func makeSegment(
        id: String?,
        sequence: Int,
        text: String
    ) -> RealtimeSpeechSegment {
        RealtimeSpeechSegment(
            id: id,
            sequence: sequence,
            text: text,
            speakerId: "speaker_1",
            speakerLabel: "Говорящий 1",
            confidence: 0.9
        )
    }
}

@MainActor
private struct Context {
    let presenter: ListenPresenter
    let view: ListenViewSpy
    let audioCapture: RealtimeAudioCaptureServiceStub
    let speechClient: RealtimeSpeechClientSpy
    let delegate: ListenPresenterDelegateSpy
    let configuration: RealtimeSpeechConfiguration
}
