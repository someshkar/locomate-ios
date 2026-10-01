//
//  Preferences.swift
//  Locomate
//
//  App-level preferences: appearance, map daylight mode, and consent flags.
//  Dark preference is persisted INDEPENDENTLY of the map's day/night treatment.
//

import SwiftUI
import Observation

@Observable
public final class Preferences {
    public enum MapLighting: String, CaseIterable, Sendable {
        case automatic, day, night
        public var label: String {
            switch self {
            case .automatic: return "Automatic"
            case .day: return "Day"
            case .night: return "Night"
            }
        }
    }

    private let defaults: UserDefaults

    public var dark: Bool {
        didSet { defaults.set(dark, forKey: Keys.dark) }
    }

    public var mapLighting: MapLighting {
        didSet { defaults.set(mapLighting.rawValue, forKey: Keys.mapLighting) }
    }

    public var contributionsEnabled: Bool {
        didSet { defaults.set(contributionsEnabled, forKey: Keys.contributions) }
    }

    public var backgroundLocationEnabled: Bool {
        didSet { defaults.set(backgroundLocationEnabled, forKey: Keys.backgroundLocation) }
    }

    private enum Keys {
        static let dark = "locomote.dark"
        static let mapLighting = "locomote.mapLighting"
        static let contributions = "locomote.contributions"
        static let backgroundLocation = "locomote.backgroundLocation"
        static let consentVersion = "locomote.consentVersion"
        static let consentScope = "locomote.consentScope"
    }

    public init(defaults: UserDefaults = .standard, consentScope: String? = nil) {
        self.defaults = defaults
        // Dark-first, matching the product's default canvas.
        self.dark = defaults.object(forKey: Keys.dark) as? Bool ?? true
        let storedLighting = defaults.string(forKey: Keys.mapLighting)
        self.mapLighting = MapLighting(rawValue: storedLighting ?? "") ?? .automatic
        let activeScope = consentScope ?? {
            switch RailDataMode.resolve() {
            case .preview: return "preview"
            case .production(let url): return RailStorageScope.gateway(url)
            }
        }()
        let consentIsCurrent = defaults.integer(forKey: Keys.consentVersion) == Consent.version
            && defaults.string(forKey: Keys.consentScope) == activeScope
        let contributions = consentIsCurrent && defaults.bool(forKey: Keys.contributions)
        self.contributionsEnabled = contributions
        self.backgroundLocationEnabled = contributions && defaults.bool(forKey: Keys.backgroundLocation)
        if !consentIsCurrent {
            defaults.set(false, forKey: Keys.contributions)
            defaults.set(false, forKey: Keys.backgroundLocation)
            defaults.set(Consent.version, forKey: Keys.consentVersion)
            defaults.set(activeScope, forKey: Keys.consentScope)
        }
    }
}
