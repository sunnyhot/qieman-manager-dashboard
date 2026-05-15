import SwiftUI

// MARK: - Status Badge

struct StatusBadge: View {
    let status: IssueStatus

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.systemImage)
                .font(.system(size: 10, weight: .semibold))
            Text(status.displayName)
                .font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.12), in: Capsule())
        .foregroundStyle(statusColor)
    }

    private var statusColor: Color {
        switch status {
        case .todo: return .secondary
        case .inProgress: return .blue
        case .inReview: return .purple
        case .done: return .green
        case .blocked: return .red
        case .backlog: return .gray
        case .cancelled: return .gray
        }
    }
}

// MARK: - Priority Badge

struct PriorityBadge: View {
    let priority: IssuePriority

    var body: some View {
        Image(systemName: priority.systemImage)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(priorityColor)
            .help(priority.displayName)
    }

    private var priorityColor: Color {
        switch priority {
        case .none: return .secondary
        case .low: return .blue
        case .medium: return .yellow
        case .high: return .orange
        case .urgent: return .red
        }
    }
}

// MARK: - Assignee Avatar

struct AssigneeAvatar: View {
    let name: String?
    let size: CGFloat

    init(name: String?, size: CGFloat = 28) {
        self.name = name
        self.size = size
    }

    var body: some View {
        Circle()
            .fill(Color.accentColor.opacity(0.15))
            .frame(width: size, height: size)
            .overlay(
                Text(initials)
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(.secondary)
            )
    }

    private var initials: String {
        guard let name, !name.isEmpty else { return "?" }
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts[0].first!)\(parts[1].first!)"
        }
        return String(name.prefix(2)).uppercased()
    }
}

// MARK: - Comment Card

struct CommentCard: View {
    let comment: Comment
    let authorName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                AssigneeAvatar(name: authorName, size: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(authorName ?? "Unknown")
                        .font(.system(size: 13, weight: .semibold))
                    Text(comment.createdAt.prefix(16))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Text(comment.content)
                .font(.system(size: 13))
                .textSelection(.enabled)

            if let reactions = comment.reactions, !reactions.isEmpty {
                ReactionBar(reactions: reactions)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Reaction Bar

struct ReactionBar: View {
    let reactions: [Reaction]

    private var grouped: [(String, Int)] {
        let freq = Dictionary(grouping: reactions, by: \.emoji)
        return freq.sorted { $0.key < $1.key }.map { ($0.key, $0.value.count) }
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(grouped, id: \.0) { emoji, count in
                HStack(spacing: 2) {
                    Text(emoji)
                    if count > 1 {
                        Text("\(count)")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.system(size: 13))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
            }
        }
    }
}

// MARK: - Comment Input

struct CommentInput: View {
    let onSubmit: (String) -> Void
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("写评论...", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($isFocused)
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )

            Button {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                onSubmit(trimmed)
                text = ""
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 24))
            }
            .buttonStyle(.plain)
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}

// MARK: - Label Chip

struct LabelChip: View {
    let label: IssueLabel

    var body: some View {
        Text(label.name)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color(hex: label.color).opacity(0.15), in: Capsule())
            .foregroundStyle(Color(hex: label.color))
    }
}

// MARK: - Color Hex Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let scanner = Scanner(string: hex)
        var rgbValue: UInt64 = 0
        scanner.scanHexInt64(&rgbValue)
        let r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = Double(rgbValue & 0x0000FF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
