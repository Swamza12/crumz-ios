import SwiftUI

/// Mandatory Temporary Password Replacement Screen replicating `ChangePasswordScreen.kt` 1:1.
struct ChangePasswordView: View {
    @StateObject private var viewModel = AuthViewModel()
    var onBack: (() -> Void)? = nil
    let onPasswordChanged: () -> Void

    @State private var newPassword: String = ""
    @State private var confirmPassword: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String = ""

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.white.ignoresSafeArea()

            if let onBack = onBack {
                Button(action: onBack) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 16, weight: .bold))
                        Text("Back")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundColor(.crumzDarkBlue)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .padding(.leading, 12)
                .padding(.top, 8)
            }

            VStack(spacing: 0) {
                Spacer()

                Text("🔒")
                    .font(.system(size: 48))
                    .padding(.bottom, 16)

                Text("Set New Password")
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundColor(.crumzDarkBlue)

                Spacer().frame(height: 8)

                Text("For security reasons, you must change your temporary password before accessing your wallet.")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)

                Spacer().frame(height: 32)

                CrumzOutlinedField(
                    label: "NEW PASSWORD",
                    text: Binding(
                        get: { newPassword },
                        set: { newPassword = $0; errorMessage = "" }
                    ),
                    isSecure: true
                )

                Spacer().frame(height: 16)

                CrumzOutlinedField(
                    label: "CONFIRM PASSWORD",
                    text: Binding(
                        get: { confirmPassword },
                        set: { confirmPassword = $0; errorMessage = "" }
                    ),
                    isSecure: true
                )

                if !errorMessage.isEmpty {
                    Spacer().frame(height: 8)
                    Text(errorMessage)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(hex: 0xDC2626))
                        .multilineTextAlignment(.center)
                }

                Spacer().frame(height: 32)

                Button(action: submitPasswordChange) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.crumzDarkBlue)

                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text("Change & Re-login")
                                .font(.system(size: 16, weight: .heavy))
                                .foregroundColor(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                }
                .disabled(isLoading)

                Spacer()
            }
            .padding(28)
        }
    }

    private func submitPasswordChange() {
        let trimmedNew = newPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedConfirm = confirmPassword.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedNew.isEmpty || trimmedConfirm.isEmpty {
            errorMessage = "Passwords cannot be empty"
        } else if newPassword != confirmPassword {
            errorMessage = "Passwords do not match"
        } else if newPassword.count < 6 {
            errorMessage = "Password must be at least 6 characters"
        } else {
            viewModel.changePassword(newPassword: newPassword) { status in
                switch status {
                case .loading:
                    isLoading = true
                case .success:
                    isLoading = false
                    onPasswordChanged()
                case .error(let msg):
                    isLoading = false
                    errorMessage = msg
                case .idle:
                    break
                }
            }
        }
    }
}
