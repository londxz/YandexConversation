//
//  CoreDataSettingsRepository.swift
//  HackatonYandex
//
//  Created by Rodion Kholodov.
//

import CoreData
import Foundation

final class CoreDataSettingsRepository: SettingsRepository {
    private enum Constants {
        static let entityName = "CDAppSettings"
        static let currentSettingsID = "current"
    }

    private let coreDataStack: CoreDataStack

    init(coreDataStack: CoreDataStack) {
        self.coreDataStack = coreDataStack
    }

    func fetchSettings() async throws -> AppSettings {
        try await coreDataStack.perform { context in
            guard let object = try self.fetchSettingsObject(context: context) else {
                return .defaultValue
            }

            return try Self.mapSettings(object)
        }
    }

    func saveSettings(_ settings: AppSettings) async throws {
        try await coreDataStack.perform { context in
            let object = try self.fetchSettingsObject(context: context)
                ?? self.makeSettingsObject(context: context)

            object.setValue(Constants.currentSettingsID, forKey: "id")
            object.setValue(settings.recognitionLanguage, forKey: "recognitionLanguage")
            object.setValue(settings.ttsLanguage, forKey: "ttsLanguage")
            object.setValue(settings.ttsVoiceIdentifier, forKey: "ttsVoiceIdentifier")
            object.setValue(NSNumber(value: settings.speechRate), forKey: "speechRate")
            object.setValue(NSNumber(value: settings.transcriptFontScale), forKey: "transcriptFontScale")
            object.setValue(settings.autoStartMicrophone, forKey: "autoStartMicrophone")
            object.setValue(settings.saveConversationsByDefault, forKey: "saveConversationsByDefault")
            object.setValue(settings.syncEnabled, forKey: "syncEnabled")
            object.setValue(settings.privacyMode.rawValue, forKey: "privacyMode")
            object.setValue(Date(), forKey: "updatedAt")
        }
    }
}

private extension CoreDataSettingsRepository {
    func fetchSettingsObject(context: NSManagedObjectContext) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: Constants.entityName)
        request.predicate = NSPredicate(format: "id == %@", Constants.currentSettingsID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    func makeSettingsObject(context: NSManagedObjectContext) -> NSManagedObject {
        NSEntityDescription.insertNewObject(
            forEntityName: Constants.entityName,
            into: context
        )
    }

    static func mapSettings(_ object: NSManagedObject) throws -> AppSettings {
        let privacyModeRaw = try stringValue("privacyMode", from: object)
        guard let privacyMode = AppSettings.PrivacyMode(rawValue: privacyModeRaw) else {
            throw LocalStorageError.invalidManagedObject(
                "Unknown privacy mode: \(privacyModeRaw)"
            )
        }

        return AppSettings(
            recognitionLanguage: try stringValue("recognitionLanguage", from: object),
            ttsLanguage: try stringValue("ttsLanguage", from: object),
            ttsVoiceIdentifier: object.value(forKey: "ttsVoiceIdentifier") as? String,
            speechRate: floatValue("speechRate", from: object),
            transcriptFontScale: floatValue("transcriptFontScale", from: object),
            autoStartMicrophone: boolValue("autoStartMicrophone", from: object),
            saveConversationsByDefault: boolValue("saveConversationsByDefault", from: object),
            syncEnabled: boolValue("syncEnabled", from: object),
            privacyMode: privacyMode
        )
    }

    static func stringValue(_ key: String, from object: NSManagedObject) throws -> String {
        guard let value = object.value(forKey: key) as? String else {
            throw LocalStorageError.invalidManagedObject("Missing string value for \(key)")
        }

        return value
    }

    static func boolValue(_ key: String, from object: NSManagedObject) -> Bool {
        (object.value(forKey: key) as? NSNumber)?.boolValue ?? false
    }

    static func floatValue(_ key: String, from object: NSManagedObject) -> Float {
        (object.value(forKey: key) as? NSNumber)?.floatValue ?? 0
    }
}
