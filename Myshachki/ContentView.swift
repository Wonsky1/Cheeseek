import SwiftUI

struct ContentView: View {
    let dependencies: AppDependencies

    var body: some View {
        RootTabView(dependencies: dependencies)
    }
}

#Preview {
    ContentView(dependencies: .preview)
}
