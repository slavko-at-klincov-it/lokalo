//
//  OnboardingFlow.swift
//  Lokalo
//
//  Two-beat first-launch coordinator with interactive paging.
//
//  Both beats live side-by-side in a horizontal HStack that tracks the
//  user's finger 1:1 during a drag — finger position maps directly to
//  screen position, iOS Home Screen style. On release past either a
//  25% distance threshold or a velocity-based flick, we spring-commit
//  to Beat 2 with a soft taptic impact. Below the threshold the drag
//  snaps back with a tighter spring.
//
//  A tap on Beat 1 still advances instantly via the same spring +
//  haptic combo, so drag and tap feel like the same gesture from the
//  user's side.
//
//  Beat 2 is terminal — the gesture early-returns while `currentBeat`
//  is non-zero, so swiping right on Beat 2 does nothing (no rubber-band
//  back to Beat 1). The paging gesture is installed as a
//  `simultaneousGesture` so controls inside the child beats (Beat 1's
//  tap-to-advance, Beat 2's toggles and model-picker menu) receive
//  their taps cleanly — the drag only activates once the user has
//  moved their finger past `minimumDistance`.
//

import SwiftUI

struct OnboardingFlow: View {
    let onComplete: () -> Void

    /// Settled page. 0 = Beat 1, 1 = Beat 2. Spring-animated on commit.
    @State private var currentBeat: Int = 0

    /// Live translation of the in-flight drag in points. Added to the
    /// base offset for 1:1 finger tracking. Clamped to `[-w, 0]` so the
    /// HStack never reveals empty space beyond Beat 2 or drags right
    /// of Beat 1. Animated back to 0 on gesture release.
    @State private var dragOffset: CGFloat = 0

    /// Precomputed taptic generator. `prepare()` warms up the hardware
    /// so the first impact fires with zero perceptible latency — without
    /// it, the first commit-thump has 80-200 ms of cold-start lag.
    private let commitHaptic = UIImpactFeedbackGenerator(style: .soft)

    // Tuning constants — pulled out so the feel is easy to adjust.
    private let minDragDistance: CGFloat = 10
    private let commitDistanceFraction: CGFloat = 0.25
    private let commitFlickDistance: CGFloat = 40
    private let commitFlickVelocity: CGFloat = -120
    private let hapticIntensity: CGFloat = 0.75

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let baseOffset = -CGFloat(currentBeat) * w

            ZStack {
                // Defense in depth — a persistent gradient behind the
                // HStack guarantees no single frame ever reveals the
                // white UIWindow background, even if a future edit
                // accidentally introduces a transition gap.
                persistentBackground

                HStack(spacing: 0) {
                    Beat1SternenwortView {
                        advanceWithHaptic()
                    }
                    .frame(width: w)

                    Beat2EinstellungenView(isActive: currentBeat == 1) {
                        onComplete()
                    }
                    .frame(width: w)
                }
                .frame(width: w * 2, alignment: .leading)
                .offset(x: baseOffset + dragOffset)
                .simultaneousGesture(pagingGesture(width: w))
            }
        }
        .ignoresSafeArea()
        // Force the entire onboarding subtree to render in dark mode,
        // regardless of the user's selected theme. The branded intro
        // experience is always the Lokalo dark-blue gradient, and this
        // locks Beat 2's `ThemedOnboardingBackground` (and all semantic
        // colors like `.primary`) to the dark variant so the swipe
        // transition from Beat 1 (hardcoded dark) never cuts through a
        // near-white `LightBackground`. The user's theme choice from
        // Beat 2's theme card still persists to AppStorage and takes
        // effect the moment RootView appears after "Loslegen".
        .environment(\.colorScheme, .dark)
        .onAppear { commitHaptic.prepare() }
    }

    // MARK: - Layers

    private var persistentBackground: some View {
        DarkBlueGradient()
    }

    // MARK: - Gesture

    /// Interactive paging gesture. Tracks the finger 1:1 while on
    /// Beat 1. Beat 2 is terminal — the guard short-circuits the
    /// gesture so nothing moves on a right-drag.
    private func pagingGesture(width w: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: minDragDistance, coordinateSpace: .local)
            .onChanged { value in
                guard currentBeat == 0 else { return }
                // Clamp to `[-w, 0]`:
                //   * Right-drags (>0) are dead — there's no page to
                //     the left of Beat 1.
                //   * Left-drags past `-w` would expose empty space to
                //     the right of Beat 2.
                dragOffset = max(-w, min(0, value.translation.width))
            }
            .onEnded { value in
                guard currentBeat == 0 else { return }
                let distance = value.translation.width
                // SwiftUI's DragGesture doesn't expose velocity directly;
                // the predicted-end delta is a decent proxy for how hard
                // the user flicked.
                let flickVelocity = value.predictedEndTranslation.width - value.translation.width

                let shouldCommit = distance < -w * commitDistanceFraction
                                 || (distance < -commitFlickDistance && flickVelocity < commitFlickVelocity)

                if shouldCommit {
                    commitToBeat2()
                } else {
                    snapBack()
                }
            }
    }

    // MARK: - State transitions

    private func commitToBeat2() {
        commitHaptic.impactOccurred(intensity: hapticIntensity)
        // `.interpolatingSpring(stiffness:damping:)` matches the curve
        // iOS uses for Home Screen page commits — slightly under-damped
        // so the motion has a tiny bit of follow-through, not a dead
        // mechanical stop.
        withAnimation(.interpolatingSpring(stiffness: 290, damping: 30)) {
            currentBeat = 1
            dragOffset = 0
        }
    }

    private func snapBack() {
        // A slightly tighter spring for the snap-back. The user
        // aborted the gesture, so we want to restore state quickly
        // without overshooting.
        withAnimation(.interpolatingSpring(stiffness: 340, damping: 28)) {
            dragOffset = 0
        }
    }

    /// Tap-to-advance path (no drag). Uses the exact same commit
    /// animation + haptic as a threshold-passing drag so both
    /// interactions feel identical from the user's side.
    private func advanceWithHaptic() {
        guard currentBeat == 0 else { return }
        commitHaptic.impactOccurred(intensity: hapticIntensity)
        withAnimation(.interpolatingSpring(stiffness: 290, damping: 30)) {
            currentBeat = 1
        }
    }
}

#Preview {
    OnboardingFlow(onComplete: {})
        .preferredColorScheme(.dark)
}
