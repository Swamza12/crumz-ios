import SwiftUI

/// Student Login Screen replicating `LoginScreen.kt` 1:1:
/// - 240 pt Dark Blue gradient hero header with 48 pt bottom rounded corners
/// - Pulsing CRUMZ header (White <-> CrumzGold over 2s)
/// - NCR Registered & Students Only badges
/// - Crisp, non-blurry, high-contrast CrumzDarkBlue inputs
/// - Pure bright white (#FFFFFF) ExtraBold "Sign In →" button text
struct LoginView: View {
    @StateObject private var viewModel = AuthViewModel()
    let onLoginSuccess: () -> Void
    let onForcePasswordChange: () -> Void

    @State private var studentNumber: String = ""
    @State private var password: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String = ""
    @State private var pulseGold: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Top Dark Blue Gradient Hero Section
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [.crumzDarkBlue, .crumzDarkBlueLight],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(SelectiveRoundedCorner(radius: 48, corners: [.bottomLeft, .bottomRight]))
                .ignoresSafeArea(edges: .top)

                VStack(alignment: .leading, spacing: 2) {
                    Text("CRUMZ")
                        .font(.system(size: 36, weight: .heavy))
                        .tracking(2)
                        .foregroundColor(pulseGold ? .crumzGold : .white)
                        .padding(.bottom, 2)

                    Text("Welcome")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.white)

                    Text("Sign in to access your Crumz wallet")
                        .font(.system(size: 14))
                        .foregroundColor(Color.white.opacity(0.8))
                }
                .padding(28)
            }
            .frame(height: 240)

            Spacer().frame(height: 24)

            // Body Content
            VStack(alignment: .leading, spacing: 0) {
                // Trust Badges
                HStack(spacing: 8) {
                    LoginBadge(text: "🔒 NCR Registered")
                    LoginBadge(text: "🎓 Students Only")
                    Spacer()
                }

                Spacer().frame(height: 32)

                // Crisp High-Contrast Inputs
                CrumzOutlinedField(
                    label: "STUDENT NUMBER",
                    text: Binding(
                        get: { studentNumber },
                        set: { studentNumber = $0; errorMessage = "" }
                    ),
                    isSecure: false,
                    keyboardType: .asciiCapable,
                    autocapitalization: .characters
                )

                Spacer().frame(height: 16)

                CrumzOutlinedField(
                    label: "PASSWORD",
                    text: Binding(
                        get: { password },
                        set: { password = $0; errorMessage = "" }
                    ),
                    isSecure: true
                )

                if !errorMessage.isEmpty {
                    Spacer().frame(height: 8)
                    Text(errorMessage)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(hex: 0xDC2626))
                }

                Spacer().frame(height: 24)

                // Sign In Button with pure bright white ExtraBold text
                Button(action: performLogin) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.crumzDarkBlue)

                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text("Sign In →")
                                .font(.system(size: 16, weight: .heavy))
                                .foregroundColor(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                }
                .disabled(isLoading)

                Spacer()

                Text("© 2026 Crumz. NCR Registered Credit Provider.")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: 0x94A3B8))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 20)
            }
            .padding(.horizontal, 28)
        }
        .background(Color.white.ignoresSafeArea())
        .onAppear {
            withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: true)) {
                pulseGold = true
            }
        }
    }

    private func performLogin() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        viewModel.login(rawStudentNumber: studentNumber, password: password) { status in
            switch status {
            case .loading:
                isLoading = true
            case .successForceChange:
                isLoading = false
                onForcePasswordChange()
            case .successReady:
                isLoading = false
                onLoginSuccess()
            case .error(let msg):
                isLoading = false
                errorMessage = msg
            case .idle:
                break
            }
        }
    }
}

private struct LoginBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(.crumzDarkBlue)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.crumzSurface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.crumzDarkBlue.opacity(0.2), lineWidth: 1)
            )
    }
}
