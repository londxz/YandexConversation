//
//  CoreDataStack.swift
//  HackatonYandex
//
//  Created by Rodion Kholodov.
//

import CoreData
import Foundation

enum LocalStorageError: LocalizedError {
    case persistentStoreLoadFailed(Error)
    case entityNotFound(String)
    case invalidManagedObject(String)

    var errorDescription: String? {
        switch self {
        case .persistentStoreLoadFailed(let error):
            return "Persistent store failed to load: \(error.localizedDescription)"
        case .entityNotFound(let name):
            return "Core Data entity not found: \(name)"
        case .invalidManagedObject(let details):
            return "Invalid Core Data object: \(details)"
        }
    }
}

final class CoreDataStack: @unchecked Sendable {
    let container: NSPersistentContainer

    private let loadGroup = DispatchGroup()
    private var persistentStoreError: Error?

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(
            name: "RazgovorLocalStore",
            managedObjectModel: Self.makeManagedObjectModel()
        )

        if inMemory {
            let description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
            container.persistentStoreDescriptions = [description]
        }

        for description in container.persistentStoreDescriptions {
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
            description.setOption(
                FileProtectionType.completeUntilFirstUserAuthentication as NSObject,
                forKey: NSPersistentStoreFileProtectionKey
            )
        }

        loadGroup.enter()
        container.loadPersistentStores { [weak self] _, error in
            if let error {
                self?.persistentStoreError = error
                AppLogger.error("Core Data store load failed: \(error.localizedDescription)")
            }

            self?.loadGroup.leave()
        }

        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    func perform<T>(_ work: @escaping (NSManagedObjectContext) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                self.loadGroup.wait()

                if let persistentStoreError = self.persistentStoreError {
                    continuation.resume(
                        throwing: LocalStorageError.persistentStoreLoadFailed(persistentStoreError)
                    )
                    return
                }

                self.container.performBackgroundTask { context in
                    context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

                    do {
                        let result = try work(context)

                        if context.hasChanges {
                            try context.save()
                        }

                        continuation.resume(returning: result)
                    } catch {
                        context.rollback()
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
}

private extension CoreDataStack {
    static func makeManagedObjectModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        let conversationEntity = NSEntityDescription()
        conversationEntity.name = "CDConversation"
        conversationEntity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        conversationEntity.properties = [
            attribute("id", type: .stringAttributeType),
            attribute("title", type: .stringAttributeType),
            attribute("mode", type: .stringAttributeType),
            attribute("createdAt", type: .dateAttributeType),
            attribute("updatedAt", type: .dateAttributeType),
            attribute("isPinned", type: .booleanAttributeType),
            attribute("syncState", type: .stringAttributeType)
        ]
        conversationEntity.uniquenessConstraints = [["id"]]

        let messageEntity = NSEntityDescription()
        messageEntity.name = "CDConversationMessage"
        messageEntity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        messageEntity.properties = [
            attribute("id", type: .stringAttributeType),
            attribute("conversationId", type: .stringAttributeType),
            attribute("text", type: .stringAttributeType),
            attribute("source", type: .stringAttributeType),
            attribute("speakerId", type: .stringAttributeType, isOptional: true),
            attribute("speakerLabel", type: .stringAttributeType, isOptional: true),
            attribute("isFinal", type: .booleanAttributeType),
            attribute("createdAt", type: .dateAttributeType),
            attribute("audioDurationMs", type: .integer64AttributeType, isOptional: true),
            attribute("syncState", type: .stringAttributeType)
        ]
        messageEntity.uniquenessConstraints = [["id"]]

        let phraseEntity = NSEntityDescription()
        phraseEntity.name = "CDPhrase"
        phraseEntity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        phraseEntity.properties = [
            attribute("id", type: .stringAttributeType),
            attribute("folderId", type: .stringAttributeType, isOptional: true),
            attribute("text", type: .stringAttributeType),
            attribute("category", type: .stringAttributeType, isOptional: true),
            attribute("isFavorite", type: .booleanAttributeType),
            attribute("sortOrder", type: .integer64AttributeType),
            attribute("usageCount", type: .integer64AttributeType),
            attribute("createdAt", type: .dateAttributeType),
            attribute("updatedAt", type: .dateAttributeType),
            attribute("syncState", type: .stringAttributeType)
        ]
        phraseEntity.uniquenessConstraints = [["id"]]

        let phraseFolderEntity = NSEntityDescription()
        phraseFolderEntity.name = "CDPhraseFolder"
        phraseFolderEntity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        phraseFolderEntity.properties = [
            attribute("id", type: .stringAttributeType),
            attribute("title", type: .stringAttributeType),
            attribute("sortOrder", type: .integer64AttributeType)
        ]
        phraseFolderEntity.uniquenessConstraints = [["id"]]

        let metadataEntity = NSEntityDescription()
        metadataEntity.name = "CDLocalMetadata"
        metadataEntity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        metadataEntity.properties = [
            attribute("key", type: .stringAttributeType),
            attribute("value", type: .stringAttributeType),
            attribute("updatedAt", type: .dateAttributeType)
        ]
        metadataEntity.uniquenessConstraints = [["key"]]

        let settingsEntity = NSEntityDescription()
        settingsEntity.name = "CDAppSettings"
        settingsEntity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        settingsEntity.properties = [
            attribute("id", type: .stringAttributeType),
            attribute("recognitionLanguage", type: .stringAttributeType),
            attribute("ttsLanguage", type: .stringAttributeType),
            attribute("ttsVoiceIdentifier", type: .stringAttributeType, isOptional: true),
            attribute("speechRate", type: .floatAttributeType),
            attribute("transcriptFontScale", type: .floatAttributeType),
            attribute("autoStartMicrophone", type: .booleanAttributeType),
            attribute("saveConversationsByDefault", type: .booleanAttributeType),
            attribute("syncEnabled", type: .booleanAttributeType),
            attribute("privacyMode", type: .stringAttributeType),
            attribute("updatedAt", type: .dateAttributeType)
        ]
        settingsEntity.uniquenessConstraints = [["id"]]

        model.entities = [
            conversationEntity,
            messageEntity,
            phraseEntity,
            phraseFolderEntity,
            metadataEntity,
            settingsEntity
        ]

        return model
    }

    static func attribute(
        _ name: String,
        type: NSAttributeType,
        isOptional: Bool = false
    ) -> NSAttributeDescription {
        let description = NSAttributeDescription()
        description.name = name
        description.attributeType = type
        description.isOptional = isOptional
        return description
    }
}
