//
//  NivyBarApp.swift
//  NivyBar
//

import SwiftUI

@main
struct NivyBarApp: App {

    @StateObject private var viewModel = MenuViewModel()
    @StateObject private var store     = UserRestaurantStore()

    init() {
        // Wire store into viewModel synchronously before any scene renders.
        // Can't call methods on @StateObject in init, so we use a post-init
        // trick via onAppear in the scene instead — see ContentView .task.
        // The attach() call is deferred to the first .task execution.
    }

    var body: some Scene {
        // MARK: Menu bar panel
        MenuBarExtra("NivyBar", systemImage: "fork.knife") {
            ContentView()
                .environmentObject(viewModel)
                .environmentObject(store)
                .task {
                    // Attach store on first appearance (safe — both objects are created)
                    viewModel.attach(store: store)
                }
        }
        .menuBarExtraStyle(.window)

        // MARK: Settings window (independent macOS window, not a panel)
        Window("Restaurant Settings", id: "settings") {
            SettingsView()
                .environmentObject(store)
                .environmentObject(viewModel)
        }
        .defaultSize(width: 760, height: 540)
    }
}
