import SwiftUI

struct IssuesSectionView: View {
    @EnvironmentObject private var auth: AuthManager
    @State private var issues: [Issue] = []
    @State private var totalCount = 0
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var selectedStatus: IssueStatus?
    @State private var selectedIssueId: String?
    @State private var isShowingCreate = false
    @State private var offset = 0

    var body: some View {
        NavigationSplitView {
            issueListPanel
        } detail: {
            if let issueId = selectedIssueId {
                IssueDetailView(issueId: issueId)
            } else {
                emptyDetail
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .searchable(text: $searchText, prompt: "搜索 Issue...")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isShowingCreate = true
                } label: {
                    Label("新建 Issue", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await loadIssues() }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
        }
        .sheet(isPresented: $isShowingCreate) {
            CreateIssueView(isPresented: $isShowingCreate) {
                Task { await loadIssues() }
            }
        }
        .task {
            await loadIssues()
        }
    }

    // MARK: - Issue List Panel

    private var issueListPanel: some View {
        VStack(spacing: 0) {
            statusFilterBar

            if isLoading && issues.isEmpty {
                Spacer()
                ProgressView("加载中...")
                Spacer()
            } else if issues.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("暂无 Issue")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                List(filteredIssues, selection: $selectedIssueId) { issue in
                    IssueRow(issue: issue)
                        .tag(issue.id)
                        .onAppear {
                            if issue.id == filteredIssues.last?.id {
                                Task { await loadMoreIfNeeded() }
                            }
                        }
                }
                .listStyle(.sidebar)
            }
        }
        .navigationTitle("Issues (\(totalCount))")
    }

    private var statusFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                FilterChip(
                    label: "All",
                    isSelected: selectedStatus == nil
                ) {
                    selectedStatus = nil
                    Task { await loadIssues() }
                }

                ForEach(IssueStatus.allCases, id: \.self) { status in
                    FilterChip(
                        label: status.displayName,
                        isSelected: selectedStatus == status
                    ) {
                        selectedStatus = status
                        Task { await loadIssues() }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private var emptyDetail: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("选择一个 Issue 查看详情")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data

    private var filteredIssues: [Issue] {
        if searchText.isEmpty {
            return issues
        }
        return issues.filter { issue in
            issue.title.localizedCaseInsensitiveContains(searchText) ||
            (issue.identifier ?? "").localizedCaseInsensitiveContains(searchText) ||
            (issue.description ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    private func loadIssues() async {
        isLoading = true
        errorMessage = nil
        offset = 0

        do {
            guard let client = authClient() else { return }
            let statusFilter: [IssueStatus]? = selectedStatus.map { [$0] }
            let result = try await client.listIssues(status: statusFilter, limit: 50, offset: 0)
            issues = result.issues
            totalCount = result.total
            offset = result.issues.count
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func loadMoreIfNeeded() async {
        guard offset < totalCount else { return }
        do {
            guard let client = authClient() else { return }
            let statusFilter: [IssueStatus]? = selectedStatus.map { [$0] }
            let result = try await client.listIssues(status: statusFilter, limit: 50, offset: offset)
            issues.append(contentsOf: result.issues)
            offset += result.issues.count
        } catch {
            // silently ignore pagination errors
        }
    }

    private func authClient() -> APIClient? {
        guard let workspace = auth.currentWorkspace else { return nil }
        let client = auth.getAPIClient()
        return client
    }
}

// MARK: - Issue Row

private struct IssueRow: View {
    let issue: Issue

    var body: some View {
        HStack(spacing: 10) {
            PriorityBadge(priority: issue.priority)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if let identifier = issue.identifier {
                        Text(identifier)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Text(issue.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    StatusBadge(status: issue.status)

                    if let labels = issue.labels, !labels.isEmpty {
                        ForEach(labels.prefix(3)) { label in
                            LabelChip(label: label)
                        }
                    }
                }
            }

            Spacer()

            AssigneeAvatar(name: nil, size: 22)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Filter Chip

private struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? Color.accentColor : Color(nsColor: .controlBackgroundColor), in: Capsule())
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}
