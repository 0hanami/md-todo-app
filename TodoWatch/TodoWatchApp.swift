//
//  TodoWatchApp.swift
//  TodoWatch
//
//  mdTodo watchOS Companion App
//  音声入力でタスクをiCloud Driveに追加する最小構成アプリ
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
