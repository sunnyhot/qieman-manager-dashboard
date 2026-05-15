import Foundation

// MARK: - Issues API

extension APIClient {
    func listIssues(
        status: [IssueStatus]? = nil,
        assigneeId: String? = nil,
        limit: Int = 50,
        offset: Int = 0
    ) async throws -> (issues: [Issue], total: Int, hasMore: Bool) {
        var path = "api/issues?limit=\(limit)&offset=\(offset)"
        if let status, !status.isEmpty {
            let statusStr = status.map(\.rawValue).joined(separator: ",")
            path += "&status=\(statusStr)"
        }
        if let assigneeId {
            path += "&assignee_id=\(assigneeId)"
        }
        let response: IssueListResponse = try await get(path)
        return (response.issues, response.total, response.hasMore)
    }

    func getIssue(id: String) async throws -> Issue {
        try await get("api/issues/\(id)")
    }

    func createIssue(
        title: String,
        description: String? = nil,
        priority: IssuePriority? = nil,
        assigneeId: String? = nil,
        parentIssueId: String? = nil
    ) async throws -> Issue {
        let body = CreateIssueRequest(
            title: title,
            description: description,
            priority: priority,
            assigneeId: assigneeId,
            parentIssueId: parentIssueId,
            projectId: nil
        )
        return try await post("api/issues", body: body)
    }

    func updateIssue(
        id: String,
        title: String? = nil,
        description: String? = nil,
        status: IssueStatus? = nil,
        priority: IssuePriority? = nil,
        assigneeId: String? = nil
    ) async throws -> Issue {
        let body = UpdateIssueRequest(
            title: title,
            description: description,
            status: status,
            priority: priority,
            assigneeId: assigneeId
        )
        return try await patch("api/issues/\(id)", body: body)
    }

    func deleteIssue(id: String) async throws {
        try await deleteRaw("api/issues/\(id)")
    }
}

// MARK: - Comments API

extension APIClient {
    func listComments(issueId: String) async throws -> [Comment] {
        try await get("api/issues/\(issueId)/comments")
    }

    func createComment(issueId: String, content: String, parentId: String? = nil) async throws -> Comment {
        let body = CreateCommentRequest(content: content, parentId: parentId)
        return try await post("api/issues/\(issueId)/comments", body: body)
    }

    func updateComment(commentId: String, content: String) async throws -> Comment {
        let body = UpdateCommentRequest(content: content)
        return try await patch("api/comments/\(commentId)", body: body)
    }

    func deleteComment(commentId: String) async throws {
        try await deleteRaw("api/comments/\(commentId)")
    }
}

// MARK: - Labels API

extension APIClient {
    func listLabels() async throws -> [IssueLabel] {
        try await get("api/labels")
    }

    func attachLabel(issueId: String, labelId: String) async throws {
        _ = try await requestRaw("api/issues/\(issueId)/labels/\(labelId)", method: "POST")
    }

    func detachLabel(issueId: String, labelId: String) async throws {
        try await deleteRaw("api/issues/\(issueId)/labels/\(labelId)")
    }
}

// MARK: - Reactions API

extension APIClient {
    func addReaction(commentId: String, emoji: String) async throws -> Reaction {
        try await post("api/comments/\(commentId)/reactions", body: ["emoji": emoji])
    }

    func removeReaction(commentId: String, emoji: String) async throws {
        try await deleteRaw("api/comments/\(commentId)/reactions/\(emoji)")
    }

    func addIssueReaction(issueId: String, emoji: String) async throws -> Reaction {
        try await post("api/issues/\(issueId)/reactions", body: ["emoji": emoji])
    }

    func removeIssueReaction(issueId: String, emoji: String) async throws {
        try await deleteRaw("api/issues/\(issueId)/reactions/\(emoji)")
    }
}

// MARK: - Subscribers API

extension APIClient {
    func listSubscribers(issueId: String) async throws -> [IssueSubscriber] {
        try await get("api/issues/\(issueId)/subscribers")
    }

    func subscribeToIssue(issueId: String) async throws {
        _ = try await requestRaw("api/issues/\(issueId)/subscribers", method: "POST")
    }
}

// MARK: - Members API

extension APIClient {
    func listWorkspaceMembers() async throws -> [WorkspaceMember] {
        try await get("api/workspace/members")
    }
}
