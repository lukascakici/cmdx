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
    }
    
    var body: some Scene {
        MenuBarExtra("cmdx", systemImage: "scissors") {
            ContentView()
        }
        .menuBarExtraStyle(.window)
    }
}
