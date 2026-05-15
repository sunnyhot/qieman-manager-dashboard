import SwiftUI

struct IssueDetailView: View {
    let issueId: String
    @EnvironmentObject private var auth: AuthManager
    @State private var issue: Issue?
    @State private var comments: [Comment] = []
    @State private var isLoading = true
    @State private var isEditingTitle = false
    @State private var editedTitle = ""
    @State private var selectedStatus: IssueStatus?
    @State private var selectedPriority: IssuePriority?
    @State private var isUpdating = false

    var body: some View {
        if isLoading {
            ProgressView("加载中...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let issue {
            issueContent(issue: issue)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("无法加载 Issue")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                Button("重试") {
                    Task { await loadIssue() }
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func issueContent(issue: Issue) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                headerSection(issue: issue)

                Divider()

                // Labels
                if let labels = issue.labels, !labels.isEmpty {
                    labelsSection(labels: labels)
                    Divider()
                }

                // Description
                descriptionSection(issue: issue)

                Divider()

                // Metadata
                metadataSection(issue: issue)

                Divider()

                // Comments
                commentsSection(issueId: issue.id)
            }
            .padding(24)
        }
        .navigationTitle(issue.identifier ?? issue.id.prefix(8).uppercased())
    }

    // MARK: - Header

    private func headerSection(issue: Issue) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if isEditingTitle {
                HStack(spacing: 8) {
                    TextField("标题", text: $editedTitle)
                        .textFieldStyle(.plain)
                        .font(.system(size: 22, weight: .bold))
                    Button("保存") {
                        Task { await saveTitle() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    Button("取消") {
                        isEditingTitle = false
                    }
                    .controlSize(.small)
                }
            } else {
                HStack(spacing: 8) {
                    Text(issue.title)
                        .font(.system(size: 22, weight: .bold))
                        .textSelection(.enabled)
                    Button {
                        editedTitle = issue.title
                        isEditingTitle = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                StatusBadge(status: issue.status)
                PriorityBadge(priority: issue.priority)
                if let identifier = issue.identifier {
                    Text(identifier)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Labels

    private func labelsSection(labels: [IssueLabel]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("标签")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(labels) { label in
                    LabelChip(label: label)
                }
            }
        }
    }

    // MARK: - Description

    private func descriptionSection(issue: Issue) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("描述")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            if let description = issue.description, !description.isEmpty {
                MarkdownView(text: description)
            } else {
                Text("无描述")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Metadata

    private func metadataSection(issue: Issue) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("详情")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 32) {
                VStack(alignment: .leading, spacing: 6) {
                    metadataRow(label: "状态", value: issue.status.displayName) {
                        StatusPicker(current: issue.status) { newStatus in
                            Task { await updateStatus(newStatus) }
                        }
                    }
                    metadataRow(label: "优先级", value: issue.priority.displayName) {
                        PriorityPicker(current: issue.priority) { newPriority in
                            Task { await updatePriority(newPriority) }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    let createdAt = String(issue.createdAt.prefix(10))
                    Label(createdAt, systemImage: "calendar")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    let updatedAt = String(issue.updatedAt.prefix(10))
                    Label("更新于 \(updatedAt)", systemImage: "clock")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func metadataRow(label: String, value: String, picker: () -> some View) -> some View {
        HStack(spacing: 6) {
            Text(label + ":")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            picker()
        }
    }

    // MARK: - Comments

    private func commentsSection(issueId: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("评论 (\(comments.count))")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            ForEach(comments) { comment in
                CommentCard(comment: comment, authorName: nil)
            }

            CommentInput { content in
                Task { await postComment(content: content) }
            }
        }
    }

    // MARK: - Actions

    private func loadIssue() async {
        isLoading = true
        do {
            guard let client = authClient() else { return }
            async let issueLoad: Issue = client.getIssue(id: issueId)
            async let commentsLoad: [Comment] = client.listComments(issueId: issueId)
            let (loadedIssue, loadedComments) = try await (issueLoad, commentsLoad)
            self.issue = loadedIssue
            self.comments = loadedComments
        } catch {
            // error handled by nil issue check
        }
        isLoading = false
    }

    private func saveTitle() async {
        guard let client = authClient(), !editedTitle.isEmpty else { return }
        isUpdating = true
        do {
            let updated = try await client.updateIssue(id: issueId, title: editedTitle)
            self.issue = updated
            isEditingTitle = false
        } catch {
            // silently fail
        }
        isUpdating = false
    }

    private func updateStatus(_ status: IssueStatus) async {
        guard let client = authClient() else { return }
        isUpdating = true
        do {
            let updated = try await client.updateIssue(id: issueId, status: status)
            self.issue = updated
        } catch {
            // silently fail
        }
        isUpdating = false
    }

    private func updatePriority(_ priority: IssuePriority) async {
        guard let client = authClient() else { return }
        isUpdating = true
        do {
            let updated = try await client.updateIssue(id: issueId, priority: priority)
            self.issue = updated
        } catch {
            // silently fail
        }
        isUpdating = false
    }

    private func postComment(content: String) async {
        guard let client = authClient() else { return }
        do {
            let comment = try await client.createComment(issueId: issueId, content: content)
            comments.append(comment)
        } catch {
            // silently fail
        }
    }

    private func authClient() -> APIClient? {
        auth.getAPIClient()
    }
}

// MARK: - Status Picker

private struct StatusPicker: View {
    let current: IssueStatus
    let onSelect: (IssueStatus) -> Void
    @State private var isExpanded = false

    var body: some View {
        Menu {
            ForEach(IssueStatus.allCases) { status in
                Button(status.displayName) {
                    onSelect(status)
                }
            }
        } label: {
            StatusBadge(status: current)
        }
        .menuStyle(.borderlessButton)
    }
}

// MARK: - Priority Picker

private struct PriorityPicker: View {
    let current: IssuePriority
    let onSelect: (IssuePriority) -> Void

    var body: some View {
        Menu {
            ForEach(IssuePriority.allCases) { priority in
                Button(priority.displayName) {
                    onSelect(priority)
                }
            }
        } label: {
            PriorityBadge(priority: current)
        }
        .menuStyle(.borderlessButton)
    }
}
