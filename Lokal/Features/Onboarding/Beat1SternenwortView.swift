//
//  Beat1SternenwortView.swift
//  Lokalo
//
//  First beat of the onboarding flow. Mirrors the HTML prototype in
//  `onboarding-preview/beat1_sternenwort.html` 1:1 in SwiftUI:
//
//    1. A particle field drifts in from the screen edges and gathers into a
//       brain-blob ring centered slightly above the screen middle.
//    2. The "Lokalo" wordmark fades in at the brain's empty center after 2.5 s.
//    3. Four privacy promises ("Kein Konto." …) appear sequentially below the
//       constellation between 3.0–4.2 s.
//    4. A pulsing "ZUM STARTEN WISCHEN →" hint appears at 5.0 s and breathes
//       gently between 0.85 and 0.55 opacity, with a slowly-drifting arrow.
//    5. A tap or a left-swipe slides the whole view out and calls onAdvance().
//

import SwiftUI

struct Beat1SternenwortView: View {
    let onAdvance: () -> Void

    @State private var animator = Beat1Animator()
    @State private var startDate: Date = .now

    @State private var titleVisible = false
    @State private var p1Visible = false
    @State private var p2Visible = false
    @State private var p3Visible = false
    @State private var p4Visible = false
    @State private var hintVisible = false
    @State private var swiped = false

    var body: some View {
        ZStack {
            background
            constellation
            title
            bottomStack
        }
        .ignoresSafeArea()
        .opacity(swiped ? 0 : 1)
        .offset(x: swiped ? -120 : 0)
        .animation(.easeOut(duration: 0.55), value: swiped)
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    if value.translation.width < -28 {
                        advance()
                    }
                }
        )
        .onTapGesture { advance() }
        .onAppear { runChoreography() }
    }

    // MARK: - Layers

    private var background: some View {
        LinearGradient(
            colors: [
                Color(red: 0.02, green: 0.04, blue: 0.10),
                Color(red: 0.04, green: 0.06, blue: 0.16),
                Color(red: 0.01, green: 0.02, blue: 0.06)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var constellation: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
            Canvas { ctx, size in
                let elapsed = context.date.timeIntervalSince(startDate)
                animator.step(time: elapsed, size: size)

                // Draw connection lines once particles have started gathering.
                if elapsed > 1.0 {
                    let particles = animator.particles
                    for i in 0..<particles.count {
                        for j in (i + 1)..<particles.count {
                            let a = particles[i]
                            let b = particles[j]
                            let dx = a.x - b.x
                            let dy = a.y - b.y
                            let d = (dx * dx + dy * dy).squareRoot()
                            if d < 95 {
                                let alpha = (1 - d / 95) * 0.18 * min(a.opacity, b.opacity)
                                var path = Path()
                                path.move(to: CGPoint(x: a.x, y: a.y))
                                path.addLine(to: CGPoint(x: b.x, y: b.y))
                                ctx.stroke(path, with: .color(.white.opacity(alpha)), lineWidth: 0.6)
                            }
                        }
                    }
                }

                // Draw particles.
                for p in animator.particles {
                    let r = p.size
                    let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
                    ctx.fill(Path(ellipseIn: rect), with: .color(.white.opacity(p.opacity)))
                }
            }
        }
        .ignoresSafeArea()
    }

    private var title: some View {
        Text("Lokalo")
            .font(.system(size: 46, weight: .ultraLight))
            .foregroundStyle(.white.opacity(0.92))
            .tracking(0.4)
            .opacity(titleVisible ? 1 : 0)
            .offset(y: -110)
            .animation(.easeIn(duration: 1.0), value: titleVisible)
    }

    private var bottomStack: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 14) {
                promiseLine("Kein Konto.",       visible: p1Visible)
                promiseLine("Keine Cloud.",      visible: p2Visible)
                promiseLine("Keine Werbung.",    visible: p3Visible)
                promiseLine("Keine Telemetrie.", visible: p4Visible)
            }
            .padding(.bottom, 52)

            Beat1BreathingHint(visible: hintVisible)
                .padding(.bottom, 56)
        }
    }

    private func promiseLine(_ text: String, visible: Bool) -> some View {
        Text(text)
            .font(.system(size: 17, weight: .light))
            .foregroundStyle(.white.opacity(0.80))
            .tracking(0.2)
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 6)
            .animation(.easeOut(duration: 0.8), value: visible)
    }

    // MARK: - Choreography

    private func runChoreography() {
        startDate = .now
        scheduleAt(2.5) { titleVisible = true }
        scheduleAt(3.0) { p1Visible = true }
        scheduleAt(3.4) { p2Visible = true }
        scheduleAt(3.8) { p3Visible = true }
        scheduleAt(4.2) { p4Visible = true }
        scheduleAt(5.0) { hintVisible = true }
    }

    private func scheduleAt(_ delay: TimeInterval, _ block: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: block)
    }

    private func advance() {
        guard !swiped else { return }
        swiped = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            onAdvance()
        }
    }
}

/// Subtitle hint at the bottom of Beat 1. Two chained animations:
///   1. A 1.0 s smooth fade-in from 0 → 0.85 (no breath yet).
///   2. After the fade settles, a 4.0 s gentle breath between 0.85 and 0.55,
///      with the arrow slowly drifting right and back.
/// Mirrors the CSS keyframe trick from the HTML prototype that fixes the
/// "appears, disappears, comes back" first-cycle bug.
private struct Beat1BreathingHint: View {
    let visible: Bool

    @State private var entryOpacity: Double = 0
    @State private var breathFactor: Double = 1.0  // 1.0 → 0.65 → 1.0
    @State private var arrowOffset: CGFloat = 0
    @State private var hasStartedBreath = false

    var body: some View {
        HStack(spacing: 6) {
            Text("Zum Starten wischen")
            Text("→")
                .offset(x: arrowOffset)
        }
        .font(.system(size: 11, weight: .medium))
        .tracking(2.5)
        .textCase(.uppercase)
        .foregroundStyle(.white.opacity(entryOpacity * breathFactor))
        .onChange(of: visible) { _, isVisible in
            guard isVisible, !hasStartedBreath else { return }
            hasStartedBreath = true
            withAnimation(.easeOut(duration: 1.0)) {
                entryOpacity = 0.85
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                    breathFactor = 0.65
                }
                withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) {
                    arrowOffset = 6
                }
            }
        }
    }
}

#Preview {
    Beat1SternenwortView(onAdvance: {})
        .preferredColorScheme(.dark)
}
