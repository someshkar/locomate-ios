//
//  UIKit.swift
//  Locomate
//
//  Core UI primitives, ported from SmartRail `src/components/ui/*`:
//  Card, StatusPill, SectionHeader, Stat, Button, ListRow, EmptyState, Skeleton.
//

import SwiftUI

// MARK: - Card

public struct Card<Content: View>: View {
    @Environment(\.locomoteColors) private var colors
    public let content: () -> Content

    public init(@ViewBuilder content: @escaping () -> Content) { self.content = content }

    public var body: some View {
        content()
            .padding(Spacing.units(4))
            .background(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(colors.elevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(colors.borderSubtle, lineWidth: 0.75)
            )
    }
}

// MARK: - Status pill

public struct StatusPill: View {
    @Environment(\.locomoteColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    public let label: String
    public let kind: StatusKind
    public let onGlass: Bool
    public let pulsing: Bool

    public init(label: String, kind: StatusKind, onGlass: Bool = false, pulsing: Bool = false) {
        self.label = label
        self.kind = kind
        self.onGlass = onGlass
        self.pulsing = pulsing
    }

    private var pair: StatusPair { colors.pair(for: kind) }

    public var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(pair.fg)
                .frame(width: 6, height: 6)
                .scaleEffect(pulse && pulsing ? 1.35 : 1)
                .opacity(pulse && pulsing ? 0.7 : 1)
            Text(label)
                .font(LocomateFont.micro)
                .monospacedDigit()
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(pair.fg)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            if onGlass {
                GlassSurface(cornerRadius: Radius.pill)
            } else {
                Capsule(style: .continuous).fill(pair.bg)
            }
        }
        .onAppear {
            guard pulsing, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}

// MARK: - Section header

public struct SectionHeader<Trailing: View>: View {
    @Environment(\.locomoteColors) private var colors
    public let eyebrow: String?
    public let title: String
    public let pageHeading: PageHeadingStyle?
    public let meta: String?
    public let trailing: () -> Trailing

    public init(
        eyebrow: String? = nil,
        title: String,
        pageHeading: PageHeadingStyle? = nil,
        meta: String? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.pageHeading = pageHeading
        self.meta = meta
        self.trailing = trailing
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                if let eyebrow {
                    Text(eyebrow).eyebrow(colors.textTertiary)
                }
                if let pageHeading {
                    Text(title).pageHeading(pageHeading)
                        .foregroundStyle(colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(title)
                        .font(LocomateFont.title)
                        .tracking(-1.2)
                        .foregroundStyle(colors.textPrimary)
                }
                if let meta {
                    Text(meta)
                        .font(LocomateFont.caption)
                        .foregroundStyle(colors.textSecondary)
                }
            }
            Spacer(minLength: Spacing.units(3))
            trailing()
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Stat

public struct Stat: View {
    @Environment(\.locomoteColors) private var colors
    public let label: String
    public let value: String
    public let unit: String?

    public init(label: String, value: String, unit: String? = nil) {
        self.label = label
        self.value = value
        self.unit = unit
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).eyebrow(colors.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(LocomateFont.timeLarge)
                    .monospacedDigit()
                    .foregroundStyle(colors.textPrimary)
                    .contentTransition(.numericText())
                if let unit {
                    Text(unit)
                        .font(LocomateFont.caption)
                        .foregroundStyle(colors.textTertiary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value) \(unit ?? "")")
    }
}

// MARK: - Button

public struct LocomateButton: View {
    @Environment(\.locomoteColors) private var colors
    public enum Style { case primary, secondary, plain }

    public let title: String
    public let systemImage: String?
    public let style: Style
    public let fullWidth: Bool
    public let action: () -> Void

    public init(
        _ title: String,
        systemImage: String? = nil,
        style: Style = .primary,
        fullWidth: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.style = style
        self.fullWidth = fullWidth
        self.action = action
    }

    public var body: some View {
        ScaleButton(accessibilityLabel: title, action: action) {
            HStack(spacing: 8) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title).font(LocomateFont.bodyStrong)
            }
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.horizontal, Spacing.units(5))
            .padding(.vertical, 14)
            .foregroundStyle(style == .primary ? colors.onAccent : colors.textPrimary)
            .background(background)
        }
    }

    @ViewBuilder private var background: some View {
        switch style {
        case .primary:
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(colors.accentBase)
        case .secondary:
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(colors.raised)
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(colors.borderSubtle, lineWidth: 0.75))
        case .plain:
            Color.clear
        }
    }
}

// MARK: - List row

public struct ListRow<Trailing: View>: View {
    @Environment(\.locomoteColors) private var colors
    public let icon: String?
    public let title: String
    public let meta: String?
    public let onPress: (() -> Void)?
    public let trailing: () -> Trailing

    public init(
        icon: String? = nil,
        title: String,
        meta: String? = nil,
        onPress: (() -> Void)? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.icon = icon
        self.title = title
        self.meta = meta
        self.onPress = onPress
        self.trailing = trailing
    }

    public var body: some View {
        let row = HStack(spacing: Spacing.units(3)) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 19))
                    .foregroundStyle(colors.accentBase)
                    .frame(width: 24)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(LocomateFont.bodyStrong).foregroundStyle(colors.textPrimary)
                if let meta {
                    Text(meta).font(LocomateFont.caption).foregroundStyle(colors.textSecondary)
                }
            }
            Spacer(minLength: Spacing.units(3))
            trailing()
        }
        .padding(.horizontal, Spacing.units(4))
        .padding(.vertical, Spacing.units(3.5))
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(colors.elevated))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(colors.borderSubtle, lineWidth: 0.75))

        if let onPress {
            ScaleButton(accessibilityLabel: title, action: onPress) { row }
        } else {
            row
        }
    }
}

// MARK: - Empty state

public struct EmptyState: View {
    @Environment(\.locomoteColors) private var colors
    public let icon: String
    public let title: String
    public let message: String
    public let actionTitle: String?
    public let onAction: (() -> Void)?

    public init(icon: String, title: String, body: String, actionTitle: String? = nil, onAction: (() -> Void)? = nil) {
        self.icon = icon; self.title = title; self.message = body
        self.actionTitle = actionTitle; self.onAction = onAction
    }

    public var body: some View {
        VStack(spacing: Spacing.units(4)) {
            Image(systemName: icon)
                .font(.system(size: 26))
                .foregroundStyle(colors.accentBase)
            VStack(spacing: Spacing.units(2)) {
                Text(title).font(LocomateFont.headline).foregroundStyle(colors.textPrimary)
                Text(message)
                    .font(LocomateFont.body)
                    .foregroundStyle(colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            if let actionTitle, let onAction {
                LocomateButton(actionTitle, style: .secondary, action: onAction)
            }
        }
        .padding(Spacing.units(7))
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Stagger-in

/// Fade + rise entrance with a capped stagger, ported from `StaggerIn.tsx`.
public struct StaggerIn<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    public let index: Int
    public let step: Double
    public let content: () -> Content

    @State private var appeared = false

    public init(index: Int, step: Double = Motion.Stagger.list, @ViewBuilder content: @escaping () -> Content) {
        self.index = index; self.step = step; self.content = content
    }

    public var body: some View {
        content()
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)
            .onAppear {
                guard !reduceMotion else { appeared = true; return }
                withAnimation(Motion.card.delay(Motion.staggerDelay(index: index, step: step))) {
                    appeared = true
                }
            }
    }
}
