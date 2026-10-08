import Foundation
import Testing
@testable import Locomate
private final class OperationsFixtureAnchor: NSObject {}

@Suite("Operational response validation")
struct OperationalContractTests {
    private func physical(_ mutation: ([String: Any]) -> [String: Any] = { $0 }) throws -> PhysicalChainResponse {
        let url = try #require(Bundle(for: OperationsFixtureAnchor.self).url(forResource: "physical-chain-unavailable", withExtension: "json"))
        let json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        return try JSONDecoder().decode(PhysicalChainResponse.self, from: JSONSerialization.data(withJSONObject: mutation(json)))
    }
    @Test("shared unavailable physical evidence remains unavailable")
    func unavailable() throws {
        let response = try physical()
        try OperationalValidation.physical(response, trainNumber: "12345", originDate: "2026-08-24")
        #expect(response.state == "unavailable" && response.rake.current == nil)
    }
    @Test("malformed identities, enums, evidence and chronology cannot become physical claims", arguments: ["identity", "kind", "state", "confidence", "negative-age", "expires-before-recorded", "available-without-current", "negative-clock", "asset-type", "link-state", "future-clock", "wrong-service-day", "reversed-run"])
    func malformedPhysical(_ issue: String) throws {
        let response = try physical { json in
            var result = json
            var rake = result["rake"] as! [String: Any]
            var evidence = rake["assignmentEvidence"] as! [String: Any]
            switch issue {
            case "identity": result["runId"] = "run:54321:2026-08-24"
            case "kind": rake["kind"] = "coach"
            case "state": result["state"] = "confirmed"
            case "confidence": evidence["confidence"] = 2
            case "negative-age": evidence["ageMs"] = -1
            case "expires-before-recorded": evidence["recordedAt"] = 1_000; evidence["expiresAt"] = 999
            case "available-without-current": rake["state"] = "available"
            case "negative-clock": result["asOf"] = -1
            case "future-clock": result["asOf"] = Date().timeIntervalSince1970 * 1_000 + 61_000
            case "wrong-service-day":
                rake["current"] = ["runId": "run:12345:2026-08-24", "trainNumber": "12345", "serviceDate": "2026-08-24", "status": "running", "origin": ["code": "AAA", "name": "Alpha"], "destination": ["code": "CCC", "name": "Charlie"], "scheduledStartAt": 1, "scheduledEndAt": 2, "scheduledOutboundDepartureAt": NSNull(), "inboundTerminalArrival": ["scheduledAt": NSNull(), "predictedAt": NSNull(), "actualAt": NSNull()]]
            case "asset-type": rake["assetType"] = "coach"
            case "link-state": var link = rake["inboundLink"] as! [String: Any]; link["state"] = "same-rake"; rake["inboundLink"] = link
            default:
                rake["current"] = ["runId": "run:12345:2026-08-24", "trainNumber": "12345", "serviceDate": "2026-08-24", "status": "running", "origin": ["code": "AAA", "name": "Alpha"], "destination": ["code": "CCC", "name": "Charlie"], "scheduledStartAt": 2, "scheduledEndAt": 1, "scheduledOutboundDepartureAt": NSNull(), "inboundTerminalArrival": ["scheduledAt": NSNull(), "predictedAt": NSNull(), "actualAt": NSNull()]]
            }
            rake["assignmentEvidence"] = evidence; result["rake"] = rake
            return result
        }
        #expect(throws: OperationalValidation.InvalidResponse.self) {
            try OperationalValidation.physical(response, trainNumber: "12345", originDate: "2026-08-24")
        }
    }
    private func operations(_ mutation: ([String: Any]) -> [String: Any] = { $0 }) throws -> OperationalChainResponse {
        let bytes = Data(#"{"trainNumber":"12345","originDate":"2026-08-24","availability":"partial","mode":"inferred","disclaimer":"Timetable continuity does not confirm a physical train-set.","previous":null,"current":{"id":"run:12345:2026-08-24","role":"current","trainNumber":"12345","trainName":"Midnight","originCode":"AAA","destinationCode":"CCC","scheduledDeparture":"2026-08-24T18:20:00Z","scheduledArrival":"2026-08-24T19:40:00Z","geometry":{"source":"official","coordinates":[{"latitude":19,"longitude":72},{"latitude":20,"longitude":73}]}},"next":null,"linkage":null,"delayAssessment":null,"propagatedDelay":null,"turnaroundRisk":null,"updatedAt":"2026-08-24T18:45:00Z"}"#.utf8)
        let json = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        return try JSONDecoder().decode(OperationalChainResponse.self, from: JSONSerialization.data(withJSONObject: mutation(json)))
    }
    @Test("valid source-backed operational geometry is accepted")
    func validOperations() throws { try OperationalValidation.operations(operations(), trainNumber: "12345", originDate: "2026-08-24") }
    @Test("wrong identities, unsupported enums, invalid geometry and backwards dated events are rejected", arguments: ["train", "date", "run-id", "role", "source", "coordinate", "chronology", "service-day", "mode"])
    func malformedOperations(_ issue: String) throws {
        let response = try operations { json in
            var result = json; var current = result["current"] as! [String: Any]
            switch issue {
            case "train": result["trainNumber"] = "54321"
            case "date": result["originDate"] = "2026-08-25"
            case "run-id": current["id"] = "run:54321:2026-08-24"
            case "role": current["role"] = "inbound"
            case "source": var geometry = current["geometry"] as! [String: Any]; geometry["source"] = "verified"; current["geometry"] = geometry
            case "coordinate": var geometry = current["geometry"] as! [String: Any]; geometry["coordinates"] = [["latitude": 91, "longitude": 72]]; current["geometry"] = geometry
            case "chronology": current["scheduledArrival"] = "2026-08-24T18:19:00Z"
            case "service-day": current["scheduledDeparture"] = "2026-08-23T18:20:00Z"
            default: result["mode"] = "live-confirmed"
            }
            result["current"] = current; return result
        }
        #expect(throws: OperationalValidation.InvalidResponse.self) {
            try OperationalValidation.operations(response, trainNumber: "12345", originDate: "2026-08-24")
        }
    }
}

extension OperationalContractTests {
    @Test("shared enriched operational and physical chains preserve separate certainty and source evidence")
    func enriched() throws {
        let physicalURL = try #require(Bundle(for: OperationsFixtureAnchor.self).url(forResource: "physical-chain-enriched", withExtension: "json"))
        let physical = try JSONDecoder().decode(PhysicalChainResponse.self, from: Data(contentsOf: physicalURL))
        try OperationalValidation.physical(physical, trainNumber: "12345", originDate: "2026-08-24")
        #expect(physical.rake.assetType == "trainset" && physical.rake.previous?.status == "completed")
        #expect(physical.rake.outboundLink.evidence.source == "synthetic-test-working-plan")
        #expect(physical.locomotive.state == "unavailable")
        let workingURL = try #require(Bundle(for: OperationsFixtureAnchor.self).url(forResource: "operational-working-enriched", withExtension: "json"))
        let working = try JSONDecoder().decode(OperationalChainResponse.self, from: Data(contentsOf: workingURL))
        try OperationalValidation.operations(working, trainNumber: "12345", originDate: "2026-08-24")
        #expect(working.mode == "inferred" && working.linkage?.claim == "possible-same-rake")
        #expect(working.previous?.geometry.source == "inferred" && working.next?.role == "next")
    }
}

extension OperationalContractTests {
    @Test("station catalogue permits real hyphenated and one-letter codes without accepting unsafe paths")
    func stationCodes() throws {
        struct Response: Decodable { let stations: [StationSearchResult] }
        let url = try #require(Bundle(for: OperationsFixtureAnchor.self).url(forResource: "station-search-hyphen", withExtension: "json"))
        let response = try JSONDecoder().decode(Response.self, from: Data(contentsOf: url))
        #expect(response.stations.contains { $0.code == "NRL-DLS" })
        #expect(response.stations.contains { $0.code == "D" })
        #expect(response.stations.allSatisfy { StationSearch.isValidCode($0.code) })
        for invalid in ["123", "-NDLS", "NDLS-", "NRL--DLS", "../../", "NDLS?x=1", "ndls", "AAAAAAAAAAA"] {
            #expect(!StationSearch.isValidCode(invalid))
        }
    }
}
