import SwiftUI

struct ProfileView: View {
    @ObservedObject var viewModel: ProfileViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section("Nickname") {
                    TextField("Nickname", text: $viewModel.nickname)
                        .autocorrectionDisabled()
#if os(iOS)
                        .textInputAutocapitalization(.never)
#endif
                    Button(viewModel.profile == nil ? "Create Profile" : "Save / Relink") {
                        Task { await viewModel.saveNickname() }
                    }
                    .disabled(viewModel.nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isSaving)
                }

                if let profile = viewModel.profile {
                    Section("Profile") {
                        infoRow(title: "Nickname", value: profile.nickname)
                        infoRow(title: "User ID", value: profile.id.uuidString)
                        infoRow(title: "Device ID", value: profile.deviceId.uuidString)
                    }
                }

                Section("Server") {
                    TextField("Base URL", text: $viewModel.serverBaseURLText)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Save Server URL") {
                        viewModel.saveServerBaseURL()
                    }
                    .disabled(!viewModel.canSaveServerURL)
                    Text("Nickname is a lightweight POC identity only. Real authentication comes later.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage = viewModel.errorMessage {
                    Section("Status") {
                        Text(errorMessage)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Profile")
        }
    }

    private func infoRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
                .textSelection(.enabled)
        }
    }
}
