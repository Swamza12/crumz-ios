import SwiftUI

/// Animated Splash Screen replicating `SplashScreen.kt` 1:1:
/// - White background
/// - 220x220 pt vector Canvas with 3D-shadowed Dark Blue 'C' (-45° start, -270° sweep, 60*scale round stroke)
/// - 5 bouncy spring Gold crumbs at exact scaled coordinates on a 240x240 grid
/// - "Dignity beyond paydays" slogan fading in at 1.4s
/// - 3.0s total duration before transitioning to Login
struct SplashView: View {
    let onTimeout: () -> Void

    @State private var cProgress: Double = 0.0
    @State private var crumbsProgress: CGFloat = 0.0
    @State private var textAlpha: Double = 0.0

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 0) {
                Canvas { context, size in
                    let scale = size.width / 240.0
                    let sweep = -270.0 * cProgress
                    let strokeWidth = 60.0 * scale
                    let radius = 80.0 * scale

                    // 1. 3D Shadow for 'C' (offset +8, +12)
                    let shadowCenter = CGPoint(x: 120.0 * scale + 8.0, y: 120.0 * scale + 12.0)
                    let shadowArc = crumzScreenArcPath(
                        center: shadowCenter,
                        radius: radius,
                        startDegrees: -45.0,
                        sweepDegrees: sweep
                    )
                    context.stroke(
                        shadowArc,
                        with: .color(Color.black.opacity(0.25)),
                        style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                    )

                    // 2. Main Dark Blue 'C' Arc
                    let mainCenter = CGPoint(x: 120.0 * scale, y: 120.0 * scale)
                    let mainArc = crumzScreenArcPath(
                        center: mainCenter,
                        radius: radius,
                        startDegrees: -45.0,
                        sweepDegrees: sweep
                    )
                    context.stroke(
                        mainArc,
                        with: .color(.crumzDarkBlue),
                        style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                    )

                    // 3. The 5 Gold Crumbs with 3D drop shadows (+8, +12)
                    if crumbsProgress > 0.0 {
                        let sX: CGFloat = 8.0
                        let sY: CGFloat = 12.0
                        let crumbs: [(CGFloat, CGFloat, CGFloat)] = [
                            (196.0, 120.0, 6.0),    // 1. Top inside gap (tiny)
                            (215.0, 175.0, 9.5),    // 2. Mid-Top right (medium)
                            (182.0, 208.0, 14.5),   // 3. Middle right (largest, outside corner)
                            (138.0, 226.0, 11.0),   // 4. Mid-Bottom (medium, underneath bottom lip)
                            (94.0,  216.0, 7.0)     // 5. Bottom (small, directly underneath)
                        ]

                        for (cx, cy, cr) in crumbs {
                            let r = max(0, cr * scale * crumbsProgress)
                            let shadowRect = CGRect(
                                x: cx * scale + sX - r,
                                y: cy * scale + sY - r,
                                width: r * 2,
                                height: r * 2
                            )
                            let mainRect = CGRect(
                                x: cx * scale - r,
                                y: cy * scale - r,
                                width: r * 2,
                                height: r * 2
                            )
                            context.fill(Path(ellipseIn: shadowRect), with: .color(Color.black.opacity(0.25)))
                            context.fill(Path(ellipseIn: mainRect), with: .color(.crumzGold))
                        }
                    }
                }
                .frame(width: 220, height: 220)

                Spacer().frame(height: 64)

                Text("Dignity beyond paydays")
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundColor(.crumzDarkBlue)
                    .opacity(textAlpha)
            }
        }
        .task {
            withAnimation(.easeInOut(duration: 1.0)) {
                cProgress = 1.0
            }
            withAnimation(.spring(response: 0.75, dampingFraction: 0.52)) {
                crumbsProgress = 1.0
            }
            withAnimation(.easeOut(duration: 0.8).delay(1.4)) {
                textAlpha = 1.0
            }

            try? await Task.sleep(nanoseconds: 3_000_000_000)
            onTimeout()
        }
    }
}
