//
//  ProfileComponents.swift
//  VerraOS
//
//  Shared building blocks for the client profile hub: custom top bar, section
//  cards, and hand-drawn bar / line charts that match the editorial aesthetic.
//

import SwiftUI

/// Custom in-shell top bar with a themed back chevron. Used on the profile
/// dashboard and every module screen so the app's bottom nav stays intact.
struct ProfileTopBar: View {
    let title: String
    var subtitle: String? = nil
    var trailing: AnyView? = nil
    var onBack: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.Color.ink)
                    .frame(width: 42, height: 42)
                    .background(Theme.Color.surface, in: Circle())
                    .overlay(Circle().stroke(Theme.Color.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.Color.ink)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.Color.inkMuted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            if let trailing { trailing }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
    }
}

/// A titled card container used to group profile content sections.
struct SectionCard<Content: View>: View {
    let title: String
    var icon: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.Color.inkMuted)
                }
                Text(title.uppercased())
                    .font(.system(size: 11.5, weight: .bold))
                    .tracking(1.1)
                    .foregroundStyle(Theme.Color.inkMuted)
            }
            content()
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Color.hairline, lineWidth: 1))
        .cardShadow(0.6)
    }
}

/// A compact stat cell (label above, value below).
struct StatCell: View {
    let label: String
    let value: String
    var accent: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(Theme.Color.inkFaint)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(accent ? Theme.Color.accentInk : Theme.Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .padding(.horizontal, 13)
        .background(accent ? Theme.Color.accent : Theme.Color.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }
}

// MARK: - Bar chart

/// A hand-drawn bar chart with optional day labels.
struct BarChart: View {
    let values: [Double]
    var labels: [String] = []
    var tint: Color = Theme.Color.ink
    var height: CGFloat = 120

    private var maxValue: Double { max(values.max() ?? 1, 0.001) }

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    let isLast = index == values.count - 1
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isLast ? Theme.Color.accent : tint.opacity(0.82))
                        .frame(height: max(6, CGFloat(value / maxValue) * height))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: height, alignment: .bottom)

            if !labels.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(labels.enumerated()), id: \.offset) { _, label in
                        Text(label)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.Color.inkFaint)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
}

// MARK: - Line chart

/// A hand-drawn line chart with a soft gradient fill and end-point dot.
struct LineChart: View {
    let values: [Double]
    var tint: Color = Theme.Color.ink
    var height: CGFloat = 90
    /// Optional second (smoothed) series drawn dashed on top.
    var average: [Double]? = nil

    /// Maps the series to points within the given size.
    private func points(in size: CGSize, series: [Double]) -> [CGPoint] {
        let lo = values.min() ?? 0
        let hi = values.max() ?? 1
        let span = max(hi - lo, 0.001)
        return series.enumerated().map { index, value in
            let x = series.count <= 1 ? 0 : size.width * CGFloat(index) / CGFloat(series.count - 1)
            let y = size.height - CGFloat((value - lo) / span) * size.height
            return CGPoint(x: x, y: y)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size, series: values)
            let avgPts = average.map { points(in: geo.size, series: $0) }
            ZStack {
                // gradient fill under the line
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
                        colors: [tint.opacity(0.20), tint.opacity(0.0)],
                        startPoint: .top, endPoint: .bottom
                    )
                )

                // main line
                Path { p in
                    guard let first = pts.first else { return }
                    p.move(to: first)
                    for pt in pts.dropFirst() { p.addLine(to: pt) }
                }
                .stroke(tint, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))

                // optional moving average
                if let avgPts, avgPts.count == pts.count, let first = avgPts.first {
                    Path { p in
                        p.move(to: first)
                        for pt in avgPts.dropFirst() { p.addLine(to: pt) }
                    }
                    .stroke(Theme.Color.inkFaint, style: StrokeStyle(lineWidth: 1.6, dash: [4, 4]))
                }

                // end dot
                if let last = pts.last {
                    Circle()
                        .fill(Theme.Color.accent)
                        .frame(width: 9, height: 9)
                        .overlay(Circle().stroke(Theme.Color.surface, lineWidth: 2))
                        .position(last)
                }
            }
        }
        .frame(height: height)
    }
}
