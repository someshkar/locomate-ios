//
//  Haptics.swift
//  Locomate
//
//  Central haptics choreography, ported from SmartRail `src/lib/haptics.ts`.
//  Every tactile moment in the app goes through one of these so intensity stays
//  consistent. On iOS we prepare generators to keep latency low.
//

import UIKit

@MainActor
public enum Haptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let selectionGenerator = UISelectionFeedbackGenerator()
    private static let notification = UINotificationFeedbackGenerator()

    /// Warm the Taptic Engine ahead of an expected interaction.
    public static func prepare() {
        selectionGenerator.prepare()
        light.prepare()
    }

    /// Light tap — buttons, list rows.
    public static func tap() { selectionGenerator.selectionChanged() }

    /// Selection change — tabs, segmented controls, pickers.
    public static func select() { selectionGenerator.selectionChanged() }

    /// Sheet snapped to a detent, recenter, snap-carousel stops.
    public static func snap() { light.impactOccurred() }

    /// Confirmations — save, add to calendar, enable alerts.
    public static func confirm() { medium.impactOccurred() }

    /// Success completion of an async action.
    public static func success() { notification.notificationOccurred(.success) }

    /// Destructive or risky action (delete, revoke).
    public static func warn() { notification.notificationOccurred(.warning) }

    /// Action failed.
    public static func error() { notification.notificationOccurred(.error) }
}
