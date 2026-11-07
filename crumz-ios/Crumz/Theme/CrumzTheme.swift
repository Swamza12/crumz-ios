import SwiftUI
import UIKit
import CryptoKit

// MARK: - Exact Brand Colors (Matching Android Color.kt 1:1)
extension Color {
    /// #131B3A — RGB(19, 27, 58)
    static let crumzDarkBlue = Color(red: 19.0 / 255.0, green: 27.0 / 255.0, blue: 58.0 / 255.0)
    /// #1E2B58 — RGB(30, 43, 88)
    static let crumzDarkBlueLight = Color(red: 30.0 / 255.0, green: 43.0 / 255.0, blue: 88.0 / 255.0)
    /// #D6932C — RGB(214, 147, 44)
    static let crumzGold = Color(red: 214.0 / 255.0, green: 147.0 / 255.0, blue: 44.0 / 255.0)
    /// #EAB35E — RGB(234, 179, 94)
    static let crumzGoldLight = Color(red: 234.0 / 255.0, green: 179.0 / 255.0, blue: 94.0 / 255.0)
    /// #F8FAFC — RGB(248, 250, 252)
    static let crumzSurface = Color(red: 248.0 / 255.0, green: 250.0 / 255.0, blue: 252.0 / 255.0)

    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

extension UIColor {
    static let crumzDarkBlue = UIColor(red: 19.0 / 255.0, green: 27.0 / 255.0, blue: 58.0 / 255.0, alpha: 1.0)
    static let crumzDarkBlueLight = UIColor(red: 30.0 / 255.0, green: 43.0 / 255.0, blue: 88.0 / 255.0, alpha: 1.0)
    static let crumzGold = UIColor(red: 214.0 / 255.0, green: 147.0 / 255.0, blue: 44.0 / 255.0, alpha: 1.0)
}

// MARK: - Byte-for-Byte SHA-256 PIN Hashing (Matches Android MessageDigest SHA-256)
enum CrumzCrypto {
    /// Produces lowercase hex SHA-256 digest of UTF-8 `(salt + pin)` — identical to Android's `hashPin`.
    static func hashPin(pin: String, salt: String) -> String {
        let data = Data((salt + pin).utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Exact Screen-Space Arc Path (Matches Jetpack Compose Canvas.drawArc)
/// In screen coordinates (+X right, +Y down):
/// 0° = 3 o'clock, +90° = 6 o'clock, -45° = upper-right.
/// Positive `sweepDegrees` moves clockwise; negative `sweepDegrees` moves counter-clockwise.
func crumzScreenArcPath(
    center: CGPoint,
    radius: CGFloat,
    startDegrees: Double,
    sweepDegrees: Double
) -> Path {
    var path = Path()
    guard abs(sweepDegrees) > 0.01 else { return path }
    let steps = max(24, Int(abs(sweepDegrees) / 2.0))
    for i in 0...steps {
        let t = Double(i) / Double(steps)
        let deg = startDegrees + sweepDegrees * t
        let rad = deg * .pi / 180.0
        let pt = CGPoint(
            x: center.x + radius * CGFloat(cos(rad)),
            y: center.y + radius * CGFloat(sin(rad))
        )
        if i == 0 {
            path.move(to: pt)
        } else {
            path.addLine(to: pt)
        }
    }
    return path
}

// MARK: - Selective Rounded Corners Shape
struct SelectiveRoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - High-Contrast Outlined Input Field (Matches LoginScreen.kt & ChangePasswordScreen.kt)
struct CrumzOutlinedField: View {
    let label: String
    @Binding var text: String
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default
    var autocapitalization: TextInputAutocapitalization = .never

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(isFocused ? .crumzDarkBlue : Color(hex: 0x64748B))

            Group {
                if isSecure {
                    SecureField("", text: $text)
                        .focused($isFocused)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.crumzDarkBlue)
                        .tint(.crumzGold)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                } else {
                    TextField("", text: $text)
                        .focused($isFocused)
                        .keyboardType(keyboardType)
                        .textInputAutocapitalization(autocapitalization)
                        .autocorrectionDisabled(true)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.crumzDarkBlue)
                        .tint(.crumzGold)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 54)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        isFocused ? Color.crumzDarkBlue : Color(hex: 0x94A3B8),
                        lineWidth: isFocused ? 2.0 : 1.25
                    )
            )
        }
    }
}

// MARK: - Shared Transaction Row Card (Used in MainView & HistoryView)
struct CrumzTransactionCard: View {
    let title: String
    let subtitle: String
    let amount: String
    let amountColor: Color
    let systemIcon: String

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(hex: 0xF1F5F9))
                    .frame(width: 48, height: 48)
                Image(systemName: systemIcon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.crumzDarkBlue)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.crumzDarkBlue)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(amount)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(amountColor)
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 3, x: 0, y: 1)
    }
}

// MARK: - Category Icon Helper
func crumzCategoryIcon(for category: String) -> String {
    let lower = category.lowercased()
    if lower.contains("food") || lower.contains("meal") || lower.contains("dining") {
        return "fork.knife"
    } else if lower.contains("book") || lower.contains("stationery") || lower.contains("supplies") {
        return "book.closed.fill"
    } else {
        return "storefront.fill"
    }
}

// MARK: - Toast Banner Modifier
struct CrumzToastModifier: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        ZStack(alignment: .bottom) {
            content

            if let msg = message, !msg.isEmpty {
                Text(msg)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(Color.crumzDarkBlue.opacity(0.95))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.crumzGold.opacity(0.5), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 4)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 36)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(999)
                    .task(id: msg) {
                        try? await Task.sleep(nanoseconds: 3_200_000_000)
                        if message == msg {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                message = nil
                            }
                        }
                    }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: message)
    }
}

extension View {
    func crumzToast(_ message: Binding<String?>) -> some View {
        modifier(CrumzToastModifier(message: message))
    }
}
