//
//  TodoWatchApp.swift
//  TodoWatch
//
//  mdTodo watchOS Companion App
//  Minimal app for adding tasks to iCloud Drive via voice input.
//

import SwiftUI

@main
struct TodoWatchApp: App {
    var body: some Scene {
        WindowGroup {
            VoiceInputView()
        }
    }
}
