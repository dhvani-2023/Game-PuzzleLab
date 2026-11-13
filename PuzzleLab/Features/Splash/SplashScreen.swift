import SwiftUI

/// About 1.4 s: the pinwheel tiles fly in, a glow pulses and a shine sweeps across them, the name rises
/// in, and the same Night Lab backdrop carries on into the app.
struct SplashScreen: View {
    let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }

    @State private var pieces: [Double] = [0, 0, 0, 0, 0]
    @State private var glow: Double = 0
    @State private var shine: Double = 0
    @State private var shining = false
    @State private var title: Double = 0
    @State private var leave: Double = 0

    var body: some View {
        let lab = Lab.colors
        let games = GameRegistry.games.count
        let levels = GameRegistry.totalLevels / 100 * 100
        let side: CGFloat = 132
        ZStack {
            LabBackground(animated: false)
            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [lab.brand2.copy(alpha: 0.75), .clear], center: .center, startRadius: 0, endRadius: 162))
                        .frame(width: 324, height: 324)
                        .scaleEffect((0.7 + 0.38 * glow) / 1.08)
                        .opacity(glow)
                        .blur(radius: 8)
                    ZStack {
                        AnimatedPinwheel(size: side, progress: pieces)
                        if shining {
                            LinearGradient(colors: [.clear, Color.white.opacity(0.75), .clear], startPoint: .leading, endPoint: .trailing)
                                .frame(width: side * 0.45, height: side * 2)
                                .rotationEffect(.degrees(18))
                                .offset(x: -side * 0.6 + side * 1.7 * shine + side * 0.45 / 2 - side / 2)
                                .frame(width: side, height: side)
                                .mask(PinwheelMask())
                                .blendMode(.plusLighter)
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(width: side, height: side)
                }
                .frame(width: 300, height: 300)
                .scaleEffect(1 - 0.14 * leave)
                VStack(spacing: 8) {
                    Text("\(games) GAMES · \(levels.grouped)+ LEVELS").font(LabText.eyebrow).foregroundStyle(lab.sun)
                    Text("Puzzle Lab").font(LabText.display).foregroundStyle(lab.ink)
                }
                .opacity(min(max(title, 0), 1))
                .offset(y: (1 - title) * 16)
                .offset(y: -60)
            }
            .offset(y: -24)
            .opacity(1 - leave)
            // NG Studio branding at the bottom — "A game by" label + logo
            VStack(spacing: 6) {
                Spacer()
                Text("A GAME BY").font(LabText.eyebrow).foregroundStyle(lab.ink2.copy(alpha: 0.6))
                Image("NGStudioLogo")
                    .resizable()
                    .aspectRatio(1.505, contentMode: .fit)
                    .frame(width: 188)
                    .accessibilityLabel("NG Studio")
            }
            .padding(.bottom, 32)
            .opacity(min(max(title * 0.85, 0), 1))
        }
        .task {
            // Warm up the level packs while the logo plays.
            GameRegistry.preloadInBackground()
            if Lab.reduceMotion {
                pieces = [1, 1, 1, 1, 1]
                title = 1
                try? await Task.sleep(nanoseconds: 600_000_000)
                onFinish()
                return
            }
            try? await Task.sleep(nanoseconds: 80_000_000)
            for i in 0..<5 {
                withAnimation(labSpring(0.62, i == 4 ? 0.45 : 0.68).delay(Double(i) * 0.09)) { pieces[i] = 1 }
            }
            try? await Task.sleep(nanoseconds: 450_000_000)
            Haptics.toggle()
            UISound.sparkle()
            withAnimation(tween(400)) { glow = 1 }
            withAnimation(labSpring(0.6, 0.88)) { title = 1 }
            // The band must exist before it moves, so it sweeps instead of appearing at its end.
            shining = true
            try? await Task.sleep(nanoseconds: 16_000_000)
            withAnimation(tween(550)) { shine = 1 }
            try? await Task.sleep(nanoseconds: 534_000_000)
            shining = false
            withAnimation(labSpring(0.5, 0.86)) { leave = 1 }
            try? await Task.sleep(nanoseconds: 220_000_000)
            onFinish()
        }
    }
}

/// The pinwheel tiles as a mask shape (for the shine sweep).
private struct PinwheelMask: Shape {
    func path(in rect: CGRect) -> Path {
        pinwheelPath(min(rect.width, rect.height)).offsetBy(dx: rect.minX, dy: rect.minY)
    }
}
