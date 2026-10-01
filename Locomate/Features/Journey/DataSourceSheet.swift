//
//  DataSourceSheet.swift
//  Locomate
//
//  Expanded provenance sheet — ported from SmartRail's "About this data" sheet.
//  It always states what the user is looking at, its source, and its age.
//

import SwiftUI

struct DataSourceSheet: View {
    @Environment(\.locomoteColors) private var colors
    @Environment(\.dismiss) private var dismiss

    let model: JourneyModel?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.units(4)) {
                    if let model, let journey = model.journey {
                        DataBanner(model: DataReport.banner(DataReportInput(
                            preview: model.isPreview,
                            historicalRoute: model.isPreview,
                            cached: model.isCached,
                            cachedAt: model.cachedAt,
                            error: nil,
                            observedAt: journey.provenance?.observedAt
                        )))

                        detailRows(journey)
                    } else {
                        Text("No journey is loaded yet.")
                            .font(LocomateFont.body)
                            .foregroundStyle(colors.textSecondary)
                    }
                }
                .padding(Spacing.units(4))
            }
            .background(colors.canvas)
            .navigationTitle("About this data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder private func detailRows(_ journey: Journey) -> some View {
        VStack(alignment: .leading, spacing: Spacing.units(3)) {
            row("Position source", journey.position.source.rawValue)
            row("Position confidence", journey.position.confidence.rawValue)
            row("Arrival source", journey.prediction.source.rawValue)
            row("Prediction model", journey.prediction.modelVersion)
            if let provenance = journey.provenance {
                row("Provider", provenance.providerLabel)
                row("Observed", RailTime.format(provenance.observedAt))
                row("Freshness", provenance.freshness)
                row("Attribution", provenance.attribution)
            }
            if model?.isPreview == true {
                Text("This is a historical route replay built from bundled route packs. It is never live, never used to estimate real performance, and never saved as a live observation.")
                    .font(LocomateFont.caption)
                    .foregroundStyle(colors.textSecondary)
            }
        }
        .padding(Spacing.units(4))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(colors.elevated))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(colors.borderSubtle, lineWidth: 0.75))
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).eyebrow(colors.textTertiary)
            Spacer(minLength: Spacing.units(3))
            Text(value)
                .font(LocomateFont.caption)
                .foregroundStyle(colors.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }
}
