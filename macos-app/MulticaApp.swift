import SwiftUI

// MARK: - Multica Auth Router
// Routes between LoginView, WorkspaceSelectionView, and MainView
// based on authentication state. Integrate into the app's view hierarchy
// by injecting an AuthManager as an @EnvironmentObject.

struct MulticaAuthView: View {
    @EnvironmentObject private var auth: AuthManager

    var body: some View {
        Group {
            if !auth.isAuthenticated {
                LoginView()
            } else if auth.currentWorkspace == nil {
                WorkspaceSelectionView()
            } else {
                MainView()
            }
        }
        .frame(minWidth: 800, minHeight: 600)
    }
}