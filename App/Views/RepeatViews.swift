import ScheduledTextsCore
import SwiftUI

/// The Repeat screen, like the one in Calendar: Never, the common choices,
/// and Custom.
struct RepeatPicker: View {
    @Binding var repetition: Repetition?
    /// The text's send time, which the schedule starts from.
    let anchor: Date

    @Environment(\.dismiss) private var dismiss

    private var preset: Repetition? {
        repetition?.preset(anchor: anchor)
    }

    var body: some View {
        Form {
            Section {
                choice("Never", selected: repetition == nil) {
                    repetition = nil
                }
                ForEach(Repetition.presets) { preset in
                    choice(preset.title, selected: self.preset == preset.rule) {
                        var rule = preset.rule
                        rule.endDate = repetition?.endDate
                        repetition = rule
                    }
                }
            }
            Section {
                NavigationLink {
                    CustomRepeatView(repetition: $repetition, anchor: anchor)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Custom")
                            if let repetition, preset == nil {
                                Text(repetition.summary(anchor: anchor))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if repetition != nil && preset == nil {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                                .fontWeight(.semibold)
                        }
                    }
                }
            }
        }
        .navigationTitle("Repeat")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func choice(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            dismiss()
        } label: {
            CheckRow(title: title, checked: selected)
        }
    }
}

/// The Custom repeat screen: frequency, every N, and the days.
struct CustomRepeatView: View {
    @Binding var repetition: Repetition?
    let anchor: Date

    @State private var rule: Repetition
    @State private var pickingInterval = false

    init(repetition: Binding<Repetition?>, anchor: Date) {
        _repetition = repetition
        self.anchor = anchor
        _rule = State(initialValue: repetition.wrappedValue ?? .daily)
    }

    private var anchorWeekday: Int { Calendar.current.component(.weekday, from: anchor) }

    var body: some View {
        Form {
            Section {
                Picker("Frequency", selection: $rule.frequency) {
                    Text("Daily").tag(Repetition.Frequency.daily)
                    Text("Weekly").tag(Repetition.Frequency.weekly)
                    Text("Monthly").tag(Repetition.Frequency.monthly)
                    Text("Yearly").tag(Repetition.Frequency.yearly)
                }

                Button {
                    withAnimation { pickingInterval.toggle() }
                } label: {
                    LabeledContent("Every") {
                        Text(intervalText)
                            .foregroundStyle(pickingInterval ? Color.accentColor : .secondary)
                    }
                    .foregroundStyle(.primary)
                }
                if pickingInterval {
                    HStack(spacing: 0) {
                        Picker("Every", selection: $rule.interval) {
                            ForEach(1...99, id: \.self) { Text("\($0)").tag($0) }
                        }
                        .pickerStyle(.wheel)
                        Text(unit(rule.interval))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .labelsHidden()
                }
            } footer: {
                Text("\(rule.summary(anchor: anchor)), starting \(SendTimeFormat.string(for: anchor)).")
            }

            switch rule.frequency {
            case .weekly:
                Section {
                    ForEach(Repetition.weekdayOrder(), id: \.self) { weekday in
                        Button {
                            toggle(weekday)
                        } label: {
                            CheckRow(title: Repetition.weekdayName(weekday), checked: weekdays.contains(weekday))
                        }
                    }
                }
            case .monthly:
                Section {
                    Button {
                        rule.monthlyWeekday = nil
                    } label: {
                        CheckRow(
                            title: "Each \(Repetition.dayOrdinal(Calendar.current.component(.day, from: anchor)))",
                            checked: rule.monthlyWeekday == nil
                        )
                    }
                    Button {
                        if rule.monthlyWeekday == nil {
                            rule.monthlyWeekday = .of(anchor)
                        }
                    } label: {
                        CheckRow(title: "On the…", checked: rule.monthlyWeekday != nil)
                    }
                    if rule.monthlyWeekday != nil {
                        HStack(spacing: 0) {
                            Picker("Which", selection: monthlyOrdinal) {
                                ForEach([1, 2, 3, 4, -1], id: \.self) { Text(Repetition.ordinalName($0)).tag($0) }
                            }
                            Picker("Day", selection: monthlyWeekday) {
                                ForEach(Repetition.weekdayOrder(), id: \.self) { Text(Repetition.weekdayName($0)).tag($0) }
                            }
                        }
                        .pickerStyle(.wheel)
                        .labelsHidden()
                    }
                } footer: {
                    if rule.monthlyWeekday == nil, Calendar.current.component(.day, from: anchor) > 28 {
                        Text("Months without a \(Repetition.dayOrdinal(Calendar.current.component(.day, from: anchor))) are skipped.")
                    }
                }
            case .daily, .yearly:
                EmptyView()
            }
        }
        .navigationTitle("Custom")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: rule.frequency) { _, frequency in
            if frequency == .weekly {
                if rule.weekdays.isEmpty { rule.weekdays = [anchorWeekday] }
            } else {
                rule.weekdays = []
            }
            if frequency != .monthly { rule.monthlyWeekday = nil }
        }
        .onChange(of: rule) { _, rule in
            repetition = rule
        }
        .onAppear {
            // Opening Custom picks it, like Calendar.
            if repetition == nil { repetition = rule }
        }
    }

    private var weekdays: Set<Int> {
        rule.weekdays.isEmpty ? [anchorWeekday] : rule.weekdays
    }

    /// Picks or unpicks a day. The last picked day can't be unpicked.
    private func toggle(_ weekday: Int) {
        var days = weekdays
        if days.contains(weekday) {
            guard days.count > 1 else { return }
            days.remove(weekday)
        } else {
            days.insert(weekday)
        }
        rule.weekdays = days
    }

    private var intervalText: String {
        rule.interval == 1 ? unit(1).capitalized : "\(rule.interval) \(unit(rule.interval))"
    }

    private func unit(_ n: Int) -> String {
        let one: String
        switch rule.frequency {
        case .daily: one = "day"
        case .weekly: one = "week"
        case .monthly: one = "month"
        case .yearly: one = "year"
        }
        return n == 1 ? one : one + "s"
    }

    private var monthlyOrdinal: Binding<Int> {
        Binding(
            get: { rule.monthlyWeekday?.ordinal ?? 1 },
            set: { rule.monthlyWeekday = .init(ordinal: $0, weekday: rule.monthlyWeekday?.weekday ?? anchorWeekday) }
        )
    }

    private var monthlyWeekday: Binding<Int> {
        Binding(
            get: { rule.monthlyWeekday?.weekday ?? anchorWeekday },
            set: { rule.monthlyWeekday = .init(ordinal: rule.monthlyWeekday?.ordinal ?? 1, weekday: $0) }
        )
    }
}

/// End Repeat: Never, or on a day.
struct EndRepeatPicker: View {
    @Binding var repetition: Repetition?
    let anchor: Date

    var body: some View {
        Form {
            Section {
                Button {
                    repetition?.endDate = nil
                } label: {
                    CheckRow(title: "Never", checked: repetition?.endDate == nil)
                }
                Button {
                    if repetition?.endDate == nil {
                        repetition?.endDate = Calendar.current.date(byAdding: .month, value: 1, to: anchor)
                    }
                } label: {
                    CheckRow(title: "On Date", checked: repetition?.endDate != nil)
                }
            }
            if repetition?.endDate != nil {
                Section {
                    DatePicker(
                        "End Date",
                        selection: Binding(
                            get: { repetition?.endDate ?? anchor },
                            set: { repetition?.endDate = $0 }
                        ),
                        in: Calendar.current.startOfDay(for: anchor)...,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                } footer: {
                    Text("The last text goes out on or before this day.")
                }
            }
        }
        .navigationTitle("End Repeat")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A list row with a checkmark when picked, like Settings and Calendar.
struct CheckRow: View {
    let title: String
    let checked: Bool

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.primary)
            Spacer()
            if checked {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
                    .fontWeight(.semibold)
            }
        }
        .contentShape(Rectangle())
    }
}
