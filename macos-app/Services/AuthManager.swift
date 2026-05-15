import Foundation
import SwiftUI

// MARK: - Authentication Manager

@MainActor
class AuthManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var token: String?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let apiClient: APIClient
    private let keychain = KeychainHelper.shared

    var currentWorkspace: Workspace?

    init(baseURL: URL = URL(string: "https://api.multica.io")!) {
        self.apiClient = APIClient(baseURL: baseURL)
        loadTokenFromKeychain()
    }

    // MARK: - Token Management

    private func loadTokenFromKeychain() {
        if let savedToken = keychain.loadToken() {
            token = savedToken
            apiClient.setToken(savedToken)
            isAuthenticated = true
        }
    }

    private func saveTokenToKeychain(_ token: String) {
        try? keychain.saveToken(token)
    }

    private func deleteTokenFromKeychain() {
        try? keychain.deleteToken()
    }

    // MARK: - Authentication

    func login(email: String) async throws {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await apiClient.sendCode(email: email)
        } catch let error as APIError {
            errorMessage = error.errorDescription
            throw error
        }
    }

    func verify(email: String, code: String) async throws {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await apiClient.verifyCode(email: email, code: code)

            token = response.token
            currentUser = response.user
            isAuthenticated = true

            apiClient.setToken(response.token)
            saveTokenToKeychain(response.token)

        } catch let error as APIError {
            errorMessage = error.errorDescription
            throw error
        }
    }

    func logout() async throws {
        isLoading = true
        errorMessage = nil
        defer {
            isLoading = false
            token = nil
            currentUser = nil
            isAuthenticated = false
            currentWorkspace = nil
            apiClient.setToken(nil)
            deleteTokenFromKeychain()
        }

        do {
            try await apiClient.logout()
        } catch let error as APIError {
            errorMessage = error.errorDescription
            throw error
        }
    }

    // MARK: - Workspace Management

    func loadWorkspaces() async throws -> [Workspace] {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            return try await apiClient.listWorkspaces()
        } catch let error as APIError {
            errorMessage = error.errorDescription
            throw error
        }
    }

    func selectWorkspace(_ workspace: Workspace) {
        currentWorkspace = workspace
    }

    // MARK: - API Client Access

    func getAPIClient() -> APIClient {
        return apiClient
    }
}