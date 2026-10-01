//
//  PressableScale.swift
//  Locomate
//
//  The shared press micro-interaction, ported from SmartRail
//  `src/components/ui/PressableScale.tsx`.
//  Scale to 0.97 + fade to 0.85 with a snappy spring; fires a light haptic.
//
//  Implemented with a `ButtonStyle` (the canonical SwiftUI press-state hook).
//  Do NOT use `onLongPressGesture` here: with `minimumDuration: 0` it fires
//  immediately and swallows the button's own tap action.
//

import SwiftUI

/// Applies the scale/fade press treatment to any view.
public struct PressScaleStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    public var haptic: Bool = true

    public init(haptic: Bool = true) { self.haptic = haptic }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.97 : 1))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(Motion.animation(Motion.snappy, reduceMotion: reduceMotion),
                       value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed && haptic { Haptics.tap() }
            }
    }
}

public extension ButtonStyle where Self == PressScaleStyle {
    static var pressScale: PressScaleStyle { PressScaleStyle() }
    static func pressScale(haptic: Bool) -> PressScaleStyle { PressScaleStyle(haptic: haptic) }
}

/// A button with the shared press micro-interaction and accessibility semantics.
public struct ScaleButton<Label: View>: View {
    public let accessibilityLabel: String?
    public let haptic: Bool
    public let action: () -> Void
    public let label: () -> Label

    public init(
        accessibilityLabel: String? = nil,
        haptic: Bool = true,
        action: @escaping () -> Void,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.accessibilityLabel = accessibilityLabel
        self.haptic = haptic
        self.action = action
        self.label = label
    }

    public var body: some View {
        Button(action: action) {
            label()
        }
        .buttonStyle(PressScaleStyle(haptic: haptic))
        .accessibilityLabel(accessibilityLabel ?? "")
        .accessibilityAddTraits(.isButton)
    }
}

/// Non-button tappable wrapper (for rows that already render their own chrome).
public struct PressableScale<Content: View>: View {
    public let action: () -> Void
    public let haptic: Bool
    public let content: () -> Content

    public init(
        haptic: Bool = true,
        action: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.haptic = haptic
        self.action = action
        self.content = content
    }

    public var body: some View {
        Button(action: action) {
            content()
        }
        .buttonStyle(PressScaleStyle(haptic: haptic))
    }
}
