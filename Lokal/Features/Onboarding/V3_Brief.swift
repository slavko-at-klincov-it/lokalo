//
//  V3_Brief.swift
//  Lokalo · First-launch concept #3
//
//  CONCEPT — "Brief von daheim" (Letter from Home)
//  ────────────────────────────────────────────────
//  A handwritten letter slides into view from the right at a slight
//  tilt. Cream paper, faint ruled lines, soft shadow. The text types
//  itself out in a cursive hand, line by line, as if Slavko is writing
//  it personally. Then the paper slides up out of view to reveal the
//  chat. Plays the analog/personal angle against the high-tech reality
//  of a 3 GB language model running on a phone.
//
//  TONE — Wes Anderson · Field Notes · pen pals · physical mail.
//  RUNTIME — ~10 seconds, fully automatic.
//

import SwiftUI

struct OnboardingV3Brief: View {
    let onFinish: () -> Void

    @State private var paperOffsetX: CGFloat = 700
    @State private var paperRotation: Double = 8
    @State private var typedText: String = ""
    @State private var rootOpacity: Double = 1

    private let letter = """
Hi.

Lokalo läuft komplett
auf deinem iPhone.

Kein Konto.
Keine Cloud.
Keine Werbung.

Falls dir das auch
wichtig ist —
los geht's.

— S.
"""

    var body: some View {
        ZStack {
            // Warm cream background
            LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.93, blue: 0.85),
                    Color(red: 0.91, green: 0.86, blue: 0.76)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Subtle paper grain
            Canvas { ctx, size in
                for _ in 0..<450 {
                    let x = CGFloat.random(in: 0...size.width)
                    let y = CGFloat.random(in: 0...size.height)
                    let r = CGFloat.random(in: 0.3...0.9)
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)),
                        with: .color(.brown.opacity(0.06))
                    )
                }
            }
            .ignoresSafeArea()
            .blendMode(.multiply)

            // The letter card
            ZStack {
                // Paper background
                Color(red: 0.99, green: 0.97, blue: 0.91)

                // Faint ruled lines
                VStack(spacing: 32) {
                    ForEach(0..<14, id: \.self) { _ in
                        Rectangle()
                            .fill(Color(red: 0.55, green: 0.45, blue: 0.45).opacity(0.10))
                            .frame(height: 0.5)
                    }
                }
                .padding(.top, 48)
                .padding(.horizontal, 12)

                // Top edge dashes
                VStack {
                    HStack(spacing: 6) {
                        ForEach(0..<14, id: \.self) { _ in
                            Rectangle()
                                .fill(Color.brown.opacity(0.18))
                                .frame(width: 8, height: 1)
                        }
                    }
                    .padding(.top, 14)
                    Spacer()
                }

                // Handwritten text
                VStack(alignment: .leading) {
                    Text(typedText)
                        .font(.custom("Bradley Hand", size: 26))
                        .foregroundStyle(Color(red: 0.18, green: 0.16, blue: 0.22))
                        .lineSpacing(6)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 32)
                .padding(.top, 56)
                .padding(.bottom, 32)
            }
            .frame(width: 320, height: 480)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .shadow(color: .black.opacity(0.20), radius: 32, x: 8, y: 18)
            .shadow(color: .black.opacity(0.10), radius: 5, x: 2, y: 4)
            .rotationEffect(.degrees(paperRotation))
            .offset(x: paperOffsetX)
        }
        .opacity(rootOpacity)
        .onAppear { choreograph() }
    }

    private func choreograph() {
        // Slide in
        withAnimation(.spring(response: 1.4, dampingFraction: 0.78)) {
            paperOffsetX = 0
            paperRotation = -2
        }

        // Type
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            let chars = Array(letter)
            for (idx, ch) in chars.enumerated() {
                let baseDelay = Double(idx) * 0.055
                let jitter = Double.random(in: 0...0.04)
                DispatchQueue.main.asyncAfter(deadline: .now() + baseDelay + jitter) {
                    typedText.append(ch)
                }
            }
        }

        // Slide out
        DispatchQueue.main.asyncAfter(deadline: .now() + 9.5) {
            withAnimation(.easeIn(duration: 0.9)) {
                paperOffsetX = -800
                paperRotation = -10
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
                withAnimation(.easeOut(duration: 0.4)) { rootOpacity = 0 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { onFinish() }
            }
        }
    }
}

#Preview {
    OnboardingV3Brief(onFinish: {})
}
