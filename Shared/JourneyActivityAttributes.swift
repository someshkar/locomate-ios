//
//  JourneyActivityAttributes.swift
//  Shared between the Locomate app and the LocomateWidgets extension.
//  ActivityKit requires the attribute/state types to be identical in both.
//

import ActivityKit
import Foundation

public struct JourneyActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var nextStation: String
        public var eta: String
        public var delayMinutes: Int?
        public var delayLabel: String
        public var distanceToNextKm: Double
        public var confidence: String
        public var updatedAt: Date

        public init(
            nextStation: String,
            eta: String,
            delayMinutes: Int?,
            delayLabel: String,
            distanceToNextKm: Double,
            confidence: String,
            updatedAt: Date = Date()
        ) {
            self.nextStation = nextStation
            self.eta = eta
            self.delayMinutes = delayMinutes
            self.delayLabel = delayLabel
            self.distanceToNextKm = distanceToNextKm
            self.confidence = confidence
            self.updatedAt = updatedAt
        }
    }

    public var trainNumber: String
    public var trainName: String
    public var destinationCode: String

    public init(trainNumber: String, trainName: String, destinationCode: String) {
        self.trainNumber = trainNumber
        self.trainName = trainName
        self.destinationCode = destinationCode
    }
}
