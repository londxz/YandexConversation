//
//  DefaultRealtimeAudioCaptureService.swift
//  HackatonYandex
//
//  Created by Rodion Kholodov.
//

import AVFoundation
import Foundation

final class DefaultRealtimeAudioCaptureService: RealtimeAudioCaptureService {
    private let audioEngine: AVAudioEngine
    private let audioSession: AVAudioSession
    private let processingQueue = DispatchQueue(
        label: "com.rodionkholodov.razgovor.realtime-audio",
        qos: .userInitiated
    )
    private let stateLock = NSLock()
    private let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )!

    private var converter: AVAudioConverter?
    private var chunkHandler: ((Data) -> Void)?
    private var capturing = false

    init(
        audioEngine: AVAudioEngine = AVAudioEngine(),
        audioSession: AVAudioSession = .sharedInstance()
    ) {
        self.audioEngine = audioEngine
        self.audioSession = audioSession
    }

    var isCapturing: Bool {
        stateLock.withLock { capturing }
    }

    func startCapture(onAudioChunk: @escaping (Data) -> Void) throws {
        guard !isCapturing else { return }

        try audioSession.setCategory(
            .record,
            mode: .measurement,
            options: [.duckOthers]
        )
        try audioSession.setActive(true)

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0,
              inputFormat.channelCount > 0,
              let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            throw AppError.speechUnavailable
        }

        stateLock.withLock {
            self.converter = converter
            chunkHandler = onAudioChunk
            capturing = true
        }

        inputNode.installTap(
            onBus: 0,
            bufferSize: 3_200,
            format: inputFormat
        ) { [weak self] buffer, _ in
            guard let self,
                  let bufferCopy = Self.copyBuffer(buffer) else {
                return
            }
            processingQueue.async { [weak self] in
                self?.convertAndDeliver(bufferCopy)
            }
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            stateLock.withLock {
                capturing = false
                chunkHandler = nil
                self.converter = nil
            }
            try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            throw error
        }
    }

    func stopCapture() {
        let wasCapturing = stateLock.withLock { () -> Bool in
            guard capturing else { return false }
            capturing = false
            chunkHandler = nil
            return true
        }
        guard wasCapturing else { return }

        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        processingQueue.async { [weak self] in
            self?.stateLock.withLock {
                self?.converter = nil
            }
        }
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func convertAndDeliver(_ inputBuffer: AVAudioPCMBuffer) {
        let currentState = stateLock.withLock {
            (capturing, converter, chunkHandler)
        }
        guard currentState.0,
              let converter = currentState.1,
              let chunkHandler = currentState.2 else {
            return
        }

        let ratio = outputFormat.sampleRate / inputBuffer.format.sampleRate
        let capacity = AVAudioFrameCount(
            max(1, ceil(Double(inputBuffer.frameLength) * ratio) + 1)
        )
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: capacity
        ) else {
            return
        }

        var suppliedInput = false
        var conversionError: NSError?
        let status = converter.convert(
            to: outputBuffer,
            error: &conversionError
        ) { _, inputStatus in
            guard !suppliedInput else {
                inputStatus.pointee = .noDataNow
                return nil
            }
            suppliedInput = true
            inputStatus.pointee = .haveData
            return inputBuffer
        }
        guard status != .error,
              conversionError == nil,
              outputBuffer.frameLength > 0,
              let channelData = outputBuffer.int16ChannelData else {
            return
        }

        let data = Data(
            bytes: channelData[0],
            count: Int(outputBuffer.frameLength) * MemoryLayout<Int16>.size
        )
        guard !data.isEmpty else { return }
        chunkHandler(data)
    }

    private static func copyBuffer(_ source: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(
            pcmFormat: source.format,
            frameCapacity: source.frameCapacity
        ) else {
            return nil
        }
        copy.frameLength = source.frameLength

        let sourceBuffers = UnsafeMutableAudioBufferListPointer(source.mutableAudioBufferList)
        let destinationBuffers = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        guard sourceBuffers.count == destinationBuffers.count else { return nil }

        for index in sourceBuffers.indices {
            guard let sourceData = sourceBuffers[index].mData,
                  let destinationData = destinationBuffers[index].mData else {
                return nil
            }
            let byteCount = Int(sourceBuffers[index].mDataByteSize)
            memcpy(destinationData, sourceData, byteCount)
            destinationBuffers[index].mDataByteSize = sourceBuffers[index].mDataByteSize
        }
        return copy
    }
}

private extension NSLock {
    func withLock<Result>(_ body: () throws -> Result) rethrows -> Result {
        lock()
        defer { unlock() }
        return try body()
    }
}
