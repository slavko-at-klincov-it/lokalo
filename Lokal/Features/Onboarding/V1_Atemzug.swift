//
//  V1_Atemzug.swift
//  Lokalo · First-launch concept #1
//
//  CONCEPT — "Atemzug" (The Breath)
//  ─────────────────────────────────
//  Confidence by absence. A single white dot breathes against pure black.
//  After a few breaths it dissolves into a single sentence in classical
//  serif type: "Alles bleibt hier." Then everything fades out into the
//  chat. No buttons. No logos. No progress bars. The opposite of typical
//  onboarding — it trusts the user to figure out the obvious.
//
//  TONE — Apple "Hello." moments. Things 3 launch. Bear writer.
//  RUNTIME — ~9 seconds, fully automatic.
//

import SwiftUI

struct OnboardingV1Atemzug: View {
    let onFinish: () -> Void

    @State private var dotScale: CGFloat = 1.0
    @State private var dotOpacity: Double = 0.0
    @State private var textOpacity: Double = 0.0
    @State private var rootOpacity: Double = 1.0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Circle()
                .fill(Color.white)
                .frame(width: 14, height: 14)
                .scaleEffect(dotScale)
                .opacity(dotOpacity)
                .blur(radius: 1)
                .shadow(color: .white.opacity(0.45), radius: 36)

            Text("Alles bleibt hier.")
                .font(.system(size: 30, weight: .light, design: .serif))
                .foregroundStyle(.white)
                .tracking(0.6)
                .opacity(textOpacity)
        }
        .opacity(rootOpacity)
        .onAppear { choreograph() }
    }

    private func choreograph() {
        // Dot fades in
        withAnimation(.easeInOut(duration: 1.2)) { dotOpacity = 1.0 }

        // Dot breathes (continuous)
        withAnimation(
            .easeInOut(duration: 2.2)
            .repeatForever(autoreverses: true)
        ) {
            dotScale = 2.6
        }

        // 5.5 s in: dot dissolves
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.5) {
            withAnimation(.easeOut(duration: 0.9)) { dotOpacity = 0 }
        }

        // 6.0 s in: text fades in
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
            withAnimation(.easeIn(duration: 1.6)) { textOpacity = 1.0 }
        }

        // 9.0 s in: everything fades out
        DispatchQueue.main.asyncAfter(deadline: .now() + 9.0) {
            withAnimation(.easeOut(duration: 0.9)) { rootOpacity = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) { onFinish() }
        }
    }
}

#Preview {
    OnboardingV1Atemzug(onFinish: {})
        .preferredColorScheme(.dark)
}
