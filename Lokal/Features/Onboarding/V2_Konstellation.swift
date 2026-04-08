//
//  V2_Konstellation.swift
//  Lokalo · First-launch concept #2
//
//  CONCEPT — "Konstellation" (The Constellation)
//  ──────────────────────────────────────────────
//  A field of soft points scattered at the edges of the screen drifts
//  inward and gathers into a brain-like blob. Connecting lines appear
//  between nearby points. The user is literally watching a "thinking
//  thing" assemble itself inside their phone. A short caption types out
//  in monospaced sans, then everything dissolves outward.
//
//  TONE — Star Walk · Brilliant night mode · Vera Molnár generative art.
//  RUNTIME — ~9 seconds, fully automatic.
//

import SwiftUI

struct OnboardingV2Konstellation: View {
    let onFinish: () -> Void

    @State private var points: [Particle] = []
    @State private var phase: Phase = .scatter
    @State private var typedText: String = ""
    @State private var textOpacity: Double = 0
    @State private var rootOpacity: Double = 1

    enum Phase { case scatter, gather, dissolve }

    private let target = "Ein Gehirn,\ndas nicht spricht.\nAußer mit dir."

    var body: some View {
        ZStack {
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

            GeometryReader { geo in
                ZStack {
                    // Connection lines
                    Canvas { ctx, _ in
                        guard phase == .gather else { return }
                        for i in 0..<points.count {
                            for j in (i + 1)..<points.count {
                                let p1 = points[i]
                                let p2 = points[j]
                                let dx = p1.position.x - p2.position.x
                                let dy = p1.position.y - p2.position.y
                                let dist = sqrt(dx * dx + dy * dy)
                                if dist < 95 {
                                    var path = Path()
                                    path.move(to: p1.position)
                                    path.addLine(to: p2.position)
                                    ctx.stroke(
                                        path,
                                        with: .color(.white.opacity(0.18 * (1 - dist / 95))),
                                        lineWidth: 0.6
                                    )
                                }
                            }
                        }
                    }

                    // Particles
                    ForEach(points) { p in
                        Circle()
                            .fill(Color.white)
                            .frame(width: p.size, height: p.size)
                            .position(p.position)
                            .opacity(p.opacity)
                            .blur(radius: 0.4)
                    }

                    // Caption
                    VStack {
                        Spacer()
                        Text(typedText)
                            .font(.system(size: 17, weight: .regular, design: .default))
                            .foregroundStyle(.white.opacity(0.86))
                            .multilineTextAlignment(.center)
                            .tracking(0.4)
                            .lineSpacing(8)
                            .opacity(textOpacity)
                            .padding(.bottom, 110)
                            .frame(maxWidth: .infinity)
                    }
                }
                .onAppear {
                    initialize(in: geo.size)
                    choreograph(in: geo.size)
                }
            }
        }
        .opacity(rootOpacity)
    }

    private func initialize(in size: CGSize) {
        points = (0..<38).map { i in
            let edge = i % 4
            let pos: CGPoint
            switch edge {
            case 0: pos = CGPoint(x: -50, y: .random(in: 0...size.height))
            case 1: pos = CGPoint(x: size.width + 50, y: .random(in: 0...size.height))
            case 2: pos = CGPoint(x: .random(in: 0...size.width), y: -50)
            default: pos = CGPoint(x: .random(in: 0...size.width), y: size.height + 50)
            }
            return Particle(position: pos, size: .random(in: 1.6...3.6), opacity: 0)
        }
    }

    private func choreograph(in size: CGSize) {
        // Fade in scattered points
        for i in 0..<points.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + .random(in: 0...0.5)) {
                withAnimation(.easeIn(duration: 0.7)) {
                    if i < points.count {
                        points[i].opacity = .random(in: 0.55...1.0)
                    }
                }
            }
        }

        // Gather into a brain blob
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            phase = .gather
            let center = CGPoint(x: size.width / 2, y: size.height / 2 - 60)
            for i in 0..<points.count {
                let angle = Double(i) / Double(points.count) * 2 * .pi
                let radius = CGFloat.random(in: 70...135)
                let target = CGPoint(
                    x: center.x + cos(angle) * radius,
                    y: center.y + sin(angle) * radius * 0.82
                )
                withAnimation(
                    .interpolatingSpring(stiffness: 14, damping: 6)
                    .delay(.random(in: 0...0.4))
                ) {
                    points[i].position = target
                }
            }
        }

        // Type the caption
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation(.easeIn(duration: 0.6)) { textOpacity = 1.0 }
            let chars = Array(target)
            for (idx, ch) in chars.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(idx) * 0.045) {
                    typedText.append(ch)
                }
            }
        }

        // Dissolve
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) {
            phase = .dissolve
            withAnimation(.easeOut(duration: 0.9)) { textOpacity = 0 }
            for i in 0..<points.count {
                let outDir: CGFloat = i.isMultiple(of: 2) ? 1 : -1
                withAnimation(.easeIn(duration: 1.0).delay(Double(i) * 0.012)) {
                    points[i].opacity = 0
                    points[i].position.y += outDir * 200
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation(.easeOut(duration: 0.4)) { rootOpacity = 0 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { onFinish() }
            }
        }
    }

    struct Particle: Identifiable {
        let id = UUID()
        var position: CGPoint
        var size: CGFloat
        var opacity: Double
    }
}

#Preview {
    OnboardingV2Konstellation(onFinish: {})
        .preferredColorScheme(.dark)
}
