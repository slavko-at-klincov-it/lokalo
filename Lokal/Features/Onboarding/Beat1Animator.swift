//
//  Beat1Animator.swift
//  Lokalo
//
//  Stateful particle system for Beat 1 (Sternenwort). Mirrors the JS
//  prototype in `onboarding-preview/beat1_sternenwort.html` exactly:
//  38 particles drift in from the screen edges and gather into a brain-blob
//  ring around `(W/2, H/2 - 110)` using the original V2 exponential-decay
//  motion. Held by `@State` inside `Beat1SternenwortView` and stepped from
//  inside the `TimelineView` / `Canvas` draw closure.
//

import Foundation
import CoreGraphics

final class Beat1Animator {
    struct Particle {
        var x: Double
        var y: Double
        let tx: Double
        let ty: Double
        let size: Double
        var opacity: Double
        let targetOpacity: Double
        let startTime: Double
        let gatherDelay: Double
    }

    private(set) var particles: [Particle] = []
    private var lastSimTime: Double = -1
    private var lastSize: CGSize = .zero

    /// Advance the simulation to the given absolute time. Idempotent for
    /// the same time value, so it's safe to call from inside a Canvas closure
    /// that may be re-evaluated multiple times per frame.
    func step(time: Double, size: CGSize) {
        if particles.isEmpty || size != lastSize {
            initialize(in: size)
            lastSize = size
            lastSimTime = -1
        }
        if lastSimTime < 0 {
            lastSimTime = time
            return
        }
        // Convert elapsed real time to integer 60 Hz frames so the simulation
        // is independent of the display refresh rate.
        let frames = max(0, min(8, Int(((time - lastSimTime) * 60.0).rounded())))
        for _ in 0..<frames {
            advanceOneFrame(at: time)
        }
        lastSimTime = time
    }

    private func advanceOneFrame(at time: Double) {
        for i in particles.indices {
            if time > particles[i].startTime {
                particles[i].opacity += (particles[i].targetOpacity - particles[i].opacity) * 0.06
            }
            if time > particles[i].gatherDelay {
                particles[i].x += (particles[i].tx - particles[i].x) * 0.05
                particles[i].y += (particles[i].ty - particles[i].y) * 0.05
            }
        }
    }

    private func initialize(in size: CGSize) {
        let cx = size.width / 2
        // Brain center is pulled up by 110 pt to leave room for the four
        // promises and the swipe hint underneath the constellation.
        let cy = size.height / 2 - 110
        var result: [Particle] = []
        for i in 0..<38 {
            let edge = i % 4
            var sx: Double = 0
            var sy: Double = 0
            switch edge {
            case 0: sx = -50;                  sy = .random(in: 0...size.height)
            case 1: sx = size.width + 50;      sy = .random(in: 0...size.height)
            case 2: sx = .random(in: 0...size.width); sy = -50
            default: sx = .random(in: 0...size.width); sy = size.height + 50
            }
            let angle = Double(i) / 38.0 * 2 * .pi
            let r = 70 + Double.random(in: 0...65)
            let tx = cx + cos(angle) * r
            let ty = cy + sin(angle) * r * 0.85
            result.append(Particle(
                x: sx, y: sy, tx: tx, ty: ty,
                size: 1.6 + .random(in: 0...2),
                opacity: 0,
                targetOpacity: 0.55 + .random(in: 0...0.45),
                startTime: .random(in: 0...0.5),
                gatherDelay: 1.1 + .random(in: 0...0.4)
            ))
        }
        particles = result
    }
}
