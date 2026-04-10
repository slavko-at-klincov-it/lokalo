//
//  ChatHaptics.swift
//  Lokal
//
//  Tiny haptic-feedback helper for the chat surfaces. UIKit's
//  `UIImpactFeedbackGenerator` should be `prepare()`d to avoid first-tap
//  latency, so we keep a single shared instance per intensity level.
//

import UIKit

@MainActor
enum ChatHaptics {
    /// Soft tap — drawer open / close, message bubble taps.
    private static let soft: UIImpactFeedbackGenerator = {
        let g = UIImpactFeedbackGenerator(style: .soft)
        g.prepare()
        return g
    }()

    /// Light tap — chat row selection, secondary actions.
    private static let light: UIImpactFeedbackGenerator = {
        let g = UIImpactFeedbackGenerator(style: .light)
        g.prepare()
        return g
    }()

    /// Medium tap — meaningful commits like "load this model now".
    private static let medium: UIImpactFeedbackGenerator = {
        let g = UIImpactFeedbackGenerator(style: .medium)
        g.prepare()
        return g
    }()

    static func drawerOpen() {
        soft.impactOccurred()
        soft.prepare()
    }

    static func drawerClose() {
        soft.impactOccurred()
        soft.prepare()
    }

    static func rowSelect() {
        light.impactOccurred()
        light.prepare()
    }

    static func confirmModelSwitch() {
        medium.impactOccurred()
        medium.prepare()
    }
}
