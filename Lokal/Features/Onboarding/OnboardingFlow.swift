//
//  OnboardingFlow.swift
//  Lokalo
//
//  Two-beat first-launch coordinator. Beat 1 (Sternenwort + privacy promises)
//  slides out to the left when the user taps or swipes; Beat 2 (settings
//  cards) slides in from the right. When Beat 2 finishes ("Loslegen"), the
//  flow calls `onComplete` so the parent (LokalApp) can flip the
//  `hasCompletedOnboarding` flag and reveal RootView.
//

import SwiftUI

struct OnboardingFlow: View {
    let onComplete: () -> Void

    @State private var currentBeat: Int = 1

    var body: some View {
        ZStack {
            if currentBeat == 1 {
                Beat1SternenwortView {
                    withAnimation(.easeInOut(duration: 0.55)) {
                        currentBeat = 2
                    }
                }
                .transition(.asymmetric(
                    insertion: .opacity,
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            } else {
                Beat2EinstellungenView {
                    onComplete()
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .opacity
                ))
            }
        }
        .ignoresSafeArea()
    }
}

#Preview {
    OnboardingFlow(onComplete: {})
        .preferredColorScheme(.dark)
}
