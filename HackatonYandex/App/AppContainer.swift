//
//  AppContainer.swift
//  HackatonYandex
//
//  Created by Rodion Kholodov.
//

import Foundation

protocol AppStateStoring: AnyObject {
    var hasSeenOnboarding: Bool { get set }
}

final class UserDefaultsAppStateStore: AppStateStoring {
    private enum Keys {
        static let hasSeenOnboarding = "hasSeenOnboarding"
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var hasSeenOnboarding: Bool {
        get {
            userDefaults.bool(forKey: Keys.hasSeenOnboarding)
        }
        set {
            userDefaults.set(newValue, forKey: Keys.hasSeenOnboarding)
        }
    }
}

final class AppContainer {
    let config: AppConfig
    let appStateStore: AppStateStoring
    private(set) lazy var microphonePermissionService: MicrophonePermissionService = DefaultMicrophonePermissionService()
    private(set) lazy var audioRecordingService: AudioRecordingService = DefaultAudioRecorderService()
    private(set) lazy var textToSpeechService: TextToSpeechService = DefaultTextToSpeechService()
    private(set) lazy var apiClient = APIClient(config: config)
    private(set) lazy var speechRecognitionService: SpeechRecognitionService = RemoteSpeechRecognitionService(
        apiClient: apiClient
    )
    private(set) lazy var coreDataStack = CoreDataStack()
    private(set) lazy var conversationRepository: ConversationRepository = CoreDataConversationRepository(
        coreDataStack: coreDataStack
    )
    private(set) lazy var phraseRepository: PhraseRepository = CoreDataPhraseRepository(
        coreDataStack: coreDataStack
    )
    private(set) lazy var fetchConversationHistoryUseCase = FetchConversationHistoryUseCase(
        repository: conversationRepository
    )
    private(set) lazy var fetchConversationMessagesUseCase = FetchConversationMessagesUseCase(
        repository: conversationRepository
    )
    private(set) lazy var saveConversationUseCase = SaveConversationUseCase(
        repository: conversationRepository
    )
    private(set) lazy var addConversationMessageUseCase = AddConversationMessageUseCase(
        repository: conversationRepository
    )
    private(set) lazy var deleteConversationUseCase = DeleteConversationUseCase(
        repository: conversationRepository
    )
    private(set) lazy var fetchPhrasesUseCase = FetchPhrasesUseCase(
        repository: phraseRepository
    )
    private(set) lazy var createPhraseUseCase = CreatePhraseUseCase(
        repository: phraseRepository
    )
    private(set) lazy var savePhraseUseCase = SavePhraseUseCase(
        repository: phraseRepository
    )
    private(set) lazy var deletePhraseUseCase = DeletePhraseUseCase(
        repository: phraseRepository
    )
    private(set) lazy var recordPhraseUsageUseCase = RecordPhraseUsageUseCase(
        repository: phraseRepository
    )

    init(
        config: AppConfig = .makeDefault(),
        appStateStore: AppStateStoring = UserDefaultsAppStateStore()
    ) {
        self.config = config
        self.appStateStore = appStateStore
    }
}
