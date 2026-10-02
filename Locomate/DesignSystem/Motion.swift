//
//  Motion.swift
//  Locomate
//
//  Motion presets — physics-first animation language, ported from
//  SmartRail `src/theme/motion.ts`.
//
//  Rules preserved:
//  - Springs for anything the user can interrupt (sheets, cards, presses).
//  - Timings for state fades and value morphs.
//  - Every consumer must respect Reduce Motion: replace motion with an
//    `instant` crossfade. Use `Motion.animation(_:reduceMotion:)`.
//

import SwiftUI

public enum Motion {
    // MARK: Springs
    //
    // SwiftUI uses (response, dampingFraction). The source presets are
    // (damping, stiffness, mass); these are calibrated near-equivalents.
    // `sheet` is critically damped — motion you barely notice, just mass.

    /// Bottom sheets — critically damped, glides to the detent with zero bounce.
    public static let sheet = Animation.spring(response: 0.36, dampingFraction: 0.86)
    /// Card presses and entrances — firm, immediate, settles fast.
    public static let card = Animation.spring(response: 0.28, dampingFraction: 0.78)
    /// Toggles, pills, small UI — quick and dead (no wobble).
    public static let snappy = Animation.spring(response: 0.24, dampingFraction: 0.74)
    /// Large surfaces: tab bar, push transitions — slow, heavy, smooth.
    public static let gentle = Animation.spring(response: 0.42, dampingFraction: 0.88)
    /// Small glass controls track selection quickly, without elastic wobble.
    public static let selection = Animation.spring(response: 0.26, dampingFraction: 0.76)

    // MARK: Timings (seconds; source is ms)
    public enum Duration {
        public static let instant: Double = 0.110
        public static let fast: Double = 0.180
        public static let normal: Double = 0.260
        public static let slow: Double = 0.400
    }

    public static let fadeInstant = Animation.linear(duration: Duration.instant)
    public static let fadeFast = Animation.easeOut(duration: Duration.fast)
    public static let fadeNormal = Animation.easeOut(duration: Duration.normal)
    public static let fadeSlow = Animation.easeInOut(duration: Duration.slow)

    // MARK: Stagger
    /// Delay between items in staggered entrances (seconds).
    public enum Stagger {
        public static let list: Double = 0.045
        public static let section: Double = 0.070
    }
    /// Max items that participate in a staggered entrance; rest appear instantly.
    public static let staggerCap = 8

    /// Respect Reduce Motion by substituting an instant crossfade.
    public static func animation(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? fadeInstant : animation
    }

    /// Staggered entrance delay, capped like the source implementation.
    public static func staggerDelay(index: Int, step: Double = Stagger.list) -> Double {
        index < staggerCap ? Double(index) * step : 0
    }
}

/// Spring tuning for interactive (drag-released) surfaces.
public struct SpringSpec: Sendable {
    public let response: Double
    public let dampingFraction: Double
    public init(response: Double, dampingFraction: Double) {
        self.response = response
        self.dampingFraction = dampingFraction
    }
    public var animation: Animation { .spring(response: response, dampingFraction: dampingFraction) }
}
