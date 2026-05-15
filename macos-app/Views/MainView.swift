import SwiftUI

// MARK: - Main View

struct MainView: View {
    @EnvironmentObject private var auth: AuthManager

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.green)

                Text("登录成功")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.primary)

                if let user = auth.currentUser {
                    Text("欢迎, \(user.name)")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }

                if let workspace = auth.currentWorkspace {
                    Text("工作空间: \(workspace.name)")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 60)

            VStack(spacing: 16) {
                Button("查看用户信息") {
                    // TODO: Navigate to user profile
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("退出登录") {
                    Task { @MainActor in
                        try? await auth.logout()
                    }
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 40)

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}