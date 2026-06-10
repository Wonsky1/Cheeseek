//
//  MyshachkiApp.swift
//  Myshachki
//
//  Created by Vlad Pidborskyi on 08.06.2026.
//

import SwiftUI

@main
struct MyshachkiApp: App {
    @StateObject private var dependencies = AppDependencies.live

    var body: some Scene {
        WindowGroup {
            ContentView(dependencies: dependencies)
        }
    }
}
