//
//  JourneySetupSheet.swift
//  Locomate
//
//  Personal boarding/alighting selection — ported from
//  SmartRail `src/components/JourneySetupSheet.tsx`.
//

import SwiftUI

struct JourneySetupSheet: View {
    @Environment(\.locomoteColors) private var colors
    @Environment(\.dismiss) private var dismiss

    let journey: Journey
    let originDate: String
    let initial: JourneyPlan?
    let onConfirm: (JourneyPlan) -> Void

    @State private var coach = ""
    @State private var seat = ""
    @State private var boardingIndex = 0
    @State private var alightingIndex = 0

    private var valid: Bool { boardingIndex < alightingIndex }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.units(5)) {
                    Text("Choose where you board and where you get off. This is stored privately on this device and never leaves it.")
                        .font(LocomateFont.caption)
                        .foregroundStyle(colors.textSecondary)

                    stopPicker("Boarding", selection: $boardingIndex, upperBound: alightingIndex - 1 < 0 ? 0 : alightingIndex - 1)
                    stopPicker("Drop-off", selection: $alightingIndex, lowerBound: boardingIndex + 1)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Your coach and seat (optional)").eyebrow(colors.textTertiary)
                        TextField("Coach", text: $coach).accessibilityIdentifier("journey.plan.coach")
                        TextField("Seat or berth", text: $seat).accessibilityIdentifier("journey.plan.seat")
                        Text("These personal details stay on this device. They are separate from a public coach plate sighting.")
                            .font(LocomateFont.caption).foregroundStyle(colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }.textFieldStyle(.roundedBorder).autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                }
                .padding(Spacing.units(4))
            }
            .background(colors.canvas)
            .navigationTitle("Your journey")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let plan = try? JourneyPlanLogic.create(
                            journey: journey, originDate: originDate,
                            boardingIndex: boardingIndex, alightingIndex: alightingIndex, coach: coach, seat: seat
                        ) {
                            onConfirm(plan)
                            dismiss()
                        }
                    }
                    .disabled(!valid)
                }
            }
        }
        .onAppear {
            let resolved = JourneyPlanLogic.resolve(journey: journey, plan: initial)
                ?? JourneyPlanLogic.default(journey: journey, originDate: originDate)
            coach = resolved.coach ?? ""
            seat = resolved.seat ?? ""
            boardingIndex = resolved.boarding.index
            alightingIndex = resolved.alighting.index
        }
    }

    private func stopPicker(
        _ title: String,
        selection: Binding<Int>,
        lowerBound: Int = 0,
        upperBound: Int? = nil
    ) -> some View {
        let upper = upperBound ?? journey.stops.count - 1
        return VStack(alignment: .leading, spacing: Spacing.units(2)) {
            Text(title).eyebrow(colors.textTertiary)
            Picker(title, selection: selection) {
                ForEach(lowerBound...max(lowerBound, upper), id: \.self) { index in
                    if journey.stops.indices.contains(index) {
                        Text("\(journey.stops[index].name) (\(journey.stops[index].code))").tag(index)
                    }
                }
            }
            .pickerStyle(.menu)
            .tint(colors.accentBase)
            .accessibilityIdentifier("journey.plan.\(title)")
        }
    }
}
