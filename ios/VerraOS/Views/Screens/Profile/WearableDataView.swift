//
//  WearableDataView.swift
//  VerraOS
//

import SwiftUI

extension String {
    /// First word of the name, for compact subtitles / toasts.
    var firstWord: String { split(separator: " ").first.map(String.init) ?? self }
}

/// The window of data plotted across the Wearables tab.
enum WearableTimeframe: String, CaseIterable, Identifiable {
    case weekly = "Weekly"
    case monthly = "Monthly"

    var id: String { rawValue }

    /// Number of daily data points in this window.
    var days: Int {
        switch self {
        case .weekly: return 7
        case .monthly: return 30
        }
    }

    /// Short label describing the averaging window.
    var avgLabel: String {
        switch self {
        case .weekly: return "7-day avg"
        case .monthly: return "30-day avg"
        }
    }
}

struct WearableDataView: View {
    let client: Client
    /// When non-nil, charts only render if `true` (client experience reflecting
    /// their own connection state). `nil` always shows charts (trainer viewing
    /// the client's synced data).
    var connectionState: Bool? = nil
    var onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ProfileTopBar(title: "Wearables", subtitle: client.name.firstWord, onBack: onBack)
            ScrollView(showsIndicators: false) {
                VStack(spacing: Theme.Spacing.md) {
                    noConnectionPrompt
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.sm)
                .padding(.bottom, 100)
            }
        }
        .background(Theme.Color.background)
    }

    // MARK: - No connection prompt

    private var noConnectionPrompt: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(Theme.Color.surfaceMuted).frame(width: 64, height: 64)
                Image(systemName: "applewatch.slash")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Theme.Color.inkFaint)
            }
            Text("No data yet")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.Color.ink)
            Text("Connect a wearable from the Wearables menu to start tracking your sleep, heart rate, and activity here.")
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(Theme.Color.inkMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
        .padding(.horizontal, Theme.Spacing.lg)
        .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg).stroke(Theme.Color.hairline, lineWidth: 1))
        .padding(.top, Theme.Spacing.sm)
    }
}

// MARK: - Average cell

/// A big-number summary tile for one metric's average.
private struct AverageCell: View {
    let label: String
    let value: String
    let caption: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 7, height: 7)
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(Theme.Color.inkMuted)
            }
            Text(value)
                .font(.system(size: 23, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(caption)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Theme.Color.inkFaint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Color.hairline, lineWidth: 1))
        .cardShadow(0.5)
    }
}

// MARK: - Dynamic chart card

/// A metric card showing a current-value headline above a dynamic chart.
private struct DynamicChartCard: View {
    enum Style { case bars, line }

    let title: String
    let icon: String
    let headline: String
    let unit: String?
    let values: [Double]
    let tint: Color
    let style: Style

    var body: some View {
        SectionCard(title: title, icon: icon) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(headline)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Color.ink)
                    if let unit {
                        Text(unit)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.Color.inkMuted)
                    }
                    Spacer()
                    Text("now")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.Color.inkFaint)
                }
                switch style {
                case .bars:
                    GradientBarChart(values: values, tint: tint)
                case .line:
                    GradientLineChart(values: values, tint: tint)
                }
            }
        }
    }
}

// MARK: - Gradient bar chart

/// A lively gradient bar chart that animates and highlights the latest bar.
private struct GradientBarChart: View {
    let values: [Double]
    var tint: Color
    var height: CGFloat = 116

    @State private var grow: CGFloat = 0

    private var maxValue: Double { max(values.max() ?? 1, 0.001) }

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .bottom, spacing: barSpacing) {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    let isLast = index == values.count - 1
                    let h = max(5, CGFloat(value / maxValue) * height) * grow
                    RoundedRectangle(cornerRadius: 5)
                        .fill(
                            LinearGradient(
                                colors: isLast
                                    ? [Theme.Color.accent, Theme.Color.accent.opacity(0.7)]
                                    : [tint.opacity(0.9), tint.opacity(0.45)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .frame(height: h)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(width: geo.size.width, height: height, alignment: .bottom)
        }
        .frame(height: height)
        .onAppear {
            grow = 0
            withAnimation(.spring(response: 0.6, dampingFraction: 0.78)) { grow = 1 }
        }
        .onChange(of: values) { _, _ in
            grow = 0
            withAnimation(.spring(response: 0.6, dampingFraction: 0.78)) { grow = 1 }
        }
    }

    /// Tighter spacing for dense monthly series.
    private var barSpacing: CGFloat { values.count > 14 ? 3 : 7 }
}

// MARK: - Gradient line chart

/// A smooth gradient-filled line chart with a soft baseline and end dot.
private struct GradientLineChart: View {
    let values: [Double]
    var tint: Color
    var height: CGFloat = 116

    @State private var reveal: CGFloat = 0

    private func points(in size: CGSize) -> [CGPoint] {
        let lo = values.min() ?? 0
        let hi = values.max() ?? 1
        let span = max(hi - lo, 0.001)
        let pad: CGFloat = 8
        let usable = size.height - pad * 2
        return values.enumerated().map { index, value in
            let x = values.count <= 1 ? 0 : size.width * CGFloat(index) / CGFloat(values.count - 1)
            let y = pad + (usable - CGFloat((value - lo) / span) * usable)
            return CGPoint(x: x, y: y)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            ZStack {
                // soft baseline
                Path { p in
                    p.move(to: CGPoint(x: 0, y: geo.size.height - 1))
                    p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height - 1))
                }
                .stroke(Theme.Color.hairline, lineWidth: 1)

                // gradient fill
                Path { p in
                    guard let first = pts.first else { return }
                    p.move(to: CGPoint(x: 0, y: geo.size.height))
                    p.addLine(to: first)
                    for pt in pts.dropFirst() { p.addLine(to: pt) }
                    p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                    p.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(0.28), tint.opacity(0.0)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .opacity(reveal)

                // main line
                Path { p in
                    guard let first = pts.first else { return }
                    p.move(to: first)
                    for pt in pts.dropFirst() { p.addLine(to: pt) }
                }
                .trim(from: 0, to: reveal)
                .stroke(tint, style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))

                // end dot
                if let last = pts.last {
                    Circle()
                        .fill(Theme.Color.accent)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Theme.Color.surface, lineWidth: 2.5))
                        .position(last)
                        .opacity(reveal)
                }
            }
        }
        .frame(height: height)
        .onAppear {
            reveal = 0
            withAnimation(.easeOut(duration: 0.7)) { reveal = 1 }
        }
        .onChange(of: values) { _, _ in
            reveal = 0
            withAnimation(.easeOut(duration: 0.7)) { reveal = 1 }
        }
    }
}

// MARK: - Value bar chart (numbers shown)

/// A 7-day bar chart that prints each day's actual number above its bar.
private struct ValueBarChart: View {
    let values: [Double]
    var labels: [String]
    var tint: Color
    var height: CGFloat = 130

    private var maxValue: Double { max(values.max() ?? 1, 0.001) }

    var body: some View {
        HStack(alignment: .bottom, spacing: 7) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                let isLast = index == values.count - 1
                VStack(spacing: 6) {
                    Text(compact(value))
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundStyle(isLast ? Theme.Color.ink : Theme.Color.inkMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    RoundedRectangle(cornerRadius: 5)
                        .fill(
                            LinearGradient(
                                colors: isLast
                                    ? [Theme.Color.accent, Theme.Color.accent.opacity(0.7)]
                                    : [tint.opacity(0.9), tint.opacity(0.45)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .frame(height: max(6, CGFloat(value / maxValue) * height))
                    Text(index < labels.count ? labels[index] : "")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.Color.inkFaint)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// Compact thousands formatting, e.g. 8.4k.
    private func compact(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "%.1fk", value / 1000)
        }
        return "\(Int(value))"
    }
}
