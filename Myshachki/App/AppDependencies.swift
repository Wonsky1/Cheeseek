import Combine
import Foundation

@MainActor
final class AppDependencies: ObservableObject {
    let serverConfiguration: ServerConfiguration
    let apiClient: APIClient
    let locationManager: LocationManager
    let walkSessionStore: WalkSessionStoring
    let coverageStore: CoverageStoring
    let profileStore: ProfileStoring
    let profileService: ProfileServing
    let backendSyncService: BackendSyncServing
    let mockRouteProvider: MockRouteProviding

    init(
        serverConfiguration: ServerConfiguration,
        apiClient: APIClient,
        locationManager: LocationManager,
        walkSessionStore: WalkSessionStoring,
        coverageStore: CoverageStoring,
        profileStore: ProfileStoring,
        profileService: ProfileServing,
        backendSyncService: BackendSyncServing,
        mockRouteProvider: MockRouteProviding
    ) {
        self.serverConfiguration = serverConfiguration
        self.apiClient = apiClient
        self.locationManager = locationManager
        self.walkSessionStore = walkSessionStore
        self.coverageStore = coverageStore
        self.profileStore = profileStore
        self.profileService = profileService
        self.backendSyncService = backendSyncService
        self.mockRouteProvider = mockRouteProvider
    }

    static var live: AppDependencies {
        let serverConfiguration = ServerConfiguration()
        let apiClient = APIClient(baseURL: serverConfiguration.baseURL)
        let profileStore = ProfileStore()
        let profileService = ProfileService(apiClient: apiClient, profileStore: profileStore)
        return AppDependencies(
            serverConfiguration: serverConfiguration,
            apiClient: apiClient,
            locationManager: LocationManager(),
            walkSessionStore: FileWalkSessionStore(),
            coverageStore: CoverageStore(),
            profileStore: profileStore,
            profileService: profileService,
            backendSyncService: HTTPBackendSyncService(apiClient: apiClient),
            mockRouteProvider: MockRouteProvider()
        )
    }

    static var preview: AppDependencies {
        let serverConfiguration = ServerConfiguration(baseURL: URL(string: "https://unconsecrative-lustrelessly-jeanie.ngrok-free.dev")!)
        let apiClient = APIClient(baseURL: serverConfiguration.baseURL)
        let profileStore = InMemoryProfileStore(
            profile: UserProfile(
                id: UUID(),
                nickname: "Vlad",
                deviceId: UUID(),
                createdAt: Date()
            )
        )
        let profileService = PreviewProfileService(profileStore: profileStore)
        return AppDependencies(
            serverConfiguration: serverConfiguration,
            apiClient: apiClient,
            locationManager: LocationManager.preview,
            walkSessionStore: PreviewWalkSessionStore(),
            coverageStore: InMemoryCoverageStore(),
            profileStore: profileStore,
            profileService: profileService,
            backendSyncService: MockBackendSyncService(),
            mockRouteProvider: MockRouteProvider()
        )
    }
}
