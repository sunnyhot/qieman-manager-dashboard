import SwiftUI

struct CreateIssueView: View {
    @Binding var isPresented: Bool
    let onCreated: () -> Void
    @EnvironmentObject private var auth: AuthManager

    @State private var title = ""
    @State private var description = ""
    @State private var selectedPriority: IssuePriority = .none
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("新建 Issue")
                    .font(.system(size: 18, weight: .bold))
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider()

            // Form
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("标题")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField("输入标题", text: $title)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                        )
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("描述")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextEditor(text: $description)
                        .font(.system(size: 13))
                        .frame(minHeight: 120)
                        .padding(6)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                        )
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("优先级")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    Picker("优先级", selection: $selectedPriority) {
                        ForEach(IssuePriority.allCases) { priority in
                            HStack(spacing: 4) {
                                Image(systemName: priority.systemImage)
                                Text(priority.displayName)
                            }
                            .tag(priority)
                        }
                    }
                    .pickerStyle(.menu)
                }

                if let error = errorMessage {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                }
            }
            .padding(20)

            Spacer()

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("取消") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button("创建") {
                    Task { await createIssue() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
            }
            .padding(20)
        }
        .frame(width: 480, height: 440)
    }

    private func createIssue() async {
        isCreating = true
        errorMessage = nil

        do {
            let client = auth.getAPIClient()
            let priority: IssuePriority? = selectedPriority == .none ? nil : selectedPriority
            _ = try await client.createIssue(
                title: title.trimmingCharacters(in: .whitespaces),
                description: description.isEmpty ? nil : description,
                priority: priority
            )
            onCreated()
            isPresented = false
        } catch {
            errorMessage = error.localizedDescription
        }
        isCreating = false
    }
}
