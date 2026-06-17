import SwiftUI

struct MapScreen: View {
    @ObservedObject var viewModel: MapViewModel
    let backendSyncService: BackendSyncServing

    var body: some View {
        ZStack(alignment: .top) {
            MapLibreMapView(
                center: viewModel.mapCenterCoordinate,
                buildingGeoJSON: viewModel.mapFeatureGeoJSON,
                routeGeoJSON: viewModel.activeRouteGeoJSON,
                storageKey: viewModel.mapStorageKey,
                userCoordinate: viewModel.userCoordinate,
                perspectiveMode: viewModel.mapPerspectiveMode,
                styleMode: viewModel.mapStyleMode,
                showsUserLocation: viewModel.showsUserLocation,
                smoothUserLocation: !viewModel.isAdminMode,
                onCurrentCoverageChange: { viewModel.currentCoverageDidChange($0) },
                onUserInteraction: { viewModel.userDidMoveMap() }
            )
            .ignoresSafeArea()

            VStack(spacing: 14) {
                HStack {
                    Spacer()
                    Button {
                        viewModel.toggleMapPerspectiveMode()
                    } label: {
                        Label(viewModel.mapPerspectiveMode.buttonTitle, systemImage: viewModel.mapPerspectiveMode.buttonSystemImage)
                            .font(.caption.weight(.semibold))
                            .labelStyle(.iconOnly)
                            .frame(width: 34, height: 34)
                            .background(.thinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(viewModel.mapPerspectiveMode.buttonTitle)

                    Button {
                        viewModel.toggleMapStyleMode()
                    } label: {
                        Label(viewModel.mapStyleMode.buttonTitle, systemImage: viewModel.mapStyleMode.buttonSystemImage)
                            .font(.caption.weight(.semibold))
                            .labelStyle(.iconOnly)
                            .frame(width: 34, height: 34)
                            .background(.thinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(viewModel.mapStyleMode.buttonTitle)
                }
            }
            .padding(.horizontal, 16)

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    recenterButton
                }
                .padding(.trailing, 16)
                .padding(.bottom, recenterBottomPadding)
            }

            VStack {
                Spacer()
                VStack(spacing: 14) {
                    if case .recording = viewModel.walkState {
                        LiveWalkCard(
                            elapsedTime: viewModel.elapsedTime,
                            distance: viewModel.liveDistance,
                            gpsStatus: viewModel.liveGPSStatus,
                            syncStatus: viewModel.syncStatusText,
                            isPaused: false,
                            isFinishing: viewModel.isFinishingWalk,
                            pauseAction: { viewModel.togglePause() },
                            finishAction: { Task { await viewModel.finishWalk() } }
                        )
                        if viewModel.isAdminMode {
                            AdminTestingCard(
                                canReset: viewModel.adminSimulationReady,
                                prepareAction: { viewModel.adminPrepareSimulation() },
                                resetAction: { viewModel.adminResetSimulation() },
                                northAction: { viewModel.adminStepNorth() },
                                southAction: { viewModel.adminStepSouth() },
                                eastAction: { viewModel.adminStepEast() },
                                westAction: { viewModel.adminStepWest() }
                            )
                        }
                    } else if case .paused = viewModel.walkState {
                        LiveWalkCard(
                            elapsedTime: viewModel.elapsedTime,
                            distance: viewModel.liveDistance,
                            gpsStatus: "Paused",
                            syncStatus: viewModel.syncStatusText,
                            isPaused: true,
                            isFinishing: viewModel.isFinishingWalk,
                            pauseAction: { viewModel.togglePause() },
                            finishAction: { Task { await viewModel.finishWalk() } }
                        )
                        if viewModel.isAdminMode {
                            AdminTestingCard(
                                canReset: viewModel.adminSimulationReady,
                                prepareAction: { viewModel.adminPrepareSimulation() },
                                resetAction: { viewModel.adminResetSimulation() },
                                northAction: { viewModel.adminStepNorth() },
                                southAction: { viewModel.adminStepSouth() },
                                eastAction: { viewModel.adminStepEast() },
                                westAction: { viewModel.adminStepWest() }
                            )
                        }
                    } else {
                        ProgressCard(progress: viewModel.sharedProgress)
                        PrimaryButton(title: "Start Walk", icon: "play.fill", isDisabled: viewModel.startButtonDisabled) {
                            viewModel.startWalk()
                        }
                        if viewModel.isAdminMode {
                            AdminTestingCard(
                                canReset: viewModel.adminSimulationReady,
                                prepareAction: { viewModel.adminPrepareSimulation() },
                                resetAction: { viewModel.adminResetSimulation() },
                                northAction: { viewModel.adminStepNorth() },
                                southAction: { viewModel.adminStepSouth() },
                                eastAction: { viewModel.adminStepEast() },
                                westAction: { viewModel.adminStepWest() }
                            )
                        }
                    }

                    Text(viewModel.permissionMessage)
                        .font(.footnote)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 22)
            }
        }
        .sheet(item: $viewModel.summarySession) { session in
            WalkSummaryContainerView(
                session: session,
                backendSyncService: backendSyncService,
                mapPerspectiveMode: viewModel.mapPerspectiveMode,
                mapStyleMode: viewModel.mapStyleMode,
                summaryCoverageGeoJSON: viewModel.summaryCoverageGeoJSON,
                dismissAction: { viewModel.dismissSummary() }
            )
        }
    }

    private var recenterButton: some View {
        Button {
            viewModel.recenterOnUser()
        } label: {
            Label("Recenter", systemImage: viewModel.isFollowingUser ? "location.fill" : "location")
                .font(.body.weight(.semibold))
                .labelStyle(.iconOnly)
                .frame(width: 46, height: 46)
                .background(.thinMaterial, in: Circle())
                .shadow(color: .black.opacity(0.16), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Recenter on me")
    }

    private var recenterBottomPadding: CGFloat {
        switch viewModel.walkState {
        case .recording, .paused:
            viewModel.isAdminMode ? 330 : 230
        default:
            viewModel.isAdminMode ? 370 : 230
        }
    }
}
