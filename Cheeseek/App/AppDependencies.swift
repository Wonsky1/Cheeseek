import Combine
import Foundation

@MainActor
final class AppDependencies: ObservableObject {
    let serverConfiguration: ServerConfiguration
    let apiClient: APIClient
    let locationManager: LocationManager
    let coverageStore: CoverageStoring
    let profileStore: ProfileStoring
    let profileService: ProfileServing
    let backendSyncService: BackendSyncServing
    let mockRouteProvider: MockRouteProviding
    let walkLiveActivityService: WalkLiveActivityService

    init(
        serverConfiguration: ServerConfiguration,
        apiClient: APIClient,
        locationManager: LocationManager,
        coverageStore: CoverageStoring,
        profileStore: ProfileStoring,
        profileService: ProfileServing,
        backendSyncService: BackendSyncServing,
        mockRouteProvider: MockRouteProviding,
        walkLiveActivityService: WalkLiveActivityService
    ) {
        self.serverConfiguration = serverConfiguration
        self.apiClient = apiClient
        self.locationManager = locationManager
        self.coverageStore = coverageStore
        self.profileStore = profileStore
        self.profileService = profileService
        self.backendSyncService = backendSyncService
        self.mockRouteProvider = mockRouteProvider
        self.walkLiveActivityService = walkLiveActivityService
    }

    static var live: AppDependencies {
        let serverConfiguration = ServerConfiguration()
        let apiClient = APIClient(baseURLProvider: { serverConfiguration.baseURL })
        let profileStore = ProfileStore()
        let profileService = ProfileService(apiClient: apiClient, profileStore: profileStore)
        return AppDependencies(
            serverConfiguration: serverConfiguration,
            apiClient: apiClient,
            locationManager: LocationManager(),
            coverageStore: CoverageStore(),
            profileStore: profileStore,
            profileService: profileService,
            backendSyncService: HTTPBackendSyncService(apiClient: apiClient),
            mockRouteProvider: MockRouteProvider(),
            walkLiveActivityService: WalkLiveActivityService()
        )
    }

    static var preview: AppDependencies {
        let serverConfiguration = ServerConfiguration(baseURL: URL(string: "https://unconsecrative-lustrelessly-jeanie.ngrok-free.dev")!)
        let apiClient = APIClient(baseURLProvider: { serverConfiguration.baseURL })
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
            coverageStore: InMemoryCoverageStore(),
            profileStore: profileStore,
            profileService: profileService,
            backendSyncService: MockBackendSyncService(),
            mockRouteProvider: MockRouteProvider(),
            walkLiveActivityService: WalkLiveActivityService()
        )
    }
}
