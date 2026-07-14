//
//  NivyBarApp.swift
//  NivyBar
//

import SwiftUI

@main
struct NivyBarApp: App {

    @StateObject private var viewModel = MenuViewModel()

    var body: some Scene {
        // MenuBarExtra with .window style (macOS 13+)
        // Fixed size enforced in ContentView via .frame
        MenuBarExtra("NivyBar", systemImage: "fork.knife") {
            ContentView()
                .environmentObject(viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}
