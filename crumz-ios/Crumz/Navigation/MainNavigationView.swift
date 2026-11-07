import SwiftUI
import UIKit
import FirebaseAuth

/// Root navigation container replicating `Navigation.kt` 1:1:
/// - Explicit `backStack` matching `androidx.navigation3`'s `rememberNavBackStack(Splash)`
/// - Global 90-second touch/keyboard inactivity auto-logout timer
/// - `returnToScanAfterPinSetup` redirect loop between `ScanView` and `ProfileView`
struct MainNavigationView: View {
    @State private var backStack: [NavRouteKey] = [.splash]
    @State private var lastInteractionTime: Date = Date()
    @State private var returnToScanAfterPinSetup: Bool = false

    private let inactivityTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    private var currentScreen: NavRouteKey {
        backStack.last ?? .login
    }

    var body: some View {
        ZStack {
            screenContent(for: currentScreen)
                .id(currentScreen)
                .transition(.opacity)

            // Non-blocking touch & keyboard monitor across the entire window
            PassthroughActivityMonitor {
                lastInteractionTime = Date()
            }
            .ignoresSafeArea()
        }
        .animation(.easeInOut(duration: 0.2), value: currentScreen)
        .onReceive(inactivityTimer) { now in
            let idleSeconds = now.timeIntervalSince(lastInteractionTime)
            if idleSeconds >= 90.0 {
                let current = backStack.last
                if current != .splash && current != .login {
                    try? Auth.auth().signOut()
                    returnToScanAfterPinSetup = false
                    backStack = [.login]
                    lastInteractionTime = now
                }
            }
        }
    }

    @ViewBuilder
    private func screenContent(for route: NavRouteKey) -> some View {
        switch route {
        case .splash:
            SplashView {
                backStack = [.login]
                lastInteractionTime = Date()
            }

        case .login:
            LoginView(
                onLoginSuccess: {
                    lastInteractionTime = Date()
                    backStack = [.main]
                },
                onForcePasswordChange: {
                    lastInteractionTime = Date()
                    backStack.append(.changePassword)
                }
            )

        case .changePassword:
            ChangePasswordView(
                onBack: backStack.count > 1 && backStack.dropLast().last == .profile ? {
                    _ = backStack.popLast()
                } : nil,
                onPasswordChanged: {
                    lastInteractionTime = Date()
                    if backStack.count > 1 {
                        _ = backStack.popLast()
                    } else {
                        backStack = [.login]
                    }
                    if backStack.last == .login {
                        try? Auth.auth().signOut()
                    }
                }
            )

        case .main:
            MainView(
                onItemClick: { target in
                    lastInteractionTime = Date()
                    backStack.append(target)
                },
                onLogoutClick: {
                    returnToScanAfterPinSetup = false
                    backStack = [.login]
                }
            )

        case .scanQR:
            ScanView(
                onBack: {
                    if backStack.count > 1 {
                        _ = backStack.popLast()
                    } else {
                        backStack = [.main]
                    }
                },
                onNavigateToProfile: {
                    returnToScanAfterPinSetup = true
                    if !backStack.isEmpty {
                        _ = backStack.popLast()
                    }
                    backStack.append(.profile)
                }
            )

        case .vendorsMap:
            VendorsMapView(
                onBack: {
                    if backStack.count > 1 {
                        _ = backStack.popLast()
                    } else {
                        backStack = [.main]
                    }
                }
            )

        case .history:
            HistoryView(
                onBackClick: {
                    if backStack.count > 1 {
                        _ = backStack.popLast()
                    } else {
                        backStack = [.main]
                    }
                }
            )

        case .profile:
            ProfileView(
                onBackClick: {
                    returnToScanAfterPinSetup = false
                    if backStack.count > 1 {
                        _ = backStack.popLast()
                    } else {
                        backStack = [.main]
                    }
                },
                onLogoutClick: {
                    returnToScanAfterPinSetup = false
                    backStack = [.login]
                },
                onChangePasswordClick: {
                    backStack.append(.changePassword)
                },
                autoOpenPinSetup: returnToScanAfterPinSetup,
                onPinSavedReturnToScan: returnToScanAfterPinSetup ? {
                    returnToScanAfterPinSetup = false
                    if !backStack.isEmpty {
                        _ = backStack.popLast()
                    }
                    backStack.append(.scanQR)
                } : nil
            )
        }
    }
}

/// Transparent UIView overlay that observes every screen touch and keyboard keystroke
/// via `hitTest` while returning `nil` so zero gestures or taps are ever intercepted.
private struct PassthroughActivityMonitor: UIViewRepresentable {
    let onActivity: () -> Void

    func makeUIView(context: Context) -> TouchSniffingView {
        let view = TouchSniffingView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = true
        view.onActivity = onActivity
        return view
    }

    func updateUIView(_ uiView: TouchSniffingView, context: Context) {
        uiView.onActivity = onActivity
    }

    final class TouchSniffingView: UIView {
        var onActivity: (() -> Void)?
        private var textObserver: NSObjectProtocol?

        override init(frame: CGRect) {
            super.init(frame: frame)
            textObserver = NotificationCenter.default.addObserver(
                forName: UITextField.textDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.onActivity?()
            }
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
        }

        deinit {
            if let obs = textObserver {
                NotificationCenter.default.removeObserver(obs)
            }
        }

        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            if event?.type == .touches {
                DispatchQueue.main.async { [weak self] in
                    self?.onActivity?()
                }
            }
            return nil
        }
    }
}
