import SwiftUI

// MARK: - Workspace Selection View

struct WorkspaceSelectionView: View {
    @EnvironmentObject private var auth: AuthManager
    @State private var workspaces: [Workspace] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 32) {
            VStack(spacing: 16) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.blue)

                Text("选择工作空间")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.primary)

                Text("请选择要使用的工作空间")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }

            if isLoading {
                ProgressView()
                    .scaleEffect(1.2)
                    .padding(.top, 40)
            } else if workspaces.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundStyle(.orange)

                    Text(errorMessage ?? "未找到可用的工作空间")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)

                    Button("重新加载") {
                        loadWorkspaces()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.top, 40)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(workspaces) { workspace in
                            WorkspaceCard(workspace: workspace) {
                                selectWorkspace(workspace)
                            }
                        }
                    }
                    .padding(.horizontal, 40)
                }
                .frame(maxHeight: 300)

                Button("退出登录") {
                    logout()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.top, 20)
            }
        }
        .padding(40)
        .frame(width: 480, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            loadWorkspaces()
        }
    }

    // MARK: - Actions

    private func loadWorkspaces() {
        isLoading = true
        errorMessage = nil

        Task { @MainActor in
            do {
                let loadedWorkspaces = try await auth.loadWorkspaces()
                workspaces = loadedWorkspaces

                if workspaces.count == 1 {
                    selectWorkspace(workspaces[0])
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func selectWorkspace(_ workspace: Workspace) {
        auth.selectWorkspace(workspace)
    }

    private func logout() {
        Task { @MainActor in
            try? await auth.logout()
        }
    }
}

// MARK: - Workspace Card

struct WorkspaceCard: View {
    let workspace: Workspace
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 32))
                    .foregroundStyle(.blue)
                    .frame(width: 50, height: 50)

                VStack(alignment: .leading, spacing: 4) {
                    Text(workspace.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(workspace.slug)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}