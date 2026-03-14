//
//  ScowldApp.swift
//  Scowld
//
//  Created by Apoorv Darshan on 14/03/26.
//

import SwiftUI
import CoreData

@main
struct ScowldApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
