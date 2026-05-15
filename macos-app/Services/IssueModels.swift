import Foundation

// MARK: - Issue Status

enum IssueStatus: String, Codable, CaseIterable, Identifiable {
    case todo
    case inProgress = "in_progress"
    case inReview = "in_review"
    case done
    case blocked
    case backlog
    case cancelled

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .todo: return "To Do"
        case .inProgress: return "In Progress"
        case .inReview: return "In Review"
        case .done: return "Done"
        case .blocked: return "Blocked"
        case .backlog: return "Backlog"
        case .cancelled: return "Cancelled"
        }
    }

    var systemImage: String {
        switch self {
        case .todo: return "circle"
        case .inProgress: return "circle.lefthalf.filled"
        case .inReview: return "eye"
        case .done: return "checkmark.circle.fill"
        case .blocked: return "nosign"
        case .backlog: return "tray"
        case .cancelled: return "xmark.circle"
        }
    }
}

// MARK: - Issue Priority

enum IssuePriority: String, Codable, CaseIterable, Identifiable {
    case none
    case low
    case medium
    case high
    case urgent

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "None"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .urgent: return "Urgent"
        }
    }

    var systemImage: String {
        switch self {
        case .none: return "minus"
        case .low: return "arrow.down"
        case .medium: return "arrow.right"
        case .high: return "arrow.up"
        case .urgent: return "exclamationmark.3"
        }
    }
}

// MARK: - Issue

struct Issue: Codable, Identifiable {
    let id: String
    let identifier: String?
    let title: String
    let description: String?
    let status: IssueStatus
    let priority: IssuePriority
    let assigneeId: String?
    let assigneeType: String?
    let creatorId: String?
    let creatorType: String?
    let parentIssueId: String?
    let projectId: String?
    let workspaceId: String?
    let number: Int?
    let labels: [IssueLabel]?
    let dueDate: String?
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, identifier, title, description, status, priority
        case assigneeId = "assignee_id"
        case assigneeType = "assignee_type"
        case creatorId = "creator_id"
        case creatorType = "creator_type"
        case parentIssueId = "parent_issue_id"
        case projectId = "project_id"
        case workspaceId = "workspace_id"
        case number, labels
        case dueDate = "due_date"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Issue Label

struct IssueLabel: Codable, Identifiable {
    let id: String
    let name: String
    let color: String

    enum CodingKeys: String, CodingKey {
        case id, name, color
    }
}

// MARK: - Comment

struct Comment: Codable, Identifiable {
    let id: String
    let issueId: String
    let authorId: String
    let authorType: String?
    let content: String
    let parentId: String?
    let attachments: [CommentAttachment]?
    let reactions: [Reaction]?
    let resolvedAt: String?
    let resolvedById: String?
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case issueId = "issue_id"
        case authorId = "author_id"
        case authorType = "author_type"
        case content
        case parentId = "parent_id"
        case attachments, reactions
        case resolvedAt = "resolved_at"
        case resolvedById = "resolved_by_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct CommentAttachment: Codable, Identifiable {
    let id: String
    let fileName: String
    let fileSize: Int64
    let url: String

    enum CodingKeys: String, CodingKey {
        case id
        case fileName = "file_name"
        case fileSize = "file_size"
        case url
    }
}

// MARK: - Reaction

struct Reaction: Codable, Identifiable {
    let id: String
    let emoji: String
    let userId: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, emoji
        case userId = "user_id"
        case createdAt = "created_at"
    }
}

// MARK: - Issue Subscriber

struct IssueSubscriber: Codable, Identifiable {
    let id: String
    let userId: String
    let userType: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case userType = "user_type"
        case createdAt = "created_at"
    }
}

// MARK: - Workspace Member

struct WorkspaceMember: Codable, Identifiable {
    let id: String
    let name: String
    let email: String?
    let role: String
    let avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, name, email, role
        case avatarUrl = "avatar_url"
    }
}

// MARK: - API Response Wrappers

struct IssueListResponse: Codable {
    let issues: [Issue]
    let total: Int
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case issues, total
        case hasMore = "has_more"
    }
}

struct CreateIssueRequest: Codable {
    let title: String
    let description: String?
    let priority: IssuePriority?
    let assigneeId: String?
    let parentIssueId: String?
    let projectId: String?

    enum CodingKeys: String, CodingKey {
        case title, description, priority
        case assigneeId = "assignee_id"
        case parentIssueId = "parent_issue_id"
        case projectId = "project_id"
    }
}

struct UpdateIssueRequest: Codable {
    let title: String?
    let description: String?
    let status: IssueStatus?
    let priority: IssuePriority?
    let assigneeId: String?

    enum CodingKeys: String, CodingKey {
        case title, description, status, priority
        case assigneeId = "assignee_id"
    }
}

struct CreateCommentRequest: Codable {
    let content: String
    let parentId: String?

    enum CodingKeys: String, CodingKey {
        case content
        case parentId = "parent_id"
    }
}

struct UpdateCommentRequest: Codable {
    let content: String
}
