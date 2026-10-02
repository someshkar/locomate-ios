import SwiftUI

struct ReliabilityHistoryCard: View {
    @Environment(\.locomoteServices) private var services
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = ReliabilityHistoryModel()
    @State private var attempt = 0
    let trainNumber: String
    let originDate: String
    let preview: Bool

    private var key: ReliabilityHistoryModel.Key {
        .init(source: ObjectIdentifier(services), trainNumber: trainNumber, originDate: originDate,
              preview: preview || services.railService == nil, attempt: attempt)
    }
    private struct Context: Equatable {
        let key: ReliabilityHistoryModel.Key
        let scenePhase: ScenePhase
    }

    var body: some View {
        ReliabilityHistoryContent(phase: model.phase(for: key), trainNumber: trainNumber) { attempt += 1 }
            .task(id: Context(key: key, scenePhase: scenePhase)) {
                guard scenePhase == .active else { return }
                await model.load(key: key) {
                    guard let service = services.railService else { throw CancellationError() }
                    return try await service.trainHistory(trainNumber: trainNumber, limit: 1)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { model.cancel() }
            }
            .onDisappear { model.cancel() }
    }
}

/// Pure rendering keeps the endpoint/loading logic separate from layout checks.
struct ReliabilityHistoryContent: View {
    @Environment(\.locomoteColors) private var colors
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let phase: ReliabilityHistoryModel.Phase
    let trainNumber: String
    let retry: () -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.units(3)) {
                Text("Reliability history").eyebrow(colors.textTertiary)
                    .accessibilityAddTraits(.isHeader)
                Text("Train \(trainNumber) · Final destination arrivals")
                    .font(LocomateFont.bodyStrong)
                    .foregroundStyle(colors.textPrimary)
                    .accessibilityIdentifier("reliability.train")
                switch phase {
                case .idle, .loading:
                    ProgressView("Loading destination-arrival history…")
                        .tint(colors.accentBase)
                        .accessibilityIdentifier("reliability.loading")
                case .unavailable:
                    text("Reliability history requires a production journey. Preview data is never used to estimate real performance.")
                        .accessibilityIdentifier("reliability.unavailable")
                case .blocked:
                    text("Data deletion is pending. Retry deletion in Settings to use the rail service.")
                        .accessibilityIdentifier("reliability.unavailable")
                case .failed:
                    text("History is temporarily unavailable. Try again.")
                        .accessibilityIdentifier("reliability.error")
                    retryButton
                case .loaded(let response):
                    summary(response)
                    retryButton
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reliability.card")
    }

    @ViewBuilder private func summary(_ response: TrainHistoryResponse) -> some View {
        let summary = response.summary
        if summary.denominator > 0 {
            (dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.units(3)))
                : AnyLayout(HStackLayout(alignment: .top, spacing: Spacing.units(3)))) {
                metric("Early", value: summary.percentages.early, id: "early")
                metric("On time (within 5 minutes)", value: summary.percentages.onTime, id: "onTime")
                metric("Late", value: summary.percentages.late, id: "late")
            }
            text("On time means within ±5 minutes of the scheduled arrival.")
                .accessibilityIdentifier("reliability.policy")
        } else {
            text(summary.counts.total == 0
                 ? "No destination-arrival history is available for this train yet."
                 : "Arrival timing percentages are unavailable for the recorded runs.")
                .accessibilityIdentifier("reliability.empty")
        }
        text(summary.denominator == 0 ? "No runs have classifiable arrival timing"
             : "Based on \(summary.denominator) recorded destination arrivals")
            .accessibilityIdentifier("reliability.sample")
        text("\(summary.counts.cancelled) cancelled and \(summary.counts.unknown) unknown runs excluded")
            .accessibilityIdentifier("reliability.exclusions")
        if summary.lowSample && summary.denominator > 0 {
            text("Small sample: fewer than 10 recorded arrivals.")
                .accessibilityIdentifier("reliability.lowSample")
        }
        if let coverage = summary.coverage {
            text("Service dates: \(coverage.from) to \(coverage.to)")
                .accessibilityIdentifier("reliability.coverage")
        }
        text(ReliabilitySummary.generatedLabel(response.generatedAt))
            .accessibilityIdentifier("reliability.generated")
        text("Coverage is partial and includes only the arrival records available to this service.")
            .accessibilityIdentifier("reliability.disclosure")
        text("These are past final-destination arrivals, not a prediction for your journey.")
            .accessibilityIdentifier("reliability.scope")
    }

    private func metric(_ label: String, value: Double?, id: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(LocomateFont.caption).foregroundStyle(colors.textSecondary)
            Text(ReliabilitySummary.percentage(value))
                .font(LocomateFont.title.monospacedDigit())
                .foregroundStyle(colors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(ReliabilitySummary.percentage(value))")
        .accessibilityIdentifier("reliability.metric.\(id)")
    }

    private var retryButton: some View {
        Button("Refresh history", action: retry)
            .font(LocomateFont.bodyStrong)
            .frame(minHeight: 44)
            .accessibilityIdentifier("reliability.retry")
    }
    private func text(_ value: String) -> some View {
        Text(value).font(LocomateFont.caption).foregroundStyle(colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
