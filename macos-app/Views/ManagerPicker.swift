import SwiftUI

/// 主理人多选 + 联想搜索控件。
struct ManagerPicker: View {
    let managers: [ManagerSummary]
    let selectedIds: Set<String>
    let isLoading: Bool
    let error: String?
    let onToggle: (String) -> Void
    let onRetry: () -> Void

    @State private var query: String = ""

    private var filtered: [ManagerSummary] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return managers }
        return managers.filter {
            $0.userName.lowercased().contains(trimmed) ||
            $0.userLabel.lowercased().contains(trimmed) ||
            $0.groupName.lowercased().contains(trimmed)
        }
    }

    private var selectedManagers: [ManagerSummary] {
        managers.filter { selectedIds.contains($0.brokerUserId) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !selectedManagers.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(selectedManagers) { manager in
                        ManagerChip(manager: manager) {
                            onToggle(manager.brokerUserId)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AppPalette.muted)
                TextField("搜索主理人 / 小组", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(AppPalette.muted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(AppPalette.card, in: RoundedRectangle(cornerRadius: AppPalette.controlRadius))
            .overlay(
                RoundedRectangle(cornerRadius: AppPalette.controlRadius)
                    .stroke(AppPalette.line, lineWidth: 1)
            )

            if isLoading {
                Text("正在加载主理人列表…")
                    .font(.system(size: 11))
                    .foregroundStyle(AppPalette.muted)
            } else if let error {
                VStack(alignment: .leading, spacing: 6) {
                    Text("加载失败：\(error)")
                        .font(.system(size: 11))
                        .foregroundStyle(AppPalette.warning)
                    Button("重试") { onRetry() }
                        .font(.system(size: 11))
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(filtered) { manager in
                        ManagerRow(
                            manager: manager,
                            isSelected: selectedIds.contains(manager.brokerUserId)
                        ) {
                            onToggle(manager.brokerUserId)
                        }
                    }
                    if filtered.isEmpty {
                        Text("没有匹配的主理人")
                            .font(.system(size: 11))
                            .foregroundStyle(AppPalette.muted)
                    }
                }
            }
        }
    }
}

private struct ManagerChip: View {
    let manager: ManagerSummary
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(manager.userName)
                .font(.system(size: 11, weight: .medium))
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppPalette.muted)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(AppPalette.brand.opacity(0.12), in: Capsule())
        .overlay(Capsule().stroke(AppPalette.brand.opacity(0.3), lineWidth: 1))
    }
}

private struct ManagerRow: View {
    let manager: ManagerSummary
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? AppPalette.brand : AppPalette.muted)
                VStack(alignment: .leading, spacing: 2) {
                    Text(manager.userName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppPalette.ink)
                    Text("\(manager.userLabel) · \(manager.groupName)")
                        .font(.system(size: 10))
                        .foregroundStyle(AppPalette.muted)
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
