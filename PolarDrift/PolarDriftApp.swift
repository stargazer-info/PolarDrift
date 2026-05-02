//
//  PolarDriftApp.swift
//  PolarDrift
//
//  Created by 山口 伸行 on 2026/04/28.
//

import SwiftUI

@main
struct PolarDriftApp: App {
    @State private var speech: SpeechRecognitionManager
    @State private var sessionVM: AppSessionViewModel
//    @State private var speech = SpeechRecognitionManager()
//    @State private var sessionVM: AppSessionViewModel

    init() {
        let s = SpeechRecognitionManager()
        _speech = State(initialValue: s)
        _sessionVM = State(initialValue: AppSessionViewModel(speech: s))
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(sessionVM)
                .environment(speech)
                .preferredColorScheme(.dark)
        }
    }
}
