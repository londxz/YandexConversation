//
//  CoreDataConversationRepository.swift
//  HackatonYandex
//
//  Created by Rodion Kholodov.
//

import CoreData
import Foundation

final class CoreDataConversationRepository: ConversationRepository {
    private enum Entity {
        static let conversation = "CDConversation"
        static let message = "CDConversationMessage"
    }

    private let coreDataStack: CoreDataStack

    init(coreDataStack: CoreDataStack) {
        self.coreDataStack = coreDataStack
    }

    func fetchConversations() async throws -> [Conversation] {
        try await coreDataStack.perform { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: Entity.conversation)
            request.sortDescriptors = [
                NSSortDescriptor(key: "isPinned", ascending: false),
                NSSortDescriptor(key: "updatedAt", ascending: false)
            ]

            return try context.fetch(request).map(Self.mapConversation)
        }
    }

    func fetchMessages(conversationId: String) async throws -> [ConversationMessage] {
        try await coreDataStack.perform { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: Entity.message)
            request.predicate = NSPredicate(format: "conversationId == %@", conversationId)
            request.sortDescriptors = [
                NSSortDescriptor(key: "createdAt", ascending: true)
            ]

            return try context.fetch(request).map(Self.mapMessage)
        }
    }

    func saveConversation(_ conversation: Conversation) async throws {
        try await coreDataStack.perform { context in
            let object = try self.fetchObject(
                entityName: Entity.conversation,
                id: conversation.id,
                context: context
            ) ?? self.makeObject(entityName: Entity.conversation, context: context)

            object.setValue(conversation.id, forKey: "id")
            object.setValue(conversation.title, forKey: "title")
            object.setValue(conversation.mode.rawValue, forKey: "mode")
            object.setValue(conversation.createdAt, forKey: "createdAt")
            object.setValue(conversation.updatedAt, forKey: "updatedAt")
            object.setValue(conversation.isPinned, forKey: "isPinned")
            object.setValue(conversation.syncState.rawValue, forKey: "syncState")
        }
    }

    func saveMessage(_ message: ConversationMessage) async throws {
        try await coreDataStack.perform { context in
            let object = try self.fetchObject(
                entityName: Entity.message,
                id: message.id,
                context: context
            ) ?? self.makeObject(entityName: Entity.message, context: context)

            object.setValue(message.id, forKey: "id")
            object.setValue(message.conversationId, forKey: "conversationId")
            object.setValue(message.text, forKey: "text")
            object.setValue(message.source.rawValue, forKey: "source")
            object.setValue(message.speakerId, forKey: "speakerId")
            object.setValue(message.speakerLabel, forKey: "speakerLabel")
            object.setValue(message.isFinal, forKey: "isFinal")
            object.setValue(message.createdAt, forKey: "createdAt")
            if let audioDurationMs = message.audioDurationMs {
                object.setValue(NSNumber(value: audioDurationMs), forKey: "audioDurationMs")
            } else {
                object.setValue(nil, forKey: "audioDurationMs")
            }
            object.setValue(message.syncState.rawValue, forKey: "syncState")
        }
    }

    func deleteConversation(id: String) async throws {
        try await coreDataStack.perform { context in
            if let conversation = try self.fetchObject(
                entityName: Entity.conversation,
                id: id,
                context: context
            ) {
                context.delete(conversation)
            }

            let messageRequest = NSFetchRequest<NSManagedObject>(entityName: Entity.message)
            messageRequest.predicate = NSPredicate(format: "conversationId == %@", id)

            for message in try context.fetch(messageRequest) {
                context.delete(message)
            }
        }
    }
}

private extension CoreDataConversationRepository {
    func fetchObject(
        entityName: String,
        id: String,
        context: NSManagedObjectContext
    ) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    func makeObject(
        entityName: String,
        context: NSManagedObjectContext
    ) throws -> NSManagedObject {
        guard let entity = NSEntityDescription.entity(forEntityName: entityName, in: context) else {
            throw LocalStorageError.entityNotFound(entityName)
        }

        return NSManagedObject(entity: entity, insertInto: context)
    }

    static func mapConversation(_ object: NSManagedObject) throws -> Conversation {
        let modeRaw = try stringValue("mode", from: object)
        let syncStateRaw = try stringValue("syncState", from: object)

        guard let mode = Conversation.Mode(rawValue: modeRaw) else {
            throw LocalStorageError.invalidManagedObject("Unknown conversation mode: \(modeRaw)")
        }

        guard let syncState = SyncState(rawValue: syncStateRaw) else {
            throw LocalStorageError.invalidManagedObject("Unknown sync state: \(syncStateRaw)")
        }

        return Conversation(
            id: try stringValue("id", from: object),
            title: try stringValue("title", from: object),
            mode: mode,
            createdAt: try dateValue("createdAt", from: object),
            updatedAt: try dateValue("updatedAt", from: object),
            isPinned: boolValue("isPinned", from: object),
            syncState: syncState
        )
    }

    static func mapMessage(_ object: NSManagedObject) throws -> ConversationMessage {
        let sourceRaw = try stringValue("source", from: object)
        let syncStateRaw = try stringValue("syncState", from: object)

        guard let source = ConversationMessage.Source(rawValue: sourceRaw) else {
            throw LocalStorageError.invalidManagedObject("Unknown message source: \(sourceRaw)")
        }

        guard let syncState = SyncState(rawValue: syncStateRaw) else {
            throw LocalStorageError.invalidManagedObject("Unknown sync state: \(syncStateRaw)")
        }

        return ConversationMessage(
            id: try stringValue("id", from: object),
            conversationId: try stringValue("conversationId", from: object),
            text: try stringValue("text", from: object),
            source: source,
            speakerId: object.value(forKey: "speakerId") as? String,
            speakerLabel: object.value(forKey: "speakerLabel") as? String,
            isFinal: boolValue("isFinal", from: object),
            createdAt: try dateValue("createdAt", from: object),
            audioDurationMs: (object.value(forKey: "audioDurationMs") as? NSNumber)?.intValue,
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
}
