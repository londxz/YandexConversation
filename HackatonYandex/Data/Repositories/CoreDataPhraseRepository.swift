//
//  CoreDataPhraseRepository.swift
//  HackatonYandex
//
//  Created by Rodion Kholodov.
//

import CoreData
import Foundation

final class CoreDataPhraseRepository: PhraseRepository {
    private enum Entity {
        static let phrase = "CDPhrase"
        static let metadata = "CDLocalMetadata"
    }

    private enum MetadataKey {
        static let starterPhrasesSeeded = "starterPhrasesSeeded"
    }

    private let coreDataStack: CoreDataStack

    init(coreDataStack: CoreDataStack) {
        self.coreDataStack = coreDataStack
    }

    func fetchPhrases() async throws -> [Phrase] {
        try await coreDataStack.perform { context in
            let phrases = try self.fetchPhraseObjects(context: context)
            let hasSeededStarterPhrases = try self.metadataBool(
                key: MetadataKey.starterPhrasesSeeded,
                context: context
            )

            if phrases.isEmpty && !hasSeededStarterPhrases {
                try self.seedStarterPhrases(context: context)
                try self.setMetadataBool(
                    true,
                    key: MetadataKey.starterPhrasesSeeded,
                    context: context
                )
                return try self.fetchPhraseObjects(context: context).map(Self.mapPhrase)
            }

            if !phrases.isEmpty && !hasSeededStarterPhrases {
                try self.setMetadataBool(
                    true,
                    key: MetadataKey.starterPhrasesSeeded,
                    context: context
                )
            }

            return try phrases.map(Self.mapPhrase)
        }
    }

    func savePhrase(_ phrase: Phrase) async throws {
        try await coreDataStack.perform { context in
            let object = try self.fetchObject(
                id: phrase.id,
                context: context
            ) ?? self.makeObject(context: context)

            object.setValue(phrase.id, forKey: "id")
            object.setValue(phrase.folderId, forKey: "folderId")
            object.setValue(phrase.text, forKey: "text")
            object.setValue(phrase.category, forKey: "category")
            object.setValue(phrase.isFavorite, forKey: "isFavorite")
            object.setValue(NSNumber(value: phrase.sortOrder), forKey: "sortOrder")
            object.setValue(NSNumber(value: phrase.usageCount), forKey: "usageCount")
            object.setValue(phrase.createdAt, forKey: "createdAt")
            object.setValue(phrase.updatedAt, forKey: "updatedAt")
            object.setValue(phrase.syncState.rawValue, forKey: "syncState")
        }
    }

    func deletePhrase(id: String) async throws {
        try await coreDataStack.perform { context in
            if let object = try self.fetchObject(id: id, context: context) {
                context.delete(object)
            }
        }
    }
}

private extension CoreDataPhraseRepository {
    func fetchPhraseObjects(context: NSManagedObjectContext) throws -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: Entity.phrase)
        request.sortDescriptors = [
            NSSortDescriptor(key: "isFavorite", ascending: false),
            NSSortDescriptor(key: "sortOrder", ascending: true),
            NSSortDescriptor(key: "updatedAt", ascending: false)
        ]
        return try context.fetch(request)
    }

    func fetchObject(
        id: String,
        context: NSManagedObjectContext
    ) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: Entity.phrase)
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    func makeObject(context: NSManagedObjectContext) throws -> NSManagedObject {
        guard let entity = NSEntityDescription.entity(forEntityName: Entity.phrase, in: context) else {
            throw LocalStorageError.entityNotFound(Entity.phrase)
        }

        return NSManagedObject(entity: entity, insertInto: context)
    }

    func metadataBool(
        key: String,
        context: NSManagedObjectContext
    ) throws -> Bool {
        guard let object = try fetchMetadataObject(key: key, context: context) else {
            return false
        }

        return (object.value(forKey: "value") as? String) == "true"
    }

    func setMetadataBool(
        _ value: Bool,
        key: String,
        context: NSManagedObjectContext
    ) throws {
        let object = try fetchMetadataObject(key: key, context: context)
            ?? makeMetadataObject(context: context)

        object.setValue(key, forKey: "key")
        object.setValue(value ? "true" : "false", forKey: "value")
        object.setValue(Date(), forKey: "updatedAt")
    }

    func fetchMetadataObject(
        key: String,
        context: NSManagedObjectContext
    ) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: Entity.metadata)
        request.predicate = NSPredicate(format: "key == %@", key)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    func makeMetadataObject(context: NSManagedObjectContext) throws -> NSManagedObject {
        guard let entity = NSEntityDescription.entity(forEntityName: Entity.metadata, in: context) else {
            throw LocalStorageError.entityNotFound(Entity.metadata)
        }

        return NSManagedObject(entity: entity, insertInto: context)
    }

    func seedStarterPhrases(context: NSManagedObjectContext) throws {
        for phrase in Phrase.starterPhrases {
            let object = try makeObject(context: context)
            object.setValue(phrase.id, forKey: "id")
            object.setValue(phrase.folderId, forKey: "folderId")
            object.setValue(phrase.text, forKey: "text")
            object.setValue(phrase.category, forKey: "category")
            object.setValue(phrase.isFavorite, forKey: "isFavorite")
            object.setValue(NSNumber(value: phrase.sortOrder), forKey: "sortOrder")
            object.setValue(NSNumber(value: phrase.usageCount), forKey: "usageCount")
            object.setValue(phrase.createdAt, forKey: "createdAt")
            object.setValue(phrase.updatedAt, forKey: "updatedAt")
            object.setValue(phrase.syncState.rawValue, forKey: "syncState")
        }
    }

    static func mapPhrase(_ object: NSManagedObject) throws -> Phrase {
        let syncStateRaw = try stringValue("syncState", from: object)

        guard let syncState = SyncState(rawValue: syncStateRaw) else {
            throw LocalStorageError.invalidManagedObject("Unknown sync state: \(syncStateRaw)")
        }

        return Phrase(
            id: try stringValue("id", from: object),
            folderId: object.value(forKey: "folderId") as? String,
            text: try stringValue("text", from: object),
            category: object.value(forKey: "category") as? String,
            isFavorite: boolValue("isFavorite", from: object),
            sortOrder: intValue("sortOrder", from: object),
            usageCount: intValue("usageCount", from: object),
            createdAt: try dateValue("createdAt", from: object),
            updatedAt: try dateValue("updatedAt", from: object),
            syncState: syncState
        )
    }

    static func stringValue(_ key: String, from object: NSManagedObject) throws -> String {
        guard let value = object.value(forKey: key) as? String else {
            throw LocalStorageError.invalidManagedObject("Missing string value for \(key)")
        }

        return value
    }

    static func dateValue(_ key: String, from object: NSManagedObject) throws -> Date {
        guard let value = object.value(forKey: key) as? Date else {
            throw LocalStorageError.invalidManagedObject("Missing date value for \(key)")
        }

        return value
    }

    static func boolValue(_ key: String, from object: NSManagedObject) -> Bool {
        (object.value(forKey: key) as? NSNumber)?.boolValue ?? false
    }

    static func intValue(_ key: String, from object: NSManagedObject) -> Int {
        (object.value(forKey: key) as? NSNumber)?.intValue ?? 0
    }
}
