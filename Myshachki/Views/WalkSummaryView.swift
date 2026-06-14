import MapKit
import SwiftUI

struct WalkSummaryContainerView: View {
    @StateObject private var viewModel: WalkSummaryViewModel
    let dismissAction: () -> Void

    init(
        session: WalkSession,
        backendSyncService: BackendSyncServing,
        walkSessionStore: WalkSessionStoring,
        dismissAction: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: WalkSummaryViewModel(
            session: session,
            backendSyncService: backendSyncService,
            walkSessionStore: walkSessionStore
        ))
        self.dismissAction = dismissAction
    }

    var body: some View {
        WalkSummaryView(viewModel: viewModel, dismissAction: dismissAction)
    }
}

struct WalkSummaryView: View {
    @ObservedObject var viewModel: WalkSummaryViewModel
    let dismissAction: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Great walk!")
                        .font(.largeTitle.weight(.bold))

                    if !viewModel.session.points.isEmpty {
                        MapLibreMapView(
                            center: viewModel.mapCenterCoordinate,
                            buildingGeoJSON: #"{"type":"FeatureCollection","features":[]}"#,
                            routeGeoJSON: viewModel.routeGeoJSON,
                            storageKey: viewModel.mapStorageKey,
                            showsUserLocation: false,
                            fitsRouteBounds: true
                        )
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    }

                    HStack(spacing: 12) {
                        SummaryStatCard(title: "Distance", value: viewModel.session.distanceMeters.formattedDistance)
                        SummaryStatCard(title: "Duration", value: viewModel.session.durationSeconds.formattedClock)
                    }
                    HStack(spacing: 12) {
                        SummaryStatCard(title: "Track Points", value: "\(viewModel.session.points.count)")
                        SummaryStatCard(title: "Sync", value: viewModel.syncStatusText)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("New Buildings")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(viewModel.newStreetsText)
                            .font(.headline)
                        Text("New Area")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(viewModel.newAreaText)
                            .font(.headline)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                    PrimaryButton(
                        title: viewModel.isSavingToServer ? "Saving..." : "Save to Shared Map",
                        icon: "icloud.and.arrow.up",
                        isDisabled: !viewModel.canSyncToServer
                    ) {
                        Task { await viewModel.syncToServer() }
                    }

                    PrimaryButton(title: "View Full Map", icon: "map.fill", prominent: false) {
                        dismiss()
                        dismissAction()
                    }
                }
                .padding(20)
            }
            .background(
                LinearGradient(
                    colors: [Color.blue.opacity(0.14), Color.teal.opacity(0.12), Color.white],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
