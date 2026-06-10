import SwiftUI

struct RootTabView: View {
    @StateObject private var mapViewModel: MapViewModel
    @StateObject private var activityViewModel: ActivityViewModel
    @StateObject private var profileViewModel: ProfileViewModel
    private let dependencies: AppDependencies

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        _mapViewModel = StateObject(wrappedValue: MapViewModel(
            locationManager: dependencies.locationManager,
            walkSessionStore: dependencies.walkSessionStore,
            coverageStore: dependencies.coverageStore,
            backendSyncService: dependencies.backendSyncService,
            mockRouteProvider: dependencies.mockRouteProvider,
            profileService: dependencies.profileService
        ))
        _activityViewModel = StateObject(wrappedValue: ActivityViewModel(
            walkSessionStore: dependencies.walkSessionStore,
            profileService: dependencies.profileService
        ))
        _profileViewModel = StateObject(wrappedValue: ProfileViewModel(profileService: dependencies.profileService))
    }

    var body: some View {
        TabView {
            MapScreen(viewModel: mapViewModel, backendSyncService: dependencies.backendSyncService)
                .tabItem {
                    Label("Map", systemImage: "map")
                }

            ActivityView(viewModel: activityViewModel)
                .tabItem {
                    Label("Activity", systemImage: "figure.walk")
                }

            ProfileView(viewModel: profileViewModel, serverBaseURL: dependencies.serverConfiguration.baseURL)
                .tabItem {
                    Label("Profile", systemImage: "person.crop.circle")
                }
        }
        .task {
            await mapViewModel.onAppear()
            await activityViewModel.refresh()
        }
        .onReceive(dependencies.locationManager.$latestLocation) { _ in
            mapViewModel.refreshLocation()
        }
        .onReceive(dependencies.locationManager.$authorizationStatus) { _ in
            mapViewModel.refreshLocationStatus()
        }
        .onChange(of: mapViewModel.summarySession?.id) { _, _ in
            Task { await activityViewModel.refresh() }
        }
        .onChange(of: profileViewModel.profile) { _, _ in
            Task {
                await mapViewModel.refreshForProfileChange()
                await activityViewModel.refresh()
            }
        }
    }
}
