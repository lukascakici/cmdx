//
//  cmdxApp.swift
//  cmdx
//
//  Created by cmdx project on 25.03.2026.
//

import SwiftUI

@main
struct cmdxApp: App {
    init() {
        EventInterceptor.shared.start()
        
        // Clean up pasteboard on app termination
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            EventInterceptor.shared.cleanup()
        }
    }
    
    var body: some Scene {
        MenuBarExtra("cmdx", systemImage: "scissors") {
            ContentView()
        }
        .menuBarExtraStyle(.window)
    }
}
