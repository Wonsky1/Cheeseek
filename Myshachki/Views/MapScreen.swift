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
                perspectiveMode: viewModel.mapPerspectiveMode,
                styleMode: viewModel.mapStyleMode
            )
            .ignoresSafeArea()

            VStack(spacing: 14) {
                HStack {
                    MapOverlayLegend()
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
            WalkSummaryView(
                viewModel: WalkSummaryViewModel(
                    session: session,
                    backendSyncService: backendSyncService,
                    walkSessionStore: viewModel.summaryWalkSessionStore
                ),
                dismissAction: { viewModel.dismissSummary() }
            )
        }
    }
}
