//
//  PolarDriftApp.swift
//  PolarDrift
//
//  Created by 山口 伸行 on 2026/04/28.
//

import SwiftUI

@main
struct PolarDriftApp: App {
    @State private var sessionVM = SessionViewModel()

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(sessionVM)
                .preferredColorScheme(.dark)
        }
    }
}
