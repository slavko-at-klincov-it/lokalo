//
//  V5_Lichtschalter.swift
//  Lokalo · First-launch concept #5
//
//  CONCEPT — "Lichtschalter" (Light Switch)
//  ─────────────────────────────────────────
//  Cinematic. Three short statements appear one after another in pure
//  black silence — "Lokal." / "Privat." / "Dein iPhone." — each with a
//  soft haptic. They merge horizontally into a single brand mark
//  "Lokalo". A pulsing hint invites a tap. On tap (or auto after a few
//  seconds) the screen flashes white and reveals the chat — like
//  flipping a light switch in a quiet room.
//
//  TONE — Apple keynote intro · quiet luxury · the moment before a movie.
//  RUNTIME — ~9 seconds auto, or earlier on tap.
//

import SwiftUI
import UIKit

struct OnboardingV5Lichtschalter: View {
    let onFinish: () -> Void

    @State private var word1Opacity: Double = 0
    @State private var word2Opacity: Double = 0
    @State private var word3Opacity: Double = 0
    @State private var wordsOffset: CGFloat = 0
    @State private var lokaloOpacity: Double = 0
    @State private var lokaloScale: CGFloat = 0.85
    @State private var hintOpacity: Double = 0
    @State private var flashOpacity: Double = 0
    @State private var rootOpacity: Double = 1
    @State private var canTap = false

    private let haptic = UIImpactFeedbackGenerator(style: .soft)
    private let confirmHaptic = UIImpactFeedbackGenerator(style: .medium)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Phase 1: three stacked statements
            VStack(spacing: 32) {
                Text("Lokal.")
                    .opacity(word1Opacity)
                Text("Privat.")
                    .opacity(word2Opacity)
                Text("Dein iPhone.")
                    .opacity(word3Opacity)
            }
            .font(.system(size: 38, weight: .ultraLight, design: .serif))
            .foregroundStyle(.white)
            .tracking(0.4)
            .offset(y: wordsOffset)

            // Phase 2: merged title
            VStack(spacing: 22) {
                Text("Lokalo")
                    .font(.system(size: 78, weight: .ultraLight, design: .serif))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, Color(white: 0.82)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .tracking(-1)
                    .scaleEffect(lokaloScale)
                    .opacity(lokaloOpacity)

                Text("zum Starten tippen")
                    .font(.system(size: 12, weight: .regular, design: .default))
                    .foregroundStyle(.white.opacity(0.42))
                    .tracking(2.5)
                    .textCase(.uppercase)
                    .opacity(hintOpacity)
            }

            // Flash overlay
            Color.white
                .opacity(flashOpacity)
                .ignoresSafeArea()
        }
        .opacity(rootOpacity)
        .contentShape(Rectangle())
        .onTapGesture {
            if canTap { triggerFlash() }
        }
        .onAppear {
            haptic.prepare()
            confirmHaptic.prepare()
            choreograph()
        }
    }

    private func choreograph() {
        // Word 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            haptic.impactOccurred(intensity: 0.4)
            withAnimation(.easeOut(duration: 0.8)) { word1Opacity = 1 }
        }

        // Word 2
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) {
            haptic.impactOccurred(intensity: 0.5)
            withAnimation(.easeOut(duration: 0.8)) { word2Opacity = 1 }
        }

        // Word 3
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.9) {
            haptic.impactOccurred(intensity: 0.6)
            withAnimation(.easeOut(duration: 0.8)) { word3Opacity = 1 }
        }

        // Words fade out, title comes in
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.6) {
            withAnimation(.easeInOut(duration: 0.9)) {
                word1Opacity = 0
                word2Opacity = 0
                word3Opacity = 0
                wordsOffset = -40
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                confirmHaptic.impactOccurred(intensity: 0.8)
                withAnimation(.spring(response: 0.85, dampingFraction: 0.7)) {
                    lokaloScale = 1.0
                    lokaloOpacity = 1.0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    withAnimation(
                        .easeInOut(duration: 1.4)
                        .repeatForever(autoreverses: true)
                    ) {
                        hintOpacity = 0.85
                    }
                    canTap = true
                }
            }
        }

        // Auto-advance after 9.5 s if no tap
        DispatchQueue.main.asyncAfter(deadline: .now() + 9.5) {
            if canTap { triggerFlash() }
        }
    }

    private func triggerFlash() {
        canTap = false
        confirmHaptic.impactOccurred(intensity: 1.0)
        withAnimation(.easeIn(duration: 0.22)) { flashOpacity = 1.0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            withAnimation(.easeOut(duration: 0.5)) { rootOpacity = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { onFinish() }
        }
    }
}

#Preview {
    OnboardingV5Lichtschalter(onFinish: {})
        .preferredColorScheme(.dark)
}
