import SwiftUI

struct PhysicalChainCard: View {
    @Environment(\.locomoteColors) private var colors
    let chain: PhysicalChainResponse?
    let enabled: Bool
    let onReport: () -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                Text("Physical train identity").eyebrow(colors.textTertiary)
                Text("Physical assignments are separate from timetable rotation. A report alone does not confirm a locomotive or train-set.")
                    .font(LocomateFont.caption).foregroundStyle(colors.textSecondary)
                if let chain {
                    asset(chain.rake, title: "Train-set")
                    asset(chain.locomotive, title: "Locomotive")
                    Text("Snapshot: \(Date(timeIntervalSince1970: chain.asOf / 1_000).formatted(date: .abbreviated, time: .shortened))")
                        .font(LocomateFont.caption).foregroundStyle(colors.textSecondary)
                } else {
                    Text(enabled ? "Physical assignment evidence is unavailable for this run." : "A current production journey is required.")
                        .font(LocomateFont.caption).foregroundStyle(colors.textSecondary)
                }
                Button("Report a locomotive or coach plate", action: onReport)
                    .buttonStyle(AccessibleTextButtonStyle()).disabled(!enabled)
                    .accessibilityIdentifier("physicalSightings.open")
            }.fixedSize(horizontal: false, vertical: true)
        }
    }

    private func asset(_ chain: PhysicalAssetChain, title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(LocomateFont.bodyStrong).foregroundStyle(colors.textPrimary)
            let evidence = chain.assignmentEvidence
            Text(chain.state == "unavailable" ? "Assignment unavailable · \(reason(chain.unavailableReason))"
                 : evidence.freshness == "fresh" ? "Current assignment evidence" : "Last assignment evidence · \(evidence.freshness)")
                .font(LocomateFont.caption).foregroundStyle(colors.textSecondary)
            if let source = evidence.source {
                Text("\(source) · \(evidence.freshness)\(evidence.confidence.map { " · " + $0.formatted(.percent.precision(.fractionLength(0))) + " confidence" } ?? "")")
                    .font(LocomateFont.caption).foregroundStyle(colors.textSecondary)
            }
            if let at = evidence.recordedAt {
                Text("Recorded \(Date(timeIntervalSince1970: at / 1_000).formatted(date: .abbreviated, time: .shortened))")
                    .font(LocomateFont.caption).foregroundStyle(colors.textSecondary)
            }
            if chain.state != "unavailable" {
                run("Inbound", chain.previous, link: chain.inboundLink)
                run("Current", chain.current, link: nil)
                run("Outbound", chain.next, link: chain.outboundLink)
            }
        }
    }
    private func run(_ label: String, _ run: PhysicalRun?, link: PhysicalLink?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(label): \(run.map { "\($0.trainNumber) · \($0.serviceDate) · \($0.origin.code) → \($0.destination.code) · \($0.status)" } ?? "unavailable")")
                .font(LocomateFont.caption).foregroundStyle(colors.textPrimary)
            if let link {
                Text("Link \(link.state) · \(reason(link.reason)) · \(link.evidence.freshness)")
                    .font(LocomateFont.caption).foregroundStyle(colors.textSecondary)
                if let ready = link.serviceReadyAt {
                    Text("Service ready \(Date(timeIntervalSince1970: ready / 1_000).formatted(date: .abbreviated, time: .shortened))")
                        .font(LocomateFont.caption).foregroundStyle(colors.textSecondary)
                }
            }
        }
    }
    private func reason(_ value: String?) -> String { (value ?? "no evidence").replacingOccurrences(of: "-", with: " ") }
}

struct PhysicalSightingSheet: View {
    @Environment(\.locomoteColors) private var colors
    @Environment(\.dismiss) private var dismiss
    let model: JourneyModel
    @State private var locomotive = ""
    @State private var coaches = ""
    @State private var consent = false
    @State private var pending = false
    @State private var message: String?
    @State private var submitted = false
    // Retry the exact request/body/key after an uncertain network response.
    @State private var request: PhysicalSightingRequest?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Report only numbers you personally read on this train. Coach plate serials identify railway equipment; your reserved coach and seat belong in Edit your journey.")
                        .font(LocomateFont.body)
                    TextField("Locomotive number (optional)", text: $locomotive)
                        .keyboardType(.numberPad).accessibilityIdentifier("physicalSightings.locomotive")
                    TextField("Coach plate serials, separated by commas (optional)", text: $coaches)
                        .keyboardType(.numbersAndPunctuation).accessibilityIdentifier("physicalSightings.coaches")
                    Text(Consent.notice).font(LocomateFont.caption).foregroundStyle(colors.textSecondary)
                    Toggle("I consent to sharing these equipment numbers for this dated journey", isOn: $consent)
                        .accessibilityIdentifier("physicalSightings.consent")
                    Text("No photo, location, PNR, passenger name or reserved coach/seat is attached. Independent evidence is required before confirmation. Withdraw community consent or delete this installation’s data in Settings.")
                        .font(LocomateFont.caption).foregroundStyle(colors.textSecondary)
                    if let message { Text(message).foregroundStyle(colors.textPrimary).accessibilityIdentifier("physicalSightings.result") }
                    if !submitted {
                        Button(pending ? "Sending…" : "Share sightings") { submit() }
                            .buttonStyle(AccessibleTextButtonStyle())
                            .disabled(pending || !consent || PhysicalSighting.request(locomotive: locomotive, coaches: coaches) == nil)
                    }
                }.textFieldStyle(.roundedBorder).padding(20)
                    .fixedSize(horizontal: false, vertical: true)
                    .disabled(pending)
            }.background(colors.canvas)
                .navigationTitle("Equipment sightings").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(submitted ? "Done" : "Cancel") { dismiss() } } }
                .onAppear {
                    if let report = model.pendingPhysicalReport {
                        request = report.consentIsCurrent() ? report.request : nil
                        locomotive = report.request.sightings.first { $0.assetKind == "locomotive" }?.identifier ?? ""
                        coaches = report.request.sightings.filter { $0.assetKind == "coach" }.map(\.identifier).joined(separator: ", ")
                        message = report.consentIsCurrent() ? "A previous report is stored for retry." : "Stored report needs your consent again before sending."
                    }
                }
                .onChange(of: locomotive) { _, _ in discardChangedDraft() }
                .onChange(of: coaches) { _, _ in discardChangedDraft() }

        }
    }
    private func discardChangedDraft() {
        guard let request else { return }
        let storedLoco = request.sightings.first { $0.assetKind == "locomotive" }?.identifier ?? ""
        let storedCoaches = request.sightings.filter { $0.assetKind == "coach" }.map(\.identifier)
        let typedCoaches = coaches.split { $0 == "," || $0.isWhitespace }.map(String.init)
        if locomotive.trimmingCharacters(in: .whitespacesAndNewlines) != storedLoco || typedCoaches != storedCoaches {
            self.request = nil
        }
    }
    private func submit() {
        guard consent, !pending, !PrivacyDeletionLatch.isPending,
              let prepared = request ?? PhysicalSighting.request(locomotive: locomotive, coaches: coaches) else { return }
        if let previous = model.pendingPhysicalReport, previous.id != prepared.consent.evidenceId {
            do { try model.discardPhysicalReport(previous.id) } catch { message = error.localizedDescription; return }
        }
        if let previous = model.pendingPhysicalReport, !previous.consentIsCurrent() {
            do { try model.discardPhysicalReport(previous.id) } catch { message = error.localizedDescription; return }
            request = nil
            consent = false
            message = "Confirm the current notice again before retrying."
            return
        }
        request = prepared
        pending = true
        Task { @MainActor in
            defer { pending = false }
            do {
                let result = try await model.submitPhysicalSightings(prepared)
                message = result.truthfulMessage
                submitted = true
            } catch is CancellationError { message = "The journey changed. Open the current run before reporting." }
            catch {
                if let failure = error as? APIError, failure.code == "invalid_observation_consent" {
                    request = nil; consent = false
                    message = "Confirm the current notice again before retrying."
                } else { message = "Report stored privately for retry while consent is current. " + error.localizedDescription }
            }
        }
    }
}
