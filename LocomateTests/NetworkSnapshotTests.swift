import Foundation
import Testing
@testable import Locomate

@Suite("Network snapshot freshness")
@MainActor
struct NetworkSnapshotTests {
    private let base = Date(timeIntervalSince1970: 1_790_848_800)

    @Test("snapshot expires at the server boundary without another response")
    func expiresByClock() async throws {
        let clock = Clock(base)
        let model = NetworkSnapshotModel(clock: { clock.now })
        await model.refresh { _ in self.response() }
        #expect(model.markers.count == 1)
        #expect(model.markers.first?.observed == true)
        clock.now = base.addingTimeInterval(60)
        model.tick()
        #expect(model.expired)
        #expect(model.markers.isEmpty)
    }

    @Test("failed refresh retains only the remaining original freshness window")
    func failureCannotRenewFreshness() async throws {
        let clock = Clock(base)
        let model = NetworkSnapshotModel(clock: { clock.now })
        await model.refresh { _ in self.response() }
        clock.now = base.addingTimeInterval(30)
        await model.refresh { _ in throw Failure.offline }
        #expect(model.error != nil)
        #expect(model.markers.count == 1)
        #expect(model.snapshot?.generatedAt == base)
        clock.now = base.addingTimeInterval(60)
        model.tick()
        #expect(model.markers.isEmpty)
        #expect(model.expired)
    }

    @Test("same coordinates still update marker kind, source, time and name")
    func metadataChangesMarkerValue() throws {
        let first = try NetworkSnapshot(response(), now: base).markers(at: base)
        let changedSource = try NetworkSnapshot(response(source: .community), now: base).markers(at: base)
        let predicted = try NetworkSnapshot(response(source: .predicted, kind: .predicted), now: base).markers(at: base)
        let updated = try NetworkSnapshot(response(observedAt: stamp(base.addingTimeInterval(-5)), name: "Updated name"), now: base).markers(at: base)
        #expect(first != changedSource)
        #expect(first != predicted)
        #expect(first != updated)
        #expect(predicted.first?.observed == false)
        #expect(first.first?.latitude == predicted.first?.latitude)
        #expect(changedSource.first?.subtitle.contains("community") == true)
    }

    @Test("invalid timing and untrustworthy marker evidence cannot display current positions")
    func validatesEvidence() throws {
        #expect(throws: NetworkSnapshot.SnapshotError.self) {
            try NetworkSnapshot(response(generatedAt: "invalid"), now: base)
        }
        #expect(throws: NetworkSnapshot.SnapshotError.self) {
            try NetworkSnapshot(response(generatedAt: stamp(base.addingTimeInterval(61)),
                                         freshUntil: stamp(base.addingTimeInterval(120))), now: base)
        }
        #expect(throws: NetworkSnapshot.SnapshotError.self) {
            try NetworkSnapshot(response(freshUntil: stamp(base.addingTimeInterval(-1))), now: base)
        }
        for invalid in [response(observedAt: "invalid"),
                        response(observedAt: stamp(base.addingTimeInterval(-601))),
                        response(observedAt: stamp(base.addingTimeInterval(61))),
                        response(source: .predicted), response(latitude: 91), response(latitude: .nan)] {
            #expect(try NetworkSnapshot(invalid, now: base).markers(at: base).isEmpty)
        }
        // A far-future snapshot expiry cannot keep an aging position on the map.
        let longTTL = try NetworkSnapshot(response(freshUntil: stamp(base.addingTimeInterval(3600))), now: base)
        #expect(longTTL.markers(at: base.addingTimeInterval(601)).isEmpty)
    }

    @Test("late replies and late failures for old bounds cannot replace newer data")
    func rejectsOldBoundsReplies() async throws {
        let model = NetworkSnapshotModel(clock: { self.base })
        let gate = Gate()
        let first = Task { await model.refresh { _ in try await gate.wait() } }
        await gate.waitUntilRequested()
        model.setBounds(NetworkBounds(west: 70, south: 10, east: 90, north: 30))
        await model.refresh { _ in self.response(name: "Current bounds") }
        gate.resume(returning: response(name: "Old bounds"))
        await first.value
        #expect(model.markers.first?.title.contains("Current bounds") == true)
        #expect(model.error == nil)

        let oldFailure = Task { await model.refresh { _ in try await gate.wait() } }
        await gate.waitUntilRequested()
        model.setBounds(NetworkBounds(west: 71, south: 11, east: 91, north: 31))
        await model.refresh { _ in self.response(name: "Newest bounds") }
        gate.resume(throwing: Failure.offline)
        await oldFailure.value
        #expect(model.markers.first?.title.contains("Newest bounds") == true)
        #expect(model.error == nil)
        #expect(!model.loading)

        let olderSameBounds = Task { await model.refresh { _ in try await gate.wait() } }
        await gate.waitUntilRequested()
        await model.refresh { _ in self.response(name: "Latest request") }
        gate.resume(returning: response(name: "Earlier request"))
        await olderSameBounds.value
        #expect(model.markers.first?.title.contains("Latest request") == true)
    }

    @Test("cancellation ignoring transport cannot publish after screen exit")
    func cancellationCannotPublish() async throws {
        let model = NetworkSnapshotModel(clock: { self.base })
        let gate = Gate()
        let request = Task { await model.refresh { _ in try await gate.wait() } }
        await gate.waitUntilRequested()
        request.cancel()
        model.invalidateRequest()
        gate.resume(returning: response())
        await request.value
        #expect(model.snapshot == nil)
        #expect(model.markers.isEmpty)
        #expect(!model.loading)
    }

    private func response(source: DataSource = .official, kind: NetworkPositionKind = .observed,
                          observedAt: String? = nil, generatedAt: String? = nil, freshUntil: String? = nil,
                          name: String = "Punjab Mail", latitude: Double = 19.0) -> NetworkTrainsResponse {
        NetworkTrainsResponse(trains: [NetworkTrain(
            runId: "12137:2026-10-01", originDate: "2026-10-01", trainNumber: "12137", name: name,
            coordinate: RailCoordinate(latitude: latitude, longitude: 72.8), bearingDegrees: 0,
            observedAt: observedAt ?? stamp(base), source: source, confidence: .high, delayMinutes: 0,
            delayStatus: .observed, originCode: "CSTM", destinationCode: "FZR", positionKind: kind,
            provenance: nil
        )], generatedAt: generatedAt ?? stamp(base), freshUntil: freshUntil ?? stamp(base.addingTimeInterval(60)))
    }

    private func stamp(_ date: Date) -> String { ISO8601DateFormatter.locomote.string(from: date) }
    @MainActor private final class Clock {
        var now: Date
        init(_ now: Date) { self.now = now }
    }
    private enum Failure: Error { case offline }
    @MainActor private final class Gate {
        var continuation: CheckedContinuation<NetworkTrainsResponse, Error>?
        func wait() async throws -> NetworkTrainsResponse {
            try await withCheckedThrowingContinuation { continuation = $0 }
        }
        func waitUntilRequested() async {
            while continuation == nil { await Task.yield() }
        }
        func resume(returning response: NetworkTrainsResponse) {
            let pending = continuation
            continuation = nil
            pending?.resume(returning: response)
        }
        func resume(throwing error: Error) {
            let pending = continuation
            continuation = nil
            pending?.resume(throwing: error)
        }
    }
}

import SwiftUI
import UIKit
import XCTest

/// Hosts the production overlay without MapKit or a network request. This checks
/// the constrained reading region, not physical VoiceOver or a full AX audit.
@MainActor
final class NetworkOverlayLayoutTests: XCTestCase {
    func testLargestTextStatsStayScrollableBelowHeader() async throws {
        let markers = (0..<5000).map { index in
            NetworkMarker(id: String(index), latitude: 19, longitude: 72,
                          title: "Test train", subtitle: "observed · official", kind: .observed)
        }
        let overlay = ExploreNetworkOverlay(
            production: true, markers: markers, loading: false,
            error: "The connection is unavailable. The gateway could not be reached. Try again when the network connection returns.",
            expired: false, generatedAt: Date(timeIntervalSince1970: 1_790_848_800)
        )
        .environment(\.locomoteColors, LocomateTheme.dark)
        .dynamicTypeSize(.accessibility5)
        .background(Color.black)
        let host = UIHostingController(rootView: overlay)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 740))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.frame = window.bounds
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        for _ in 0..<50 {
            if scrollViews(in: host.view).contains(where: { $0.contentSize.height > $0.bounds.height && $0.bounds.height > 0 }) { break }
            try await Task.sleep(for: .milliseconds(20))
            host.view.layoutIfNeeded()
        }
        // Allow the window's appearance transaction to finish before capturing.
        try await Task.sleep(for: .milliseconds(400))
        let scroll = try XCTUnwrap(scrollViews(in: host.view).first)
        let frame = scroll.convert(scroll.bounds, to: host.view)
        XCTAssertGreaterThan(frame.minY, 150, "The enlarged header must retain its own reading space.")
        XCTAssertGreaterThanOrEqual(frame.height, 100, "The stats viewport must leave a usable reading region.")
        XCTAssertLessThanOrEqual(frame.maxY, host.view.bounds.maxY)
        XCTAssertGreaterThan(scroll.contentSize.height, scroll.bounds.height)
        XCTAssertTrue(scroll.isScrollEnabled)
        let bounds = XCTAttachment(string: "Container: \(host.view.bounds); stats viewport: \(frame); scroll content: \(scroll.contentSize)")
        bounds.name = "Explore largest stats bounds"
        bounds.lifetime = .keepAlways
        add(bounds)
        capture(host.view, name: "Explore largest stats top")
        scroll.setContentOffset(CGPoint(x: 0, y: scroll.contentSize.height - scroll.bounds.height), animated: false)
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertGreaterThan(scroll.contentOffset.y, 0)
        capture(host.view, name: "Explore largest stats end")
    }

    private func scrollViews(in view: UIView) -> [UIScrollView] {
        (view as? UIScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews(in: $0) }
    }

    private func capture(_ view: UIView, name: String) {
        let image = UIGraphicsImageRenderer(bounds: view.bounds).image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
