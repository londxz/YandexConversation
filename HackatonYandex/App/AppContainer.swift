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
    private(set) lazy var settingsRepository: SettingsRepository = CoreDataSettingsRepository(
        coreDataStack: coreDataStack
    )
    private(set) lazy var localDataRepository: LocalDataRepository = CoreDataLocalDataRepository(
        coreDataStack: coreDataStack
    )
    private(set) lazy var fetchConversationHistoryUseCase = FetchConversationHistoryUseCase(
        repository: conversationRepository
    )
    private(set) lazy var fetchConversationMessagesUseCase = FetchConversationMessagesUseCase(
        repository: conversationRepository
    )
    private(set) lazy var fetchConversationUseCase = FetchConversationUseCase(
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
    private(set) lazy var fetchPhraseFoldersUseCase = FetchPhraseFoldersUseCase(
        repository: phraseRepository
    )
    private(set) lazy var createPhraseFolderUseCase = CreatePhraseFolderUseCase(
        repository: phraseRepository
    )
    private(set) lazy var savePhraseFolderUseCase = SavePhraseFolderUseCase(
        repository: phraseRepository
    )
    private(set) lazy var deletePhraseFolderUseCase = DeletePhraseFolderUseCase(
        repository: phraseRepository
    )
    private(set) lazy var fetchSettingsUseCase = FetchSettingsUseCase(
        repository: settingsRepository
    )
    private(set) lazy var saveSettingsUseCase = SaveSettingsUseCase(
        repository: settingsRepository
    )
    private(set) lazy var deleteAllUserDataUseCase = DeleteAllUserDataUseCase(
        repository: localDataRepository
    )

    init(
        config: AppConfig = .makeDefault(),
        appStateStore: AppStateStoring = UserDefaultsAppStateStore()
    ) {
        self.config = config
        self.appStateStore = appStateStore
    }

    func prepareRuntimeServices() {
        Task { [weak self] in
            guard let self else { return }

            do {
                let settings = try await self.fetchSettingsUseCase.execute()
                await MainActor.run {
                    self.textToSpeechService.apply(settings: settings)
                }
            } catch {
                AppLogger.error("Failed to prepare runtime settings: \(error.localizedDescription)")
            }
        }
    }
}
