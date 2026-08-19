//
//  CoreDataLocalDataRepository.swift
//  HackatonYandex
//
//  Created by Rodion Kholodov.
//

import CoreData
import Foundation

final class CoreDataLocalDataRepository: LocalDataRepository {
    private let coreDataStack: CoreDataStack

    init(coreDataStack: CoreDataStack) {
        self.coreDataStack = coreDataStack
    }

    func deleteAllUserData() async throws {
        try await coreDataStack.perform { context in
            let entityNames = [
                "CDConversationMessage",
                "CDConversation",
                "CDPhrase",
                "CDPhraseFolder",
                "CDLocalMetadata",
                "CDAppSettings"
            ]

            for entityName in entityNames {
                let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
                request.includesPropertyValues = false
                for object in try context.fetch(request) {
                    context.delete(object)
                }
            }
        }
    }
}
