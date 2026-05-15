import SwiftUI

// MARK: - Login View

struct LoginView: View {
    @EnvironmentObject private var auth: AuthManager
    @State private var email = ""
    @State private var code = ""
    @State private var codeSent = false
    @State private var isSendingCode = false
    @State private var isVerifying = false
    @State private var countdown = 0
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 32) {
            VStack(spacing: 16) {
                Image(systemName: "app.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.blue)

                Text("欢迎来到 Multica")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.primary)

                Text("请使用邮箱验证码登录")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("邮箱地址")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)

                    TextField("请输入邮箱", text: $email)
                        .textFieldStyle(.plain)
                        .padding()
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(8)
                        .disabled(codeSent)
                }

                if codeSent {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("验证码")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)

                        HStack {
                            TextField("请输入6位验证码", text: $code)
                                .textFieldStyle(.plain)
                                .padding()
                                .background(Color(nsColor: .controlBackgroundColor))
                                .cornerRadius(8)

                            Button(action: resendCode) {
                                Text(countdown > 0 ? "\(countdown)s" : "重发")
                                    .font(.system(size: 14))
                                    .foregroundStyle(countdown > 0 ? Color.secondary : Color.blue)
                            }
                            .buttonStyle(.plain)
                            .disabled(countdown > 0 || isSendingCode)
                        }
                    }
                }
            }
            .padding(.horizontal, 40)

            VStack(spacing: 12) {
                if !codeSent {
                    Button(action: sendCode) {
                        if isSendingCode {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Text("发送验证码")
                                .font(.system(size: 16, weight: .semibold))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(email.isEmpty || isSendingCode)
                } else {
                    Button(action: verifyCode) {
                        if isVerifying {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Text("登录")
                                .font(.system(size: 16, weight: .semibold))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(code.isEmpty || isVerifying)

                    Button(action: resetEmail) {
                        Text("更换邮箱")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 40)

            if let error = auth.errorMessage {
                Text(error)
                    .font(.system(size: 14))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 40)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(40)
        .frame(width: 480, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .onDisappear {
            timer?.invalidate()
        }
    }

    // MARK: - Actions

    private func sendCode() {
        guard !email.isEmpty else { return }

        isSendingCode = true

        Task { @MainActor in
            do {
                try await auth.login(email: email)
                codeSent = true
                startCountdown()
            } catch {
                // Error is already handled by auth.errorMessage
            }
            isSendingCode = false
        }
    }

    private func resendCode() {
        guard countdown == 0 else { return }
        sendCode()
    }

    private func verifyCode() {
        guard !code.isEmpty else { return }

        isVerifying = true

        Task { @MainActor in
            do {
                try await auth.verify(email: email, code: code)
            } catch {
                // Error is already handled by auth.errorMessage
            }
            isVerifying = false
        }
    }

    private func resetEmail() {
        codeSent = false
        code = ""
        countdown = 0
        timer?.invalidate()
        timer = nil
    }

    private func startCountdown() {
        countdown = 60
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if countdown > 0 {
                countdown -= 1
            } else {
                timer?.invalidate()
                timer = nil
            }
        }
    }
}