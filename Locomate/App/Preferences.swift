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
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Dark-first, matching the product's default canvas.
        self.dark = defaults.object(forKey: Keys.dark) as? Bool ?? true
        let storedLighting = defaults.string(forKey: Keys.mapLighting)
        self.mapLighting = MapLighting(rawValue: storedLighting ?? "") ?? .automatic
        self.contributionsEnabled = defaults.bool(forKey: Keys.contributions)
        self.backgroundLocationEnabled = defaults.bool(forKey: Keys.backgroundLocation)
    }
}
