import Foundation

public struct PhysicalEvidence: Codable, Sendable {
    public let confidence: Double?
    public let source: String?
    public let recordedAt: Double?
    public let ageMs: Double?
    public let expiresAt: Double?
    public let freshness: String
}
public struct PhysicalRun: Codable, Sendable {
    public struct Station: Codable, Sendable { public let code: String; public let name: String }
    public struct Arrival: Codable, Sendable { public let scheduledAt: Double?; public let predictedAt: Double?; public let actualAt: Double? }
    public let runId: String
    public let trainNumber: String
    public let serviceDate: String
    public let status: String
    public let origin: Station
    public let destination: Station
    public let scheduledStartAt: Double
    public let scheduledEndAt: Double
    public let scheduledOutboundDepartureAt: Double?
    public let inboundTerminalArrival: Arrival
}
public struct PhysicalLink: Codable, Sendable {
    public let state: String
    public let reason: String
    public let evidence: PhysicalEvidence
    public let minimumServiceDurationMs: Double?
    public let serviceReadyAt: Double?
}
public struct PhysicalAssetChain: Codable, Sendable {
    public let kind: String
    public let assetType: String?
    public let state: String
    public let unavailableReason: String?
    public let assignmentEvidence: PhysicalEvidence
    public let previous: PhysicalRun?
    public let current: PhysicalRun?
    public let next: PhysicalRun?
    public let inboundLink: PhysicalLink
    public let outboundLink: PhysicalLink
}
public struct PhysicalChainResponse: Codable, Sendable {
    public let runId: String
    public let asOf: Double
    public let state: String
    public let rake: PhysicalAssetChain
    public let locomotive: PhysicalAssetChain
}
public struct PhysicalSightingInput: Codable, Sendable {
    public let assetKind: String
    public let identifier: String
    public let observedAt: Int64
    public let evidenceMethod: String
}
public struct PhysicalSightingRequest: Codable, Sendable {
    public struct ConsentEvidence: Codable, Sendable {
        public let evidenceId: String
        public let purpose = "community_observations"
        public let granted = true
        public let consentVersion: String
        public let noticeHash: String
        public let consentedAt: Int64
        private enum CodingKeys: String, CodingKey { case evidenceId, purpose, granted, consentVersion, noticeHash, consentedAt }
        public init(evidenceId: String, consentVersion: String, noticeHash: String, consentedAt: Int64) {
            self.evidenceId = evidenceId; self.consentVersion = consentVersion
            self.noticeHash = noticeHash; self.consentedAt = consentedAt
        }
        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            guard try values.decode(String.self, forKey: .purpose) == "community_observations",
                  try values.decode(Bool.self, forKey: .granted) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Equipment consent must explicitly grant community observations."))
            }
            evidenceId = try values.decode(String.self, forKey: .evidenceId)
            consentVersion = try values.decode(String.self, forKey: .consentVersion)
            noticeHash = try values.decode(String.self, forKey: .noticeHash)
            consentedAt = try values.decode(Int64.self, forKey: .consentedAt)
        }
    }
    public let sightings: [PhysicalSightingInput]
    public func validated() throws {
        guard (1...8).contains(sightings.count), (8...100).contains(consent.evidenceId.count),
              consent.consentVersion == String(Consent.version), consent.noticeHash == Consent.noticeHash,
              consent.consentedAt >= 0,
              Set(sightings.map { "\($0.assetKind):\($0.identifier)" }).count == sightings.count,
              sightings.allSatisfy({ item in
                  item.observedAt >= 0 && (item.assetKind == "locomotive"
                      ? item.evidenceMethod == "visual-number" && PhysicalSighting.locomotive(item.identifier) != nil
                      : item.assetKind == "coach" && item.evidenceMethod == "onboard-coach-plate" && PhysicalSighting.coaches(item.identifier) != nil)
              }), sightings.filter({ $0.assetKind == "locomotive" }).count <= 1 else { throw URLError(.badURL) }
    }
    public let consent: ConsentEvidence
}
public struct PhysicalSightingResponse: Codable, Sendable {
    public struct State: Codable, Sendable { public let locomotive: String; public let rake: String }
    public let acceptedIds: [String]
    public let evidenceState: State
    public let message: String
    public var truthfulMessage: String {
        if evidenceState.locomotive == "conflicting" || evidenceState.rake == "conflicting" {
            return "Recorded. Conflicting evidence prevents confirmation."
        }
        if evidenceState.locomotive == "confirmed" || evidenceState.rake == "confirmed" {
            return "Recorded. Independent evidence currently confirms this identity."
        }
        return "Recorded, awaiting independent corroboration."
    }
}
public enum PhysicalSighting {
    public static func locomotive(_ value: String) -> String? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.range(of: "^[1-9][0-9]{4}$", options: .regularExpression) != nil ? normalized : nil
    }
    public static func coaches(_ value: String) -> [String]? {
        let items = value.split { $0.isWhitespace || $0 == "," }.map(String.init)
        guard (1...7).contains(items.count), Set(items).count == items.count,
              items.allSatisfy({ $0.range(of: "^[0-9]{5,12}$", options: .regularExpression) != nil && !$0.allSatisfy({ $0 == "0" }) }) else { return nil }
        return items
    }
    public static func request(locomotive: String, coaches: String, now: Date = Date(), evidenceId: String = UUID().uuidString) -> PhysicalSightingRequest? {
        let locoText = locomotive.trimmingCharacters(in: .whitespacesAndNewlines)
        let coachText = coaches.trimmingCharacters(in: .whitespacesAndNewlines)
        let loco = locoText.isEmpty ? nil : self.locomotive(locoText)
        let coachList = coachText.isEmpty ? [] : self.coaches(coachText)
        guard locoText.isEmpty || loco != nil, let coachList, loco != nil || !coachList.isEmpty else { return nil }
        let timestamp = Int64(now.timeIntervalSince1970 * 1_000)
        var sightings = coachList.map { PhysicalSightingInput(assetKind: "coach", identifier: $0, observedAt: timestamp, evidenceMethod: "onboard-coach-plate") }
        if let loco { sightings.insert(.init(assetKind: "locomotive", identifier: loco, observedAt: timestamp, evidenceMethod: "visual-number"), at: 0) }
        return .init(sightings: sightings, consent: .init(evidenceId: evidenceId, consentVersion: String(Consent.version), noticeHash: Consent.noticeHash, consentedAt: timestamp))
    }
}
