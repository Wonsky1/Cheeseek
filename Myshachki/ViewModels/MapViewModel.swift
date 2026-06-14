import Combine
import CoreLocation
import MapKit
import SwiftUI

@MainActor
final class MapViewModel: ObservableObject {
    private static let mapPerspectiveModeDefaultsKey = "myshachki.mapPerspectiveMode"
    private static let mapStyleModeDefaultsKey = "myshachki.mapStyleMode"

    @Published var selectedFilter: MapFilter = .me
    @Published private(set) var mapPerspectiveMode: MapPerspectiveMode
    @Published private(set) var mapStyleMode: MapStyleMode
    @Published private(set) var storedSessions: [WalkSession] = []
    @Published private(set) var sharedProgress: SharedProgress = .placeholder
    @Published private(set) var walkState: WalkState = .idle
    @Published private(set) var activeSession: WalkSession?
    @Published private(set) var elapsedTime: TimeInterval = 0
    @Published private(set) var liveDistance: Double = 0
    @Published private(set) var mapRoutes: [RouteOverlay] = []
    @Published private(set) var exploredBuildingAreas: [CoverageBuildingArea] = []
    @Published private(set) var activeBuildingAreas: [CoverageBuildingArea] = []
    @Published private(set) var permissionMessage = "Allow location to draw live routes."
    @Published var cameraPosition: MapCameraPosition
    @Published private(set) var mapFeatureGeoJSON = #"{"type":"FeatureCollection","features":[]}"#
    @Published private(set) var activeRouteGeoJSON = #"{"type":"FeatureCollection","features":[]}"#
    @Published private(set) var mapCenterCoordinate: CLLocationCoordinate2D
    @Published private(set) var userCoordinate: CLLocationCoordinate2D?
    @Published var summarySession: WalkSession?
    @Published private(set) var syncStatusText: String = SyncStatus.localOnly.label
    @Published private(set) var isFinishingWalk = false
    @Published private(set) var isFollowingUser = true

    private let locationManager: LocationManager
    private let walkSessionStore: WalkSessionStoring
    private let coverageStore: CoverageStoring
    private let backendSyncService: BackendSyncServing
    private let mockRouteProvider: MockRouteProviding
    private let profileService: ProfileServing
    private let walkLiveActivityService: WalkLiveActivityService
    private var timer: Timer?
    private var currentProfile: UserProfile?
    private var persistedCoverageSideIDs: Set<String> = []
    private var activeCoverageSideIDs: Set<String> = []
    private var lastAcceptedLocation: CLLocation?
    private let defaultCoordinate = CLLocationCoordinate2D(latitude: 52.2297, longitude: 21.0122)
    private let coverageAreaID = "osm-building-sides-v1"
    private let boardLatSpan = 0.014
    private let boardLonSpan = 0.021
    private let liveRouteInterpolationStepMeters = 2.0
    private let maxLiveRouteVisualCoordinates = 700

    init(
        locationManager: LocationManager,
        walkSessionStore: WalkSessionStoring,
        coverageStore: CoverageStoring,
        backendSyncService: BackendSyncServing,
        mockRouteProvider: MockRouteProviding,
        profileService: ProfileServing,
        walkLiveActivityService: WalkLiveActivityService
    ) {
        self.locationManager = locationManager
        self.walkSessionStore = walkSessionStore
        self.coverageStore = coverageStore
        self.backendSyncService = backendSyncService
        self.mockRouteProvider = mockRouteProvider
        self.profileService = profileService
        self.walkLiveActivityService = walkLiveActivityService
        self.mapPerspectiveMode = Self.loadPersistedMapPerspectiveMode()
        self.mapStyleMode = Self.loadPersistedMapStyleMode()
        let initialCoordinate = locationManager.latestLocation?.coordinate ?? defaultCoordinate
        self.userCoordinate = locationManager.latestLocation?.coordinate
        self.cameraPosition = .region(
            MKCoordinateRegion(
                center: initialCoordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)
            )
        )
        self.mapCenterCoordinate = initialCoordinate
        self.locationManager.setLocationUpdateHandler { [weak self] location in
            self?.handleLocationUpdate(location)
        }
    }

    func onAppear() async {
        locationManager.requestWhenInUseAuthorization()
        locationManager.requestCurrentLocation()
        refreshProfile()
        refreshLocationStatus()
        await loadStoredSessions()
        await refreshCoverage()
        await loadSharedProgress()
        updateMapRoutes()
        updateExplorationState()
        await refreshBackendMapData()
    }

    func refreshProfile() {
        currentProfile = try? profileService.currentProfile()
        refreshLocationStatus()
    }

    func refreshCoverage() async {
        refreshProfile()
        guard let profile = currentProfile else {
            persistedCoverageSideIDs = []
            updateExplorationState()
            return
        }

        let localIDs = normalizedCoverageIDs((try? coverageStore.loadCoverage(userId: profile.id, areaId: coverageAreaID)) ?? [])
        var mergedIDs = localIDs.union(discoveredBuildingSideIDs(from: storedSessions.flatMap(\.points)))

        do {
            let remoteIDs = normalizedCoverageIDs(try await backendSyncService.fetchCoverage(userId: profile.id, areaId: coverageAreaID))
            mergedIDs.formUnion(remoteIDs)
        } catch {
            // Local coverage is enough for gameplay; the next successful sync will merge again.
        }

        persistedCoverageSideIDs = mergedIDs
        try? coverageStore.saveCoverage(userId: profile.id, areaId: coverageAreaID, coveredFeatureIDs: mergedIDs)
        updateExplorationState()

        if mergedIDs != localIDs {
            await syncCoverageSnapshot(mergedIDs, for: profile)
        }
    }

    func refreshLocationStatus() {
        permissionMessage = startGuidanceMessage
    }

    func refreshLocation() {
        if let latestLocation = locationManager.latestLocation {
            handleLocationUpdate(latestLocation)
        }
        refreshLocationStatus()
    }

    func startWalk() {
        refreshProfile()
        guard currentProfile != nil else {
            permissionMessage = "Create or relink your nickname in Profile first."
            return
        }
        if isAdminMode && !locationManager.isSimulating {
            locationManager.enableSimulation(at: defaultCoordinate)
        }
        if locationPermissionDenied {
            permissionMessage = "Location access is off. Enable it in Settings, then come back and start."
            return
        }
        if locationPermissionNeedsPrompt {
            locationManager.requestWhenInUseAuthorization()
            permissionMessage = "Allow location access, then tap Start Walk again."
            return
        }
        if locationManager.authorizationStatus == .authorizedWhenInUse {
            locationManager.requestAlwaysAuthorization()
        }
        let session = WalkSession.fresh(userId: currentProfile!.id.uuidString)
        activeSession = session
        walkState = .recording
        activeCoverageSideIDs = []
        liveDistance = 0
        elapsedTime = 0
        syncStatusText = SyncStatus.localOnly.label
        lastAcceptedLocation = nil
        isFollowingUser = true
        if let latestLocation = locationManager.latestLocation {
            userCoordinate = latestLocation.coordinate
            setMapCenter(latestLocation.coordinate)
        } else {
            locationManager.requestCurrentLocation()
        }
        locationManager.startUpdates(allowsBackground: true)
        walkLiveActivityService.start(startedAt: session.startedAt, distanceMeters: liveDistance, elapsedSeconds: elapsedTime)
        startTimer()
        permissionMessage = "Walk started. Waiting for your first GPS point."
        consumeLatestLocationIfNeeded()
    }

    func togglePause() {
        switch walkState {
        case .recording:
            walkState = .paused
            locationManager.stopUpdates()
            stopTimer()
            walkLiveActivityService.update(distanceMeters: liveDistance, elapsedSeconds: elapsedTime, isPaused: true)
        case .paused:
            walkState = .recording
            locationManager.startUpdates(allowsBackground: true)
            startTimer()
            walkLiveActivityService.update(distanceMeters: liveDistance, elapsedSeconds: elapsedTime, isPaused: false)
        default:
            break
        }
    }

    func finishWalk() async {
        guard !isFinishingWalk else { return }
        guard var session = activeSession else { return }
        isFinishingWalk = true
        defer { isFinishingWalk = false }
        locationManager.stopUpdates()
        stopTimer()
        walkLiveActivityService.end(distanceMeters: liveDistance, elapsedSeconds: elapsedTime)
        session.endedAt = .now
        session.durationSeconds = elapsedTime
        session.distanceMeters = liveDistance
        session.syncStatus = .readyToSync
        do {
            try await walkSessionStore.saveSession(session)
            storedSessions.insert(session, at: 0)
            await persistCoverage(from: session)
        } catch {
            session.syncStatus = .failed
        }
        activeSession = nil
        activeCoverageSideIDs = []
        walkState = .finished(session)
        summarySession = session
        syncStatusText = session.syncStatus.label
        updateMapRoutes()
        updateExplorationState()
        await refreshBackendMapData()
    }

    func dismissSummary() {
        summarySession = nil
        walkState = .idle
        updateMapRoutes()
    }

    var filteredRoutes: [RouteOverlay] {
        mapRoutes
    }

    var activeRouteCoordinates: [CLLocationCoordinate2D] {
        activeSession?.points.map(\.coordinate) ?? []
    }

    var showsUserLocation: Bool {
        userCoordinate != nil
    }

    var locationReady: Bool {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            true
        default:
            false
        }
    }

    var permissionStatusMessage: String {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            "Location ready"
        case .denied, .restricted:
            "Location access is off. Enable it in Settings."
        case .notDetermined:
            "Allow location to draw live routes."
        @unknown default:
            "Location state unavailable."
        }
    }

    var startButtonDisabled: Bool {
        currentProfile == nil || locationPermissionDenied
    }

    var liveGPSStatus: String {
        if isAdminMode && locationManager.isSimulating {
            return "Admin simulator"
        }
        if locationManager.latestLocation == nil {
            return "Waiting for GPS"
        }
        return locationManager.statusText
    }

    var isAdminMode: Bool {
        currentProfile?.nickname.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "admin"
    }

    var mapStorageKey: String {
        currentProfile?.id.uuidString ?? "anonymous"
    }

    var summaryWalkSessionStore: WalkSessionStoring {
        walkSessionStore
    }

    func toggleMapPerspectiveMode() {
        mapPerspectiveMode = mapPerspectiveMode == .flat ? .threeD : .flat
        UserDefaults.standard.set(mapPerspectiveMode.rawValue, forKey: Self.mapPerspectiveModeDefaultsKey)
    }

    func toggleMapStyleMode() {
        mapStyleMode = mapStyleMode == .light ? .dark : .light
        UserDefaults.standard.set(mapStyleMode.rawValue, forKey: Self.mapStyleModeDefaultsKey)
    }

    func recenterOnUser() {
        isFollowingUser = true
        if let latestLocation = locationManager.latestLocation {
            userCoordinate = latestLocation.coordinate
            setMapCenter(latestLocation.coordinate)
        } else {
            locationManager.requestCurrentLocation()
        }
    }

    func userDidMoveMap() {
        isFollowingUser = false
    }

    var adminSimulationReady: Bool {
        locationManager.isSimulating || locationManager.latestLocation != nil
    }

    private var locationPermissionDenied: Bool {
        if isAdminMode {
            return false
        }
        return switch locationManager.authorizationStatus {
        case .denied, .restricted:
            true
        default:
            false
        }
    }

    private var locationPermissionNeedsPrompt: Bool {
        if isAdminMode {
            return false
        }
        return locationManager.authorizationStatus == .notDetermined
    }

    private var startGuidanceMessage: String {
        if currentProfile == nil {
            return "Create or relink your nickname in Profile first."
        }
        if isAdminMode {
            return "Admin mode: start a walk, then use the test controls to simulate movement."
        }
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            if locationManager.latestLocation == nil {
                return "Ready to start. If the route stays empty, set a Simulator location first."
            }
            return "Ready to start your walk."
        case .denied, .restricted:
            return "Location access is off. Enable it in Settings."
        case .notDetermined:
            return "Tap Start Walk and allow location access."
        @unknown default:
            return "Location state unavailable."
        }
    }

    func adminPrepareSimulation() {
        guard isAdminMode else { return }
        locationManager.enableSimulation(at: defaultCoordinate)
        refreshLocation()
    }

    func refreshForProfileChange() async {
        refreshProfile()
        await loadStoredSessions()
        await refreshCoverage()
        await refreshBackendMapData()
    }

    func adminResetSimulation() {
        guard isAdminMode else { return }
        locationManager.resetSimulation(at: defaultCoordinate)
        refreshLocation()
    }

    func adminStepNorth() {
        adminStep(latitudeDelta: 0.00012, longitudeDelta: 0)
    }

    func adminStepSouth() {
        adminStep(latitudeDelta: -0.00012, longitudeDelta: 0)
    }

    func adminStepEast() {
        adminStep(latitudeDelta: 0, longitudeDelta: 0.00018)
    }

    func adminStepWest() {
        adminStep(latitudeDelta: 0, longitudeDelta: -0.00018)
    }

    private func adminStep(latitudeDelta: Double, longitudeDelta: Double) {
        guard isAdminMode else { return }
        if !locationManager.isSimulating {
            locationManager.enableSimulation(at: defaultCoordinate)
        }
        locationManager.stepSimulation(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
    }

    private func handleLocationUpdate(_ location: CLLocation) {
        userCoordinate = location.coordinate
        if isFollowingUser {
            setMapCenter(location.coordinate)
        }
        refreshLocationStatus()
        let consumedLocation = consumeLatestLocationIfNeeded(location)
        if !consumedLocation {
            updateExplorationState()
            refreshMapData()
        }
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.elapsedTime = Date().timeIntervalSince(self.activeSession?.startedAt ?? .now)
                self.walkLiveActivityService.update(
                    distanceMeters: self.liveDistance,
                    elapsedSeconds: self.elapsedTime,
                    isPaused: false
                )
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private static func loadPersistedMapPerspectiveMode() -> MapPerspectiveMode {
        guard
            let stored = UserDefaults.standard.string(forKey: mapPerspectiveModeDefaultsKey),
            let mode = MapPerspectiveMode(rawValue: stored)
        else {
            return .flat
        }
        return mode
    }

    private static func loadPersistedMapStyleMode() -> MapStyleMode {
        guard
            let stored = UserDefaults.standard.string(forKey: mapStyleModeDefaultsKey),
            let mode = MapStyleMode(rawValue: stored)
        else {
            return .light
        }
        return mode
    }

    private func loadStoredSessions() async {
        do {
            let profileID = currentProfile?.id.uuidString
            storedSessions = try await walkSessionStore.loadSessions()
                .filter { session in
                    guard let profileID else { return false }
                    return session.userId == profileID
                }
                .sorted(by: { $0.startedAt > $1.startedAt })
        } catch {
            storedSessions = []
        }
    }

    private func loadSharedProgress() async {
        do {
            sharedProgress = try await backendSyncService.fetchSharedProgress()
        } catch {
            updateExplorationState()
        }
    }

    private func updateMapRoutes() {
        let storedRoutes = storedSessions.map { session in
            RouteOverlay(
                id: session.id,
                owner: .me,
                title: session.startedAt.formatted(date: .abbreviated, time: .omitted),
                coordinates: session.points.map(\.coordinate),
                style: .completed
            )
        }
        mapRoutes = storedRoutes + mockRouteProvider.routes()
    }

    @discardableResult
    private func consumeLatestLocationIfNeeded(_ location: CLLocation? = nil) -> Bool {
        guard walkState == .recording, var session = activeSession else { return false }
        guard let location = location ?? locationManager.latestLocation else { return false }
        guard shouldAccept(location: location) else { return false }

        let trackPoint = TrackPoint.from(location: location)
        session.points.append(trackPoint)
        if let previousLocation = lastAcceptedLocation {
            liveDistance += location.distance(from: previousLocation)
        }
        elapsedTime = Date().timeIntervalSince(session.startedAt)
        lastAcceptedLocation = location
        syncStatusText = SyncStatus.localOnly.label
        activeSession = session
        walkLiveActivityService.update(distanceMeters: liveDistance, elapsedSeconds: elapsedTime, isPaused: false)
        updateExplorationState()
        refreshMapData()
        return true
    }

    private func shouldAccept(location: CLLocation) -> Bool {
        if location.horizontalAccuracy < 0 || location.horizontalAccuracy > LocationManager.maxAcceptedHorizontalAccuracy {
            return false
        }
        if let lastAcceptedLocation {
            let movedDistance = location.distance(from: lastAcceptedLocation)
            if movedDistance < LocationManager.minimumMovementDistance {
                return false
            }
        }
        return true
    }

    private func updateExplorationState() {
        let localExploredIDs = discoveredBuildingSideIDs(from: storedSessions.flatMap(\.points))
        let exploredIDs = normalizedCoverageIDs(persistedCoverageSideIDs).union(localExploredIDs)
        let activeIDs = activeCoverageSideIDs.isEmpty
            ? discoveredBuildingSideIDs(from: activeSession?.points ?? [])
            : activeCoverageSideIDs
        let newActiveIDs = activeIDs.subtracting(exploredIDs)
        let activeBuildingIDs = CoverageBuildingCodec.buildingIDs(from: newActiveIDs)
        let discoveredBuildingCount = buildingIDs(from: exploredIDs.union(newActiveIDs)).count
        exploredBuildingAreas = CoverageBuildingCodec.areas(from: exploredIDs).filter { !activeBuildingIDs.contains($0.id) }
        activeBuildingAreas = CoverageBuildingCodec.areas(from: exploredIDs.union(newActiveIDs)).filter {
            activeBuildingIDs.contains($0.id)
        }

        sharedProgress = SharedProgress(
            totalDistanceMeters: storedSessions.reduce(0) { $0 + $1.distanceMeters } + liveDistance,
            totalWalks: storedSessions.count + (activeSession == nil ? 0 : 1),
            completedRoutesPlaceholder: discoveredBuildingCount,
            explorationProgressPercentPlaceholder: 0
        )
    }

    private func refreshBackendCoverageCandidates() async {
        guard let points = activeSession?.points, points.count > 1 else {
            activeCoverageSideIDs = []
            return
        }
        do {
            activeCoverageSideIDs = try await backendSyncService.fetchMapCoverageCandidates(points: points)
            updateExplorationState()
        } catch {
            activeCoverageSideIDs = []
        }
    }

    private func refreshBackendMapData() async {
        refreshMapData()
    }

    private func refreshMapData() {
        let center = locationManager.latestLocation?.coordinate
            ?? activeSession?.points.last?.coordinate
            ?? storedSessions.first?.points.last?.coordinate
            ?? defaultCoordinate
        userCoordinate = locationManager.latestLocation?.coordinate
        if isFollowingUser || userCoordinate == nil {
            setMapCenter(center)
        }
        activeRouteGeoJSON = routeFeatureCollection(
            storedSessions: storedSessions,
            activePoints: activeSession?.points ?? []
        )
        mapFeatureGeoJSON = #"{"type":"FeatureCollection","features":[]}"#
    }

    private func persistCoverage(from session: WalkSession) async {
        guard let profile = currentProfile else { return }
        let sessionIDs = activeCoverageSideIDs.isEmpty
            ? discoveredBuildingSideIDs(from: session.points)
            : activeCoverageSideIDs
        guard !sessionIDs.isEmpty else { return }

        var mergedIDs = persistedCoverageSideIDs
        mergedIDs.formUnion(sessionIDs)
        mergedIDs.formUnion(discoveredBuildingSideIDs(from: storedSessions.flatMap(\.points)))
        persistedCoverageSideIDs = mergedIDs
        try? coverageStore.saveCoverage(userId: profile.id, areaId: coverageAreaID, coveredFeatureIDs: mergedIDs)
        updateExplorationState()
        await syncCoverageSnapshot(mergedIDs, for: profile)
    }

    private func syncCoverageSnapshot(_ coveredFeatureIDs: Set<String>, for profile: UserProfile) async {
        do {
            let remoteIDs = try await backendSyncService.upsertCoverage(
                userId: profile.id,
                areaId: coverageAreaID,
                coveredFeatureIDs: coveredFeatureIDs
            )
            let mergedIDs = normalizedCoverageIDs(coveredFeatureIDs).union(normalizedCoverageIDs(remoteIDs))
            persistedCoverageSideIDs = mergedIDs
            try? coverageStore.saveCoverage(userId: profile.id, areaId: coverageAreaID, coveredFeatureIDs: mergedIDs)
            updateExplorationState()
        } catch {
            // Coverage remains saved locally and will be retried when the map/profile reloads.
        }
    }

    private func discoveredBuildingSideIDs(from points: [TrackPoint]) -> Set<String> {
        CoverageBuildingCodec.sideIDs(from: points)
    }

    private func normalizedCoverageIDs(_ ids: Set<String>) -> Set<String> {
        Set(ids.filter { CoverageBuildingCodec.decode($0) != nil || $0.contains(":side:") })
    }

    private func routeFeatureCollection(storedSessions: [WalkSession], activePoints: [TrackPoint]) -> String {
        var features = storedSessions.compactMap { session in
            routeFeature(from: session.points, status: "explored")
        }
        if let activeFeature = routeFeature(from: activePoints, status: "active") {
            features.append(activeFeature)
        }
        return jsonString([
            "type": "FeatureCollection",
            "features": features
        ])
    }

    private func routeFeature(from points: [TrackPoint], status: String) -> [String: Any]? {
        guard points.count > 1 else { return nil }
        let coordinates = status == "active"
            ? interpolatedRouteCoordinates(from: points)
            : points.map(\.coordinate)
        return [
            "type": "Feature",
            "properties": [
                "status": status
            ],
            "geometry": [
                "type": "LineString",
                "coordinates": coordinates.map { [$0.longitude, $0.latitude] }
            ]
        ]
    }

    private func interpolatedRouteCoordinates(from points: [TrackPoint]) -> [CLLocationCoordinate2D] {
        guard let first = points.first?.coordinate else { return [] }
        var coordinates = [first]
        for pair in zip(points, points.dropFirst()) {
            let start = pair.0.coordinate
            let end = pair.1.coordinate
            let distance = pair.0.location.distance(from: pair.1.location)
            let stepCount = max(1, Int(ceil(distance / liveRouteInterpolationStepMeters)))
            for step in 1...stepCount {
                let progress = Double(step) / Double(stepCount)
                coordinates.append(
                    CLLocationCoordinate2D(
                        latitude: start.latitude + ((end.latitude - start.latitude) * progress),
                        longitude: start.longitude + ((end.longitude - start.longitude) * progress)
                    )
                )
                if coordinates.count >= maxLiveRouteVisualCoordinates {
                    return coordinates
                }
            }
        }
        return coordinates
    }

    private func localFeatureCollection() -> String {
        let explored = exploredBuildingAreas.map { featureDictionary(for: $0, status: "explored") }
        let active = activeBuildingAreas.map { featureDictionary(for: $0, status: "active") }
        return jsonString([
            "type": "FeatureCollection",
            "features": explored + active
        ])
    }

    private func featureDictionary(for area: CoverageBuildingArea, status: String) -> [String: Any] {
        let ring = (area.coordinates + [area.coordinates.first].compactMap { $0 }).map { coordinate in
            [coordinate.longitude, coordinate.latitude]
        }
        return [
            "type": "Feature",
            "id": area.id,
            "properties": [
                "id": area.id,
                "status": status,
                "isFullyCovered": area.isFullyCovered
            ],
            "geometry": [
                "type": "Polygon",
                "coordinates": [ring]
            ]
        ]
    }

    private func buildingIDs(from sideIDs: Set<String>) -> Set<String> {
        let backendIDs = sideIDs.compactMap { sideID -> String? in
            guard let range = sideID.range(of: ":side:") else { return nil }
            return String(sideID[..<range.lowerBound])
        }
        return CoverageBuildingCodec.buildingIDs(from: sideIDs).union(backendIDs)
    }

    private func jsonString(_ object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object),
              let string = String(data: data, encoding: .utf8) else {
            return #"{"type":"FeatureCollection","features":[]}"#
        }
        return string
    }

    private var explorationBoardRegion: MKCoordinateRegion {
        if let firstCoordinate = storedSessions
            .flatMap(\.points)
            .first?.coordinate {
            return region(centeredAt: firstCoordinate)
        }
        if let activeCoordinate = activeSession?.points.first?.coordinate {
            return region(centeredAt: activeCoordinate)
        }
        if let latestCoordinate = locationManager.latestLocation?.coordinate {
            return region(centeredAt: latestCoordinate)
        }
        return region(centeredAt: defaultCoordinate)
    }

    private func region(centeredAt coordinate: CLLocationCoordinate2D) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: boardLatSpan, longitudeDelta: boardLonSpan)
        )
    }

    private func setMapCenter(_ coordinate: CLLocationCoordinate2D) {
        mapCenterCoordinate = coordinate
        cameraPosition = .region(
            MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
            )
        )
    }
}
