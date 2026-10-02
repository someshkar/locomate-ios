import Foundation
import Observation
import UIKit
import UserNotifications

struct JourneyAlertPayload: Sendable, Equatable {
    let eventId: String
    let runId: String
    let revision: Int64
    let channel: JourneyAlertChannel
    let expiresAt: Date
    let url: URL

    init?(fields: [String: String], now: Date = Date()) {
        guard fields["type"] == "journey-alert", fields["version"] == "1",
              let eventId = fields["eventId"], !eventId.isEmpty, eventId.count <= 200,
              eventId.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value <= 126 }),
              let runId = fields["runId"], runId == JourneyAlertIdentity.normalize(runId),
              let identity = JourneyAlertIdentity.parse(runId),
              fields["trainNumber"] == identity.trainNumber, fields["serviceDate"] == identity.date,
              let revision = fields["revision"].flatMap(Int64.init), revision > 0, revision <= 9_007_199_254_740_991,
              let channel = fields["channel"].flatMap(JourneyAlertChannel.init(rawValue:)),
              let observed = fields["observedAt"].flatMap(Double.init), observed.isFinite,
              let expiry = fields["expiresAt"].flatMap(Double.init), expiry.isFinite,
              observed <= now.timeIntervalSince1970 * 1000 + 60_000,
              expiry > now.timeIntervalSince1970 * 1000, expiry > observed, expiry <= observed + 600_000,
              let title = fields["title"], !title.isEmpty, title.count <= 160,
              let body = fields["body"], !body.isEmpty, body.count <= 1000,
              let rawLink = fields["deepLink"],
              let expected = try? Routes.journeyURL(trainNumber: identity.trainNumber, date: identity.date),
              rawLink == expected.absoluteString else { return nil }
        self.eventId = eventId
        self.runId = runId
        self.revision = revision
        self.channel = channel
        self.expiresAt = Date(timeIntervalSince1970: expiry / 1000)
        self.url = expected
    }
}

@Observable @MainActor
final class JourneyAlertPushBridge: JourneyAlertPushAuthorization {
    static let shared = JourneyAlertPushBridge()
    private(set) var token: String?
    var pendingPayload: JourneyAlertPayload?
    var registrationError: String?
    weak var service: JourneyAlertService?

    var environment: String {
        Bundle.main.object(forInfoDictionaryKey: "LocomateAPNSEnvironment") as? String == "production" ? "production" : "sandbox"
    }
    static var appIsActive: Bool { UIApplication.shared.applicationState == .active }

    func requestPermission() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }
    func isDenied() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }
    func register() {
        registrationError = nil
        UIApplication.shared.registerForRemoteNotifications()
    }
    func registered(_ data: Data) {
        token = data.map { String(format: "%02x", $0) }.joined()
        Task { await service?.refresh() }
    }
    func failed(_ error: Error) { registrationError = error.localizedDescription }
}

final class JourneyAlertDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        JourneyAlertPushBridge.shared.registered(deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        JourneyAlertPushBridge.shared.failed(error)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let fields = notification.request.content.userInfo.reduce(into: [String: String]()) { result, entry in
            if let key = entry.key as? String, let value = entry.value as? String { result[key] = value }
        }
        guard let payload = JourneyAlertPayload(fields: fields) else { return [] }
        return await MainActor.run {
            JourneyAlertPushBridge.shared.service?.accepts(payload, presenting: true) == true ? [.banner, .sound, .list] : []
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        let fields = response.notification.request.content.userInfo.reduce(into: [String: String]()) { result, entry in
            if let key = entry.key as? String, let value = entry.value as? String { result[key] = value }
        }
        guard let payload = JourneyAlertPayload(fields: fields) else { return }
        await MainActor.run { JourneyAlertPushBridge.shared.pendingPayload = payload }
    }
}
