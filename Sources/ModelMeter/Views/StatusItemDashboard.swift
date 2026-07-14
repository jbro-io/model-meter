import AppKit
import SwiftUI

/// The compact, two-line dashboard rendered inside the menu-bar status item.
///
/// It intentionally shows one honest quota meter per provider rather than a
/// sparkline: the CLIs expose the current window value, but no time-series
/// samples from which a real history graph could be drawn.
@MainActor
struct StatusItemDashboard: View {
    static let minimumWidth: CGFloat = 156
    static let preferredHeight: CGFloat = 24

    private static let minimumLabelWidth: CGFloat = 44
    private static let nonLabelWidth: CGFloat = 112
    private static let textSize: CGFloat = 10

    @ObservedObject var store: UsageStore
    @ObservedObject var settings: AppSettings

    var body: some View {
        let rows = StatusItemPresentation.rows(
            states: store.states,
            displayMode: settings.usageDisplayMode
        )
        let labelWidth = Self.preferredLabelWidth(for: rows)

        VStack(spacing: 0) {
            ForEach(rows) { row in
                StatusItemProviderRow(
                    row: row,
                    displayMode: settings.usageDisplayMode,
                    labelWidth: labelWidth
                )
            }
        }
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity, minHeight: Self.preferredHeight, maxHeight: Self.preferredHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Model Meter usage")
    }

    static func preferredWidth(for rows: [StatusItemPresentation.Row]) -> CGFloat {
        ceil(nonLabelWidth + preferredLabelWidth(for: rows))
    }

    private static func preferredLabelWidth(
        for rows: [StatusItemPresentation.Row]
    ) -> CGFloat {
        let systemFont = NSFont.systemFont(ofSize: textSize, weight: .bold)
        let descriptor = systemFont.fontDescriptor.withDesign(.rounded)
            ?? systemFont.fontDescriptor
        let font = NSFont(descriptor: descriptor, size: textSize) ?? systemFont
        let measuredWidth = rows
            .map(\.windowLabel)
            .map { $0.uppercased() }
            .map { value in
                NSString(string: value).size(withAttributes: [.font: font]).width
            }
            .max() ?? 0

        // A little breathing room avoids edge clipping from fractional glyph metrics.
        return max(minimumLabelWidth, ceil(measuredWidth) + 8)
    }
}

/// Pure presentation mapping for the status item. Keeping this separate from
/// SwiftUI makes selection, compact labels, and Used/Remaining semantics easy
/// to verify without rendering a view.
struct StatusItemPresentation {
    struct Row: Equatable, Identifiable {
        let provider: ProviderID
        let windowLabel: String
        let displayedFraction: Double?
        let displayedPercent: Int?
        let isLoading: Bool
        let hasError: Bool

        var id: ProviderID { provider }

        // Short aliases are useful to view code and preserve a natural API for
        // clients that do not need the more explicit `displayed` terminology.
        var fraction: Double? { displayedFraction }
        var percent: Int? { displayedPercent }
    }

    static func rows(
        states: [ProviderID: ProviderLoadState],
        displayMode: UsageDisplayMode
    ) -> [Row] {
        ProviderID.allCases.map { provider in
            let state = states[provider]
            let candidate = state?.snapshot?.limits
                .map { limit in
                    let fraction = displayMode.fraction(
                        forUsedFraction: limit.usedFraction
                    )
                    return (
                        limit: limit,
                        fraction: fraction,
                        percent: Int((fraction * 100).rounded())
                    )
                }
                .filter { $0.percent > 0 }
                .max { lhs, rhs in
                    lhs.limit.usedFraction < rhs.limit.usedFraction
                }

            return Row(
                provider: provider,
                windowLabel: candidate.map {
                    compactWindowTitle($0.limit, provider: provider)
                } ?? "--",
                displayedFraction: candidate?.fraction,
                displayedPercent: candidate?.percent,
                isLoading: state?.isLoading ?? false,
                hasError: state?.errorMessage != nil
            )
        }
    }

    static func compactWindowTitle(
        _ limit: UsageLimit,
        provider: ProviderID? = nil
    ) -> String {
        var value = limit.title.trimmingCharacters(in: .whitespacesAndNewlines)

        value = value.replacingOccurrences(
            of: "5-hour",
            with: "5h",
            options: .caseInsensitive
        )
        value = value.replacingOccurrences(
            of: "Weekly",
            with: "Wk",
            options: .caseInsensitive
        )
        value = value.replacingOccurrences(
            of: "Monthly",
            with: "Mo",
            options: .caseInsensitive
        )
        value = value.replacingOccurrences(of: "·", with: " ")

        if value.isEmpty || value.caseInsensitiveCompare("Primary") == .orderedSame
            || value.caseInsensitiveCompare("Secondary") == .orderedSame
        {
            value = compactDuration(minutes: limit.windowMinutes) ?? "--"
        }

        var components = value
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        if let metricIndex = components.firstIndex(where: isWindowMetric) {
            let metric = components.remove(at: metricIndex)
            let identity = components.joined(separator: " ")
            let resolvedIdentity = identity.isEmpty ? provider?.displayName : identity
            return [resolvedIdentity, metric]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }

        return components.joined(separator: " ")
    }

    private static func isWindowMetric(_ value: String) -> Bool {
        let lowercased = value.lowercased()
        if lowercased == "wk" || lowercased == "mo" { return true }
        return lowercased.range(
            of: #"^\d+(?:\.\d+)?[mhdw]$"#,
            options: .regularExpression
        ) != nil
    }

    private static func compactDuration(minutes: Int?) -> String? {
        guard let minutes, minutes > 0 else { return nil }

        switch minutes {
        case 300:
            return "5h"
        case 10_080:
            return "Wk"
        case 43_200, 44_640:
            return "Mo"
        case let value where value.isMultiple(of: 1_440):
            return "\(value / 1_440)d"
        case let value where value.isMultiple(of: 60):
            return "\(value / 60)h"
        default:
            return "\(minutes)m"
        }
    }
}

private struct StatusItemProviderRow: View {
    let row: StatusItemPresentation.Row
    let displayMode: UsageDisplayMode
    let labelWidth: CGFloat

    private var tint: Color {
        switch row.provider {
        case .claude: .orange
        case .codex: .blue
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            providerMark

            Text(row.windowLabel.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.primary.opacity(row.fraction == nil ? 0.46 : 0.84))
                .lineLimit(1)
                .frame(width: labelWidth, alignment: .leading)

            SegmentedQuotaMeter(fraction: row.fraction, tint: tint)
                .frame(width: 46, height: 5)

            Text(row.percent.map { "\($0)%" } ?? "--")
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundStyle(row.fraction == nil ? .secondary : .primary)
                .monospacedDigit()
                .frame(width: 30, alignment: .trailing)
        }
        .padding(.horizontal, 3)
        .frame(maxWidth: .infinity, minHeight: 12, maxHeight: 12)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 3.5))
        .opacity(row.isLoading && row.fraction == nil ? 0.68 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var providerMark: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 3)
                .fill(tint.opacity(0.18))
                .frame(width: 13, height: 10)

            Image(systemName: row.provider.systemImage)
                .font(.system(size: 7.5, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 13, height: 10)

            if row.hasError {
                Circle()
                    .fill(.red)
                    .frame(width: 3.5, height: 3.5)
                    .overlay(Circle().stroke(.background, lineWidth: 0.6))
                    .offset(x: 1, y: -1)
            }
        }
        .frame(width: 13, height: 10)
    }

    private var accessibilityLabel: String {
        guard let percent = row.percent else {
            return "\(row.provider.displayName) usage unavailable"
        }
        return "\(row.provider.displayName), \(row.windowLabel), \(percent) percent \(displayMode.metricWord)"
    }
}

private struct SegmentedQuotaMeter: View {
    let fraction: Double?
    let tint: Color

    private let segmentCount = 10

    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<segmentCount, id: \.self) { index in
                segment(at: index)
            }
        }
        .accessibilityHidden(true)
    }

    private func segment(at index: Int) -> some View {
        let progress = segmentProgress(at: index)

        return GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.primary.opacity(0.12))

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.68), tint],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: proxy.size.width * progress)
            }
        }
    }

    private func segmentProgress(at index: Int) -> CGFloat {
        guard let fraction else { return 0 }
        let clamped = min(max(fraction, 0), 1)
        return CGFloat(min(max((clamped * Double(segmentCount)) - Double(index), 0), 1))
    }
}
