//
//  WeightTrackingView.swift
//  VerraOS
//

import SwiftUI

struct WeightTrackingView: View {
    let client: Client
    var onBack: () -> Void

    @Environment(ProfileStore.self) private var profile
    @Environment(TrainerStore.self) private var trainer
    @Environment(\.isReadOnly) private var isReadOnly

    @State private var showingLog = false
    @State private var editingDetails = false
    @State private var showAllHistory = false
    @State private var toast: ToastData?

    private let historyLimit = 5

    private var unit: WeightUnit { trainer.units }

    private var entries: [WeightEntry] {
        profile.weights(for: client).sorted { $0.daysAgo > $1.daysAgo }
    }
    /// Logged values converted into the trainer's chosen display unit.
    private var values: [Double] { entries.map { unit.fromKg($0.kg) } }

    private var targets: WeightTargets { profile.weightTargets(for: client) }

    /// All headline weights are stored in kg; expose them in the display unit.
    private var startWeight: Double { unit.fromKg(targets.start ?? (entries.first?.kg ?? 0)) }
    private var currentWeight: Double { unit.fromKg(entries.last?.kg ?? 0) }
    private var goalWeight: Double { unit.fromKg(targets.goal ?? 0) }

    var body: some View {
        VStack(spacing: 0) {
            ProfileTopBar(
                title: "Weight",
                subtitle: client.name.firstWord,
                trailing: isReadOnly ? nil : AnyView(editButton),
                onBack: onBack
            )
            ScrollView(showsIndicators: false) {
                VStack(spacing: Theme.Spacing.md) {
                    trendCard
                    HStack(spacing: 8) {
                        StatCell(label: "Start", value: String(format: "%.0f %@", startWeight, unit.short))
                        StatCell(label: "Current", value: String(format: "%.1f %@", currentWeight, unit.short))
                        StatCell(label: "Goal", value: String(format: "%.0f %@", goalWeight, unit.short), accent: true)
                    }
                    logButton
                    historyCard
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.sm)
                .padding(.bottom, 100)
            }
        }
        .background(Theme.Color.background)
        .toast($toast)
        .sheet(isPresented: $showingLog) {
            LogWeightSheet(current: currentWeight, unit: unit) { value in
                profile.logWeight(unit.toKg(value), for: client)
                toast = ToastData(message: "Weight logged", icon: "scalemass.fill")
            }
        }
        .sheet(isPresented: $editingDetails) {
            WeightDetailsSheet(start: startWeight, current: currentWeight, goal: goalWeight, unit: unit) { newStart, newCurrent, newGoal in
                profile.setWeightTargets(start: unit.toKg(newStart), goal: unit.toKg(newGoal), for: client)
                if abs(newCurrent - currentWeight) > 0.001 {
                    profile.logWeight(unit.toKg(newCurrent), for: client)
                }
                toast = ToastData(message: "Details updated", icon: "checkmark.circle.fill")
            }
        }
    }

    private var editButton: some View {
        Button { editingDetails = true } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.Color.ink)
                .frame(width: 42, height: 42)
                .background(Theme.Color.surface, in: Circle())
                .overlay(Circle().stroke(Theme.Color.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var trendCard: some View {
        SectionCard(title: "Trend", icon: "chart.line.uptrend.xyaxis") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(String(format: "%.1f", currentWeight))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Color.ink)
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: currentWeight)
                    Text(unit.short)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.Color.inkMuted)
                    Spacer()
                    let delta = currentWeight - startWeight
                    Label(String(format: "%+.1f %@", delta, unit.short), systemImage: delta <= 0 ? "arrow.down.right" : "arrow.up.right")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(delta <= 0 ? Color(hex: 0x57C77B) : Theme.Color.danger)
                }
                WeightTrendChart(values: values, goal: goalWeight, height: 150)
                legend
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 16) {
            legendDot(color: Theme.Color.ink, label: "Logged")
            legendDot(color: Theme.Color.accent, label: "Current")
            legendDash(color: Color(hex: 0x57C77B), label: "Target")
            Spacer()
        }
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.Color.inkMuted)
        }
    }

    private func legendDash(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 14, height: 3)
            Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.Color.inkMuted)
        }
    }

    private var logButton: some View {
        Button { showingLog = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                Text("Log Weight")
            }
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(Theme.Color.accentInk)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Theme.Color.accent, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var historyCard: some View {
        SectionCard(title: "Log History", icon: "list.bullet") {
            VStack(spacing: 0) {
                let all = entries.reversed().map { $0 } // newest first
                let visible = showAllHistory ? all : Array(all.prefix(historyLimit))
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, entry in
                    HStack {
                        Text(dateLabel(daysAgo: entry.daysAgo))
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(Theme.Color.ink)
                        Spacer()
                        Text(String(format: "%.1f %@", unit.fromKg(entry.kg), unit.short))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.Color.ink)
                    }
                    .padding(.vertical, 9)
                    if index < visible.count - 1 {
                        Rectangle().fill(Theme.Color.hairline).frame(height: 1)
                    }
                }
                if all.count > historyLimit {
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            showAllHistory.toggle()
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text(showAllHistory ? "Show less" : "Show all \(all.count)")
                            Image(systemName: showAllHistory ? "chevron.up" : "chevron.down")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(Theme.Color.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)
                        .padding(.bottom, 2)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func dateLabel(daysAgo: Int) -> String {
        if daysAgo == 0 { return "Today" }
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

// MARK: - Trend chart with target reference line

private struct WeightTrendChart: View {
    let values: [Double]
    let goal: Double
    var height: CGFloat = 150

    private var lo: Double { (min(values.min() ?? goal, goal)) - 1 }
    private var hi: Double { (max(values.max() ?? goal, goal)) + 1 }

    private func y(_ value: Double, in h: CGFloat) -> CGFloat {
        let span = max(hi - lo, 0.001)
        return h - CGFloat((value - lo) / span) * h
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let pts: [CGPoint] = values.enumerated().map { i, v in
                let x = values.count <= 1 ? 0 : w * CGFloat(i) / CGFloat(values.count - 1)
                return CGPoint(x: x, y: y(v, in: h))
            }
            ZStack {
                // gradient fill
                Path { p in
                    guard let first = pts.first else { return }
                    p.move(to: CGPoint(x: 0, y: h))
                    p.addLine(to: first)
                    for pt in pts.dropFirst() { p.addLine(to: pt) }
                    p.addLine(to: CGPoint(x: w, y: h))
                    p.closeSubpath()
                }
                .fill(LinearGradient(colors: [Theme.Color.ink.opacity(0.18), Theme.Color.ink.opacity(0)], startPoint: .top, endPoint: .bottom))

                // target reference line
                let gy = y(goal, in: h)
                Path { p in
                    p.move(to: CGPoint(x: 0, y: gy))
                    p.addLine(to: CGPoint(x: w, y: gy))
                }
                .stroke(Color(hex: 0x57C77B), style: StrokeStyle(lineWidth: 1.6, dash: [5, 4]))

                // main line
                Path { p in
                    guard let first = pts.first else { return }
                    p.move(to: first)
                    for pt in pts.dropFirst() { p.addLine(to: pt) }
                }
                .stroke(Theme.Color.ink, style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))

                // start dot
                if let first = pts.first {
                    Circle().fill(Theme.Color.surface)
                        .frame(width: 9, height: 9)
                        .overlay(Circle().stroke(Theme.Color.ink, lineWidth: 2))
                        .position(first)
                }
                // current dot
                if let last = pts.last {
                    Circle().fill(Theme.Color.accent)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(Theme.Color.surface, lineWidth: 2.5))
                        .position(last)
                }
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.82), value: values)
        }
        .frame(height: height)
    }
}

// MARK: - Log sheet

private struct LogWeightSheet: View {
    @Environment(\.dismiss) private var dismiss
    let current: Double
    let unit: WeightUnit
    var onSave: (Double) -> Void

    @State private var text: String

    init(current: Double, unit: WeightUnit, onSave: @escaping (Double) -> Void) {
        self.current = current
        self.unit = unit
        self.onSave = onSave
        _text = State(initialValue: String(format: "%.1f", current))
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("Today's weight")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Color.inkMuted)
                HStack(spacing: 8) {
                    TextField("0.0", text: $text)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .keyboardType(.decimalPad)
                    Text(unit.short)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.Color.inkMuted)
                }
                .padding(Theme.Spacing.md)
                .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Color.hairline, lineWidth: 1))
                Spacer()
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Color.background)
            .navigationTitle("Log Weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Theme.Color.inkMuted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let kg = Double(text.replacingOccurrences(of: ",", with: ".")), kg > 0 {
                            onSave(kg)
                        }
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.Color.ink)
                }
            }
        }
        .presentationDetents([.height(240)])
    }
}

// MARK: - Edit details sheet

private struct WeightDetailsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let start: Double
    let current: Double
    let goal: Double
    let unit: WeightUnit
    var onSave: (Double, Double, Double) -> Void

    @State private var startText: String
    @State private var currentText: String
    @State private var goalText: String

    init(start: Double, current: Double, goal: Double, unit: WeightUnit, onSave: @escaping (Double, Double, Double) -> Void) {
        self.start = start
        self.current = current
        self.goal = goal
        self.unit = unit
        self.onSave = onSave
        _startText = State(initialValue: String(format: "%.1f", start))
        _currentText = State(initialValue: String(format: "%.1f", current))
        _goalText = State(initialValue: String(format: "%.1f", goal))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.md) {
                field(title: "Starting weight", text: $startText)
                field(title: "Current weight", text: $currentText)
                field(title: "Target weight", text: $goalText, accent: true)
                Spacer()
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Color.background)
            .navigationTitle("Edit Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Theme.Color.inkMuted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let s = parse(startText) ?? start
                        let c = parse(currentText) ?? current
                        let g = parse(goalText) ?? goal
                        onSave(s, c, g)
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.Color.ink)
                }
            }
        }
        .presentationDetents([.height(360)])
    }

    private func parse(_ s: String) -> Double? {
        Double(s.replacingOccurrences(of: ",", with: "."))
    }

    private func field(title: String, text: Binding<String>, accent: Bool = false) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.Color.ink)
            Spacer()
            TextField("0.0", text: text)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
            Text(unit.short).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.Color.inkMuted)
        }
        .padding(Theme.Spacing.sm)
        .background(accent ? Theme.Color.accent.opacity(0.18) : Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.sm).stroke(Theme.Color.hairline, lineWidth: 1))
    }
}
