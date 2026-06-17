import SwiftUI

struct ActivityView: View {
    @ObservedObject var viewModel: ActivityViewModel
    let backendSyncService: BackendSyncServing
    let mapPerspectiveMode: MapPerspectiveMode
    let mapStyleMode: MapStyleMode

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.sessions.isEmpty {
                    ContentUnavailableView("No walks yet", systemImage: "figure.walk", description: Text("Finish your first walk and it will appear here."))
                } else {
                    List(viewModel.sessions) { session in
                        NavigationLink {
                            WalkSummaryContainerView(
                                session: session,
                                backendSyncService: backendSyncService,
                                mapPerspectiveMode: mapPerspectiveMode,
                                mapStyleMode: mapStyleMode,
                                dismissAction: {}
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.headline)
                                HStack {
                                    Label(session.distanceMeters.formattedDistance, systemImage: "ruler")
                                    Label(session.durationSeconds.formattedClock, systemImage: "timer")
                                }
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                Text(session.syncStatus.label)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 6)
                        }
                    }
                    .listStyle(.automatic)
                }
            }
            .navigationTitle("Activity")
            .toolbar {
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let statusText = viewModel.statusText {
                    Text(statusText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.thinMaterial)
                }
            }
        }
        .task {
            await viewModel.refresh()
        }
    }
}
