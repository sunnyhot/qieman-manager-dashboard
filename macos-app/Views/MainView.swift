import SwiftUI

// MARK: - App Section

enum MulticaAppSection: String, CaseIterable, Identifiable {
    case issues = "Issues"
    case members = "成员"
    case settings = "设置"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .issues: return "list.bullet.circle"
        case .members: return "person.2"
        case .settings: return "gearshape"
        }
    }
}

// MARK: - Main View

struct MainView: View {
    @EnvironmentObject private var auth: AuthManager
    @State private var selectedSection: MulticaAppSection = .issues

    var body: some View {
        NavigationSplitView {
            List(MulticaAppSection.allCases, selection: $selectedSection) { section in
                Label(section.rawValue, systemImage: section.systemImage)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)

            VStack(alignment: .leading, spacing: 8) {
                Divider()
                HStack(spacing: 8) {
                    AssigneeAvatar(
                        name: auth.currentUser?.name,
                        size: 24
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(auth.currentUser?.name ?? "User")
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        if let workspace = auth.currentWorkspace {
                            Text(workspace.name)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    Button {
                        Task { @MainActor in
                            try? await auth.logout()
                        }
                    } label: {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("退出登录")
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        } detail: {
            detailContent
        }
        .frame(minWidth: 800, minHeight: 600)
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selectedSection {
        case .issues:
            IssuesSectionView()
        case .members:
            Text("成员管理")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .settings:
            Text("设置")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
