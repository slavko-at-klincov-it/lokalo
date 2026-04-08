//
//  V4_Tokens.swift
//  Lokalo · First-launch concept #4
//
//  CONCEPT — "Tokens" (The Tokens)
//  ────────────────────────────────
//  Recreates the visual language of an LLM emitting tokens. Small text
//  capsules — German + English fragments + special model tokens — stream
//  upward from the bottom of the screen in monospaced type. They slow
//  down, dim, and the title "Lokalo" emerges from the stream like a
//  final emitted token. A meta moment: the very thing the app does *is*
//  the welcome.
//
//  TONE — Cyberpunk minimal · Linear typography poster · tokenizer viz.
//  RUNTIME — ~7 seconds, fully automatic.
//

import SwiftUI

struct OnboardingV4Tokens: View {
    let onFinish: () -> Void

    @State private var tokens: [TokenItem] = []
    @State private var titleScale: CGFloat = 0.7
    @State private var titleOpacity: Double = 0
    @State private var subtitleOpacity: Double = 0
    @State private var rootOpacity: Double = 1

    private let tokenPool: [String] = [
        "Hal", "lo", " auf", " dei", "nem", " iPh", "one",
        " ohne", " Cloud", " ein", " lokal", "es", " Mo", "dell",
        " für", " dich", "Hi", " there", " no", " server",
        "•", "<|im_start|>", "<|eot_id|>", "<|end|>",
        "tokens", "_per_", "second", " 84", " stream", "ing",
        "Lo", "kal", "o", "•"
    ]

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [Color(white: 0.05), .black],
                center: .center,
                startRadius: 100,
                endRadius: 700
            )
            .ignoresSafeArea()

            ForEach(tokens) { token in
                Text(token.text)
                    .font(.system(size: token.fontSize, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(token.opacity))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(token.bgOpacity))
                    )
                    .position(token.position)
            }

            VStack(spacing: 14) {
                Text("Lokalo")
                    .font(.system(size: 68, weight: .black, design: .default))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, Color(white: 0.7)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .tracking(-2)
                    .scaleEffect(titleScale)
                    .opacity(titleOpacity)

                Text("tokens bleiben hier.")
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                    .tracking(2)
                    .opacity(subtitleOpacity)
            }
        }
        .opacity(rootOpacity)
        .onAppear { choreograph() }
    }

    private func choreograph() {
        let screenW = UIScreen.main.bounds.width
        let screenH = UIScreen.main.bounds.height

        // Spawn 70 tokens streaming upward over ~3 s
        for i in 0..<70 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.045) {
                let token = TokenItem(
                    text: tokenPool.randomElement() ?? "•",
                    position: CGPoint(
                        x: .random(in: 40...(screenW - 40)),
                        y: screenH + 30
                    ),
                    fontSize: .random(in: 11...18),
                    opacity: 0.0,
                    bgOpacity: 0.04
                )
                tokens.append(token)
                let id = token.id

                withAnimation(.linear(duration: 2.0)) {
                    if let idx = tokens.firstIndex(where: { $0.id == id }) {
                        tokens[idx].position.y = -30
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    withAnimation(.easeIn(duration: 0.4)) {
                        if let idx = tokens.firstIndex(where: { $0.id == id }) {
                            tokens[idx].opacity = 0.85
                        }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        withAnimation(.easeOut(duration: 1.0)) {
                            if let idx = tokens.firstIndex(where: { $0.id == id }) {
                                tokens[idx].opacity = 0.0
                            }
                        }
                    }
                }
            }
        }

        // Title appears mid-stream
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.3) {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.65)) {
                titleScale = 1.0
                titleOpacity = 1.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(.easeOut(duration: 0.8)) { subtitleOpacity = 1.0 }
            }
        }

        // Hold then dissolve
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
            withAnimation(.easeOut(duration: 0.9)) {
                titleOpacity = 0
                subtitleOpacity = 0
                rootOpacity = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) { onFinish() }
        }
    }

    struct TokenItem: Identifiable {
        let id = UUID()
        var text: String
        var position: CGPoint
        var fontSize: CGFloat
        var opacity: Double
        var bgOpacity: Double
    }
}

#Preview {
    OnboardingV4Tokens(onFinish: {})
        .preferredColorScheme(.dark)
}
