import SwiftUI

enum ProviderCardActivityStyle: Sendable, Equatable {
    case compact
    case expanded

    var isCompact: Bool {
        self == .compact
    }
}

private enum ActivityHistoryRange: String, CaseIterable, Identifiable, Sendable {
    case week
    case month
    case quarter

    var id: String { rawValue }

    var shortTitle: String {
        switch self {
        case .week: "7D"
        case .month: "30D"
        case .quarter: "3M"
        }
    }

    var dayCount: Int {
        switch self {
        case .week: 7
        case .month: 30
        case .quarter: 90
        }
    }

    var summaryTitle: String {
        switch self {
        case .week: "7 days"
        case .month: "30 days"
        case .quarter: "3 months"
        }
    }
}

struct ProviderUsageCard: View {
    let provider: ProviderID
    let state: ProviderLoadState
    let displayMode: UsageDisplayMode
    var activityStyle: ProviderCardActivityStyle = .compact
    var openWindow: (@MainActor () -> Void)? = nil
    @State private var showsResetCredits = false
    @State private var activityRange: ActivityHistoryRange = .week

    private let staleInterval: TimeInterval = 10 * 60

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: activityStyle.isCompact ? 6 : 13) {
                header(at: context.date)

                if let snapshot = state.snapshot {
                    if let message = state.errorMessage {
                        ErrorCallout(message: message)
                    }

                    snapshotContent(snapshot, now: context.date)
                } else {
                    placeholder
                }
            }
            .padding(activityStyle.isCompact ? 8 : 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modelMeterGlass(
                style: .regular,
                tint: provider.tint.opacity(0.08),
                cornerRadius: activityStyle.isCompact ? 12 : 18
            )
            .overlay {
                ModelMeterInstrumentFrame(
                    tint: provider.tint,
                    cornerRadius: activityStyle.isCompact ? 12 : 18
                )
            }
        }
    }

    private func header(at date: Date) -> some View {
        let iconSize: CGFloat = activityStyle.isCompact ? 24 : 32

        return HStack(spacing: activityStyle.isCompact ? 6 : 10) {
            ProviderBrandIcon(provider: provider, size: iconSize)

            if activityStyle.isCompact {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(provider.displayName.uppercased())
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(0.45)

                    Text((state.snapshot?.plan ?? "CLI").uppercased())
                        .font(.system(size: 7.5, weight: .semibold, design: .monospaced))
                        .tracking(0.35)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(.primary.opacity(0.045), in: Capsule())
                        .help(accountDescription(state.snapshot))
                }
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text(provider.displayName)
                        .font(.headline)

                    Text(expandedAccountDescription(state.snapshot))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: activityStyle.isCompact ? 4 : 8)

            statusBadge(at: date)

            if let openWindow {
                Button(action: openWindow) {
                    Image(systemName: "arrow.up.right.square")
                }
                .modelMeterGlassButton()
                .controlSize(.mini)
                .frame(
                    width: activityStyle.isCompact ? 28 : nil,
                    height: activityStyle.isCompact ? 28 : nil
                )
                .help("Open \(provider.displayName) window")
                .accessibilityLabel("Open \(provider.displayName) window")
            }
        }
    }

    @ViewBuilder
    private func statusBadge(at date: Date) -> some View {
        switch state {
        case .loading:
            StatusBadge(
                title: "Refreshing",
                color: provider.tint,
                showsProgress: true,
                compact: activityStyle.isCompact
            )
        case .failed(_, let previous):
            StatusBadge(
                title: previous == nil ? "Error" : "Stale",
                color: previous == nil ? .red : .orange,
                systemImage: previous == nil ? "exclamationmark" : "clock",
                compact: activityStyle.isCompact
            )
        case .loaded(let snapshot) where isStale(snapshot, at: date):
            StatusBadge(
                title: "Stale",
                color: .orange,
                systemImage: "clock",
                compact: activityStyle.isCompact
            )
        case .loaded:
            StatusBadge(
                title: activityStyle.isCompact ? "Live" : "Current",
                color: .green,
                systemImage: "checkmark",
                compact: activityStyle.isCompact
            )
        case .idle:
            EmptyView()
        }
    }

    @ViewBuilder
    private var placeholder: some View {
        switch state {
        case .idle:
            PlaceholderView(
                systemImage: "clock.badge.questionmark",
                title: "Not checked yet",
                detail: "Refresh to read \(provider.displayName) usage."
            )
        case .loading:
            VStack(spacing: 9) {
                ProgressView()
                    .controlSize(.small)
                Text("Checking \(provider.displayName) usage…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        case .failed(let message, _):
            PlaceholderView(
                systemImage: "exclamationmark.triangle.fill",
                title: "Usage unavailable",
                detail: message,
                color: .red
            )
        case .loaded:
            EmptyView()
        }
    }

    @ViewBuilder
    private func snapshotContent(_ snapshot: ProviderUsageSnapshot, now: Date) -> some View {
        let metrics = activityMetrics(snapshot.activity)

        VStack(alignment: .leading, spacing: activityStyle.isCompact ? 6 : 13) {
            if snapshot.limits.isEmpty {
                Label("No quota windows reported", systemImage: "gauge.with.dots.needle.0percent")
                    .font(activityStyle.isCompact ? .caption : .callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, activityStyle.isCompact ? 2 : 4)
            } else {
                quotaGaugeShelf(snapshot.limits, now: now)
            }

            if activityStyle == .expanded,
               provider == .codex,
               let resetCredits = snapshot.resetCredits {
                Divider()
                resetCreditsSection(resetCredits, now: now)
            }

            if activityStyle.isCompact {
                if !metrics.isEmpty
                    || !snapshot.activity.dailyTokens.isEmpty
                    || (provider == .codex && snapshot.resetCredits != nil) {
                    compactActivityPanel(
                        metrics,
                        activity: snapshot.activity,
                        resetCredits: provider == .codex ? snapshot.resetCredits : nil,
                        now: now
                    )
                }
            } else if !metrics.isEmpty || !snapshot.activity.dailyTokens.isEmpty {
                Divider()
                expandedActivityPanel(metrics, activity: snapshot.activity)
            }

            if let note = snapshot.note, !note.isEmpty {
                if activityStyle.isCompact {
                    Label(note, systemImage: "info.circle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help(note)
                        .accessibilityLabel(note)
                } else {
                    Label(note, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !activityStyle.isCompact {
                footer(snapshot, now: now)
            }
        }
    }

    private func quotaGaugeShelf(_ limits: [UsageLimit], now: Date) -> some View {
        let visibleLimits = compactVisibleLimits(in: limits)
        let columnCount = min(
            max(visibleLimits.count, 1),
            activityStyle.isCompact ? 4 : 4
        )
        let spacing: CGFloat = activityStyle.isCompact ? 5 : 10
        let columns = Array(
            repeating: GridItem(.flexible(minimum: 54), spacing: spacing, alignment: .top),
            count: columnCount
        )
        let hiddenCount = limits.count - visibleLimits.count

        return VStack(spacing: activityStyle.isCompact ? 5 : 9) {
            LazyVGrid(columns: columns, alignment: .center, spacing: spacing) {
                ForEach(visibleLimits) { limit in
                    quotaGauge(limit, now: now)
                }
            }

            if hiddenCount > 0, let openWindow {
                Button(action: openWindow) {
                    Label(
                        "\(hiddenCount) more quota \(hiddenCount == 1 ? "window" : "windows")",
                        systemImage: "ellipsis.circle"
                    )
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(provider.tint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
                .help("Open every \(provider.displayName) quota window")
            }
        }
    }

    private func compactVisibleLimits(in limits: [UsageLimit]) -> [UsageLimit] {
        guard activityStyle.isCompact, openWindow != nil, limits.count > 4 else {
            return limits
        }

        let visibleIDs = Set(
            limits
                .sorted { $0.usedFraction > $1.usedFraction }
                .prefix(4)
                .map(\.id)
        )
        return limits.filter { visibleIDs.contains($0.id) }
    }

    private func quotaGauge(_ limit: UsageLimit, now: Date) -> some View {
        let displayedFraction = displayMode.fraction(forUsedFraction: limit.usedFraction)
        let displayedPercent = Int((displayedFraction * 100).rounded())
        let details = resetDetails(for: limit, now: now)

        return QuotaGaugeView(
            title: gaugeTitle(for: limit),
            fraction: displayedFraction,
            percent: displayedPercent,
            metricWord: displayMode.metricWord,
            color: quotaColor(limit.usedFraction),
            resetLabel: compactResetLabel(for: limit, now: now),
            diameter: activityStyle.isCompact ? 50 : 68,
            compact: activityStyle.isCompact
        )
        .help(details ?? limit.title)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(provider.displayName) \(limit.title)")
        .accessibilityValue(
            quotaAccessibilityValue(
                displayedPercent: displayedPercent,
                limit: limit,
                details: details
            )
        )
    }

    private func expandedActivityPanel(
        _ metrics: [ActivityMetric],
        activity: UsageActivity
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Activity")
                    .font(.callout.weight(.semibold))

                if let scope = activity.scope {
                    activityScopeBadge(scope, compact: false)
                }

                Spacer()

                if !activity.dailyTokens.isEmpty {
                    Picker("Activity range", selection: $activityRange) {
                        ForEach(ActivityHistoryRange.allCases) { range in
                            Text(range.shortTitle).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.mini)
                    .frame(width: 142)
                    .help("Change activity graph range")
                }
            }

            if !activity.dailyTokens.isEmpty {
                ActivityTokenPulseView(
                    days: activity.dailyTokens,
                    tint: provider.tint,
                    range: activityRange
                )
            }

            if !metrics.isEmpty {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 8, alignment: .leading),
                        GridItem(.flexible(), spacing: 8, alignment: .leading),
                        GridItem(.flexible(), spacing: 8, alignment: .leading)
                    ],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(metrics) { metric in
                        ActivityMetricView(metric: metric, tint: provider.tint)
                    }
                }
            }
        }
    }

    private func compactActivityPanel(
        _ metrics: [ActivityMetric],
        activity: UsageActivity,
        resetCredits: UsageResetCredits?,
        now: Date
    ) -> some View {
        let columnCount: Int
        switch metrics.count {
        case 5...6:
            columnCount = 3
        case 7...:
            columnCount = 4
        default:
            columnCount = max(metrics.count, 1)
        }
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: 4, alignment: .leading),
            count: columnCount
        )

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(provider.tint)

                Text("Activity")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .textCase(.uppercase)
                    .tracking(0.7)
                    .foregroundStyle(.secondary)

                if let scope = activity.scope {
                    activityScopeBadge(scope, compact: true)
                }

                Spacer(minLength: 4)

                if !activity.dailyTokens.isEmpty {
                    CompactActivityRangeSwitch(selection: $activityRange)
                }

                if let resetCredits {
                    Button {
                        withAnimation(.snappy(duration: 0.22)) {
                            showsResetCredits.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.counterclockwise")
                            Text("\(resetCredits.availableCount)")
                                .monospacedDigit()
                            Text(resetCredits.availableCount == 1 ? "reset" : "resets")
                        }
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.green.opacity(0.11), in: Capsule())
                        .overlay(Capsule().stroke(.green.opacity(0.18), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .help(showsResetCredits ? "Hide reset credits" : "Show reset credits")
                    .accessibilityLabel("Usage limit resets")
                    .accessibilityValue(
                        "\(resetCredits.availableCount) available, \(showsResetCredits ? "expanded" : "collapsed")"
                    )
                    .accessibilityHint(
                        showsResetCredits
                            ? "Collapses reset credit details"
                            : "Expands reset credit details"
                    )
                }
            }

            if !activity.dailyTokens.isEmpty {
                CompactActivitySignalView(
                    days: activity.dailyTokens,
                    tint: provider.tint,
                    range: activityRange
                )
            }

            if !metrics.isEmpty {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
                    ForEach(metrics) { metric in
                        CompactActivityMetricView(metric: metric, tint: provider.tint)
                    }
                }
            }

            if showsResetCredits, let resetCredits {
                compactResetCreditDetails(resetCredits, now: now)
            }
        }
        .padding(5)
        .background(
            LinearGradient(
                colors: [provider.tint.opacity(0.075), .primary.opacity(0.018)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(provider.tint.opacity(0.14), lineWidth: 0.5)
        }
    }

    private func compactResetCreditDetails(
        _ resetCredits: UsageResetCredits,
        now: Date
    ) -> some View {
        VStack(spacing: 4) {
            ForEach(resetCredits.credits) { credit in
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.green)

                    Text(credit.title)
                        .font(.caption2.weight(.medium))
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    if let expiresAt = credit.expiresAt {
                        Text(expiryDetails(for: expiresAt, now: now))
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(.green.opacity(0.055), in: RoundedRectangle(cornerRadius: 5))
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func resetCreditsSection(_ resetCredits: UsageResetCredits, now: Date) -> some View {
        VStack(alignment: .leading, spacing: showsResetCredits ? 10 : 0) {
            Button {
                withAnimation(.snappy(duration: 0.24)) {
                    showsResetCredits.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.green)
                        .frame(width: 30, height: 30)
                        .background(
                            .green.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Usage limit resets")
                            .font(.callout.weight(.semibold))

                        if let nearestExpiry = resetCredits.credits
                            .compactMap(\.expiresAt)
                            .min() {
                            Text("Next expires \(nearestExpiry, style: .relative)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Granted reset credits")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 8)

                    Text("\(resetCredits.availableCount)")
                        .font(.system(.callout, design: .rounded, weight: .bold))
                        .foregroundStyle(.green)
                        .monospacedDigit()
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(.green.opacity(0.14), in: Capsule())

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(showsResetCredits ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(showsResetCredits ? "Collapse reset credits" : "Show reset credits")

            if showsResetCredits {
                VStack(spacing: 7) {
                    ForEach(resetCredits.credits) { credit in
                        HStack(spacing: 9) {
                            Image(systemName: "bolt.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.green)
                                .frame(width: 24, height: 24)
                                .background(.green.opacity(0.1), in: Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                Text(credit.title)
                                    .font(.callout.weight(.medium))

                                if let expiresAt = credit.expiresAt {
                                    Text(expiryDetails(for: expiresAt, now: now))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            .green.opacity(0.045),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Usage limit resets")
        .accessibilityValue(
            "\(resetCredits.availableCount) available, \(showsResetCredits ? "expanded" : "collapsed")"
        )
    }

    private func footer(_ snapshot: ProviderUsageSnapshot, now: Date) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: isStale(snapshot, at: now) ? "clock.badge.exclamationmark" : "clock")

            Text("Updated")
            Text(snapshot.fetchedAt, style: .relative)

            Spacer(minLength: 6)

            Text(sourceDescription(snapshot))
                .lineLimit(1)
                .truncationMode(.middle)
                .help(snapshot.source)
        }
        .font(.caption2)
        .foregroundStyle(.secondary.opacity(0.78))
    }

    private func isStale(_ snapshot: ProviderUsageSnapshot, at date: Date) -> Bool {
        date.timeIntervalSince(snapshot.fetchedAt) > staleInterval
    }

    private func quotaColor(_ fraction: Double) -> Color {
        switch fraction {
        case 0.9...:
            .red
        case 0.75...:
            .orange
        default:
            provider.tint
        }
    }

    private func formattedWindow(_ minutes: Int?) -> String? {
        guard let minutes else { return nil }

        if minutes.isMultiple(of: 1_440) {
            let days = minutes / 1_440
            return "\(days)d window"
        }

        if minutes.isMultiple(of: 60) {
            return "\(minutes / 60)h window"
        }

        return "\(minutes)m window"
    }

    private func resetDetails(for limit: UsageLimit, now: Date) -> String? {
        var parts: [String] = []

        if let resetsAt = limit.resetsAt {
            parts.append("Resets \(resetsAt.formatted(date: .abbreviated, time: .shortened))")
            parts.append(
                RelativeDateTimeFormatter().localizedString(for: resetsAt, relativeTo: now)
            )
        } else if let description = limit.resetDescription, !description.isEmpty {
            parts.append("Resets \(description)")
        }

        if let window = formattedWindow(limit.windowMinutes) {
            parts.append(window)
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func gaugeTitle(for limit: UsageLimit) -> String {
        guard activityStyle.isCompact else { return limit.title }

        var title = limit.title
            .replacingOccurrences(of: "5-hour", with: "5h", options: .caseInsensitive)
            .replacingOccurrences(of: "Weekly", with: "Wk", options: .caseInsensitive)
            .replacingOccurrences(of: "Monthly", with: "Mo", options: .caseInsensitive)
        let providerPrefix = "\(provider.displayName) · "
        if title.lowercased().hasPrefix(providerPrefix.lowercased()) {
            title.removeFirst(providerPrefix.count)
        }
        return title
    }

    private func compactResetLabel(for limit: UsageLimit, now: Date) -> String? {
        if let resetsAt = limit.resetsAt {
            let interval = resetsAt.timeIntervalSince(now)
            if interval <= 0 {
                return limit.usedFraction < 0.01 ? "reset complete" : "reset due"
            }

            if interval < 60 * 60 {
                return "in \(max(Int(ceil(interval / 60)), 1))m"
            }
            if interval < 24 * 60 * 60 {
                return "in \(max(Int(ceil(interval / (60 * 60))), 1))h"
            }
            if interval < 7 * 24 * 60 * 60 {
                return "in \(max(Int(ceil(interval / (24 * 60 * 60))), 1))d"
            }
            return resetsAt.formatted(date: .abbreviated, time: .omitted)
        }

        guard let description = limit.resetDescription?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !description.isEmpty else {
            return nil
        }

        return description
            .replacingOccurrences(of: "resets ", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "reset ", with: "", options: .caseInsensitive)
    }

    private func quotaAccessibilityValue(
        displayedPercent: Int,
        limit: UsageLimit,
        details: String?
    ) -> String {
        var parts = ["\(displayedPercent) percent \(displayMode.metricWord)"]

        if limit.usedFraction >= 0.9 {
            parts.append("Critical")
        } else if limit.usedFraction >= 0.75 {
            parts.append("Warning")
        }

        if let details {
            parts.append(details)
        }

        return parts.joined(separator: ", ")
    }

    private func expiryDetails(for date: Date, now: Date) -> String {
        let exact = date.formatted(date: .abbreviated, time: .omitted)
        let relative = RelativeDateTimeFormatter().localizedString(for: date, relativeTo: now)
        return "Expires \(exact) · \(relative)"
    }

    private func sourceDescription(_ snapshot: ProviderUsageSnapshot) -> String {
        guard let version = snapshot.cliVersion, !version.isEmpty else {
            return snapshot.source
        }

        return "CLI \(version)"
    }

    private func accountDescription(_ snapshot: ProviderUsageSnapshot?) -> String {
        guard let snapshot else { return "CLI usage" }
        let parts = [snapshot.plan, snapshot.account]
            .compactMap { $0 }
        return parts.isEmpty ? "CLI usage" : parts.joined(separator: " · ")
    }

    private func expandedAccountDescription(_ snapshot: ProviderUsageSnapshot?) -> String {
        accountDescription(snapshot)
    }

    private func activityScopeBadge(
        _ scope: UsageActivityScope,
        compact: Bool
    ) -> some View {
        Text(scope.label.uppercased())
            .font(
                .system(
                    size: compact ? 7 : 8,
                    weight: .bold,
                    design: .monospaced
                )
            )
            .tracking(0.35)
            .foregroundStyle(provider.tint)
            .padding(.horizontal, compact ? 4 : 5)
            .padding(.vertical, compact ? 1.5 : 2)
            .background(provider.tint.opacity(0.1), in: Capsule())
            .overlay(Capsule().stroke(provider.tint.opacity(0.18), lineWidth: 0.5))
            .help(scope.detail)
            .accessibilityLabel("Activity scope: \(scope.label)")
            .accessibilityHint(scope.detail)
    }

    func activityMetrics(_ activity: UsageActivity) -> [ActivityMetric] {
        var metrics: [ActivityMetric] = []

        if let tokens = activity.todayTokens {
            metrics.append(ActivityMetric(
                id: "todayTokens",
                systemImage: "calendar",
                title: "Today",
                value: formattedCount(tokens)
            ))
        }

        if let tokens = activity.lifetimeTokens {
            metrics.append(ActivityMetric(
                id: "lifetimeTokens",
                systemImage: "sum",
                title: provider == .claude ? "Local total" : "Lifetime",
                value: formattedCount(tokens)
            ))
        }

        if let tokens = activity.peakDailyTokens {
            metrics.append(ActivityMetric(
                id: "peakDailyTokens",
                systemImage: "chart.line.uptrend.xyaxis",
                title: "Peak day",
                value: formattedCount(tokens)
            ))
        }

        if let cost = activity.sessionCostUSD {
            metrics.append(ActivityMetric(
                id: "sessionCost",
                systemImage: "dollarsign.circle",
                title: "Session",
                value: cost.formatted(.currency(code: "USD").precision(.fractionLength(2)))
            ))
        }

        if let sessions = activity.activeSessions {
            metrics.append(ActivityMetric(
                id: "activeSessions",
                systemImage: "rectangle.stack",
                title: "Active sessions",
                value: sessions.formatted()
            ))
        }

        if let days = activity.currentStreakDays {
            metrics.append(ActivityMetric(
                id: "streak",
                systemImage: "flame",
                title: "Day streak",
                value: days.formatted()
            ))
        }

        if let days = activity.longestStreakDays {
            metrics.append(ActivityMetric(
                id: "longestStreak",
                systemImage: "trophy",
                title: "Best streak",
                value: days.formatted()
            ))
        }

        if let seconds = activity.longestRunningTurnSeconds {
            metrics.append(ActivityMetric(
                id: "longestRunningTurn",
                systemImage: "clock",
                title: "Longest turn",
                value: formattedDuration(seconds)
            ))
        }

        if let sessions = activity.totalSessions {
            metrics.append(ActivityMetric(
                id: "totalSessions",
                systemImage: "tray.full",
                title: provider == .claude ? "Local sessions" : "Total sessions",
                value: sessions.formatted(.number.notation(.compactName))
            ))
        }

        if let messages = activity.totalMessages {
            metrics.append(ActivityMetric(
                id: "totalMessages",
                systemImage: "bubble.left.and.bubble.right",
                title: provider == .claude ? "Local messages" : "Messages",
                value: messages.formatted(.number.notation(.compactName))
            ))
        }

        return metrics
    }

    private func formattedCount(_ value: Int64) -> String {
        value.formatted(.number.notation(.compactName))
    }

    private func formattedDuration(_ seconds: Int64) -> String {
        let seconds = max(seconds, 0)
        if seconds < 60 {
            return "\(seconds)s"
        }

        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)m"
        }

        let hours = minutes / 60
        if hours < 24 {
            let remainingMinutes = minutes % 60
            return remainingMinutes == 0
                ? "\(hours)h"
                : "\(hours)h \(remainingMinutes)m"
        }

        let days = hours / 24
        let remainingHours = hours % 24
        return remainingHours == 0
            ? "\(days)d"
            : "\(days)d \(remainingHours)h"
    }
}

extension ProviderID {
    var tint: Color {
        switch self {
        case .claude:
            .orange
        case .codex:
            .blue
        }
    }
}

private struct StatusBadge: View {
    let title: String
    let color: Color
    var systemImage: String? = nil
    var showsProgress = false
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 3 : 4) {
            if showsProgress {
                ProgressView()
                    .controlSize(.mini)
                    .tint(color)
                    .scaleEffect(compact ? 0.78 : 1)
            } else if let systemImage {
                if compact {
                    Circle()
                        .fill(color)
                        .frame(width: 5, height: 5)
                        .shadow(color: color.opacity(0.45), radius: 2)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 8, weight: .bold))
                }
            }

            Text(title)
        }
        .font(
            compact
                ? .system(size: 9, weight: .semibold, design: .rounded)
                : .caption2.weight(.semibold)
        )
        .foregroundStyle(color)
        .padding(.horizontal, compact ? 6 : 7)
        .padding(.vertical, compact ? 3 : 4)
        .background(color.opacity(0.12), in: Capsule())
        .overlay(Capsule().stroke(color.opacity(compact ? 0.18 : 0), lineWidth: 0.5))
    }
}

private struct ErrorCallout: View {
    let message: String

    var body: some View {
        Label {
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .font(.caption)
        .foregroundStyle(.red)
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.red.opacity(0.09), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct PlaceholderView: View {
    let systemImage: String
    let title: String
    let detail: String
    var color: Color = .secondary

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(color)

            Text(title)
                .font(.callout.weight(.semibold))

            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

struct ActivityMetric: Identifiable {
    let id: String
    let systemImage: String
    let title: String
    let value: String

    var compactTitle: String {
        switch id {
        case "activeSessions":
            "Active"
        case "streak":
            "Streak"
        case "totalSessions":
            "Sessions"
        default:
            title
        }
    }
}

private struct CompactActivityRangeSwitch: View {
    @Binding var selection: ActivityHistoryRange

    private let ranges: [ActivityHistoryRange] = [.week, .month]

    var body: some View {
        HStack(spacing: 1) {
            ForEach(ranges) { range in
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        selection = range
                    }
                } label: {
                    Text(range.shortTitle)
                        .font(.system(size: 7.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(selection == range ? Color.cyan : .secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(
                            selection == range ? Color.cyan.opacity(0.11) : .clear,
                            in: RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                        )
                        .overlay(alignment: .bottom) {
                            if selection == range {
                                Capsule()
                                    .fill(.cyan)
                                    .frame(width: 10, height: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(range.summaryTitle) of token history")
            }
        }
        .padding(1.5)
        .frame(width: 52, height: 18)
        .background(.primary.opacity(0.026), in: RoundedRectangle(cornerRadius: 5))
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(.primary.opacity(0.085), lineWidth: 0.5)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Activity history range")
        .accessibilityValue(selection.summaryTitle)
    }
}

private struct CompactActivitySignalView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    let days: [UsageActivityDay]
    let tint: Color
    let range: ActivityHistoryRange

    private var visibleDays: [UsageActivityDay] {
        Array(days.suffix(range.dayCount))
    }

    private var total: Int64 {
        visibleDays.reduce(Int64(0)) { $0 + max($1.tokens, 0) }
    }

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 5) {
                Text("TOKEN SIGNAL")
                    .font(.system(size: 7.5, weight: .semibold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 4)

                Text("\(formatted(total)) TOKENS")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(tint)
                    .monospacedDigit()
            }

            GeometryReader { geometry in
                let points = chartPoints(in: geometry.size)
                let line = signalPath(points)
                let area = signalArea(points, height: geometry.size.height)

                ZStack {
                    Canvas { context, size in
                        var grid = Path()
                        for index in 1...3 {
                            let y = size.height * CGFloat(index) / 4
                            grid.move(to: CGPoint(x: 0, y: y))
                            grid.addLine(to: CGPoint(x: size.width, y: y))
                        }
                        context.stroke(
                            grid,
                            with: .color(
                                .primary.opacity(contrast == .increased ? 0.12 : 0.055)
                            ),
                            style: StrokeStyle(
                                lineWidth: 0.5,
                                dash: [2, 4]
                            )
                        )
                    }

                    area
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.22), tint.opacity(0.015)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    line
                        .stroke(
                            tint.opacity(0.24),
                            style: StrokeStyle(
                                lineWidth: 5,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                        .blur(radius: 2)

                    line
                        .stroke(
                            LinearGradient(
                                colors: [tint.opacity(0.52), tint],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(
                                lineWidth: 1.6,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )

                    if let last = points.last {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [.clear, tint.opacity(0.3), .clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 0.7)
                            .position(x: last.x, y: geometry.size.height / 2)

                        Circle()
                            .fill(tint.opacity(0.2))
                            .frame(width: 9, height: 9)
                            .blur(radius: 1.5)
                            .position(last)

                        Circle()
                            .fill(tint)
                            .frame(width: 3.5, height: 3.5)
                            .overlay(Circle().stroke(.white.opacity(0.55), lineWidth: 0.5))
                            .shadow(color: tint.opacity(0.55), radius: 2)
                            .position(last)
                    }
                }
            }
            .frame(height: 42)
        }
        .frame(maxWidth: .infinity)
        .animation(
            reduceMotion ? nil : .snappy(duration: 0.3),
            value: range
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Token usage over the last \(range.summaryTitle)")
        .accessibilityValue("\(total) tokens")
    }

    private func chartPoints(in size: CGSize) -> [CGPoint] {
        guard !visibleDays.isEmpty else { return [] }
        let values = visibleDays.map { Double(max($0.tokens, 0)) }
        let maximum = max(values.max() ?? 0, 1)
        let horizontalStep = visibleDays.count > 1
            ? size.width / CGFloat(visibleDays.count - 1)
            : 0
        let topInset: CGFloat = 4
        let bottomInset: CGFloat = 4
        let drawableHeight = max(size.height - topInset - bottomInset, 1)

        return values.enumerated().map { index, value in
            let normalized = value / maximum
            return CGPoint(
                x: CGFloat(index) * horizontalStep,
                y: topInset + (drawableHeight * CGFloat(1 - normalized))
            )
        }
    }

    private func signalPath(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)

        for index in points.indices.dropFirst() {
            let previous = points[index - 1]
            let current = points[index]
            let controlX = (previous.x + current.x) / 2
            path.addCurve(
                to: current,
                control1: CGPoint(x: controlX, y: previous.y),
                control2: CGPoint(x: controlX, y: current.y)
            )
        }
        return path
    }

    private func signalArea(_ points: [CGPoint], height: CGFloat) -> Path {
        var path = signalPath(points)
        guard let first = points.first, let last = points.last else { return path }
        path.addLine(to: CGPoint(x: last.x, y: height))
        path.addLine(to: CGPoint(x: first.x, y: height))
        path.closeSubpath()
        return path
    }

    private func formatted(_ value: Int64) -> String {
        value.formatted(.number.notation(.compactName))
    }
}

private struct CompactActivityMetricView: View {
    let metric: ActivityMetric
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 3) {
                Image(systemName: metric.systemImage)
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(tint)

                Text(metric.compactTitle.uppercased())
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .tracking(0.35)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            Text(metric.value)
                .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 1.5)
        .frame(maxWidth: .infinity, minHeight: 27, alignment: .leading)
        .background(
            .primary.opacity(0.034),
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(.primary.opacity(0.065), lineWidth: 0.5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metric.title)
        .accessibilityValue(metric.value)
    }
}

private struct ActivityMetricView: View {
    let metric: ActivityMetric
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: metric.systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 22, height: 22)
                    .background(
                        tint.opacity(0.11),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )

                Text(metric.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Text(metric.value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            .primary.opacity(0.035),
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
    }
}

private struct ActivityPulseBucket: Identifiable {
    let startDate: Date
    let endDate: Date
    let tokens: Int64

    var id: Date { startDate }
}

private struct ActivityTokenPulseView: View {
    let days: [UsageActivityDay]
    let tint: Color
    let range: ActivityHistoryRange

    private var buckets: [ActivityPulseBucket] {
        let visibleDays = Array(days.suffix(range.dayCount))
        guard range == .quarter else {
            return visibleDays.map {
                ActivityPulseBucket(
                    startDate: $0.date,
                    endDate: $0.date,
                    tokens: $0.tokens
                )
            }
        }

        return stride(from: 0, to: visibleDays.count, by: 7).map { startIndex in
            let endIndex = min(startIndex + 7, visibleDays.count)
            let slice = visibleDays[startIndex..<endIndex]
            return ActivityPulseBucket(
                startDate: slice.first?.date ?? .distantPast,
                endDate: slice.last?.date ?? .distantPast,
                tokens: slice.reduce(Int64(0)) { $0 + $1.tokens }
            )
        }
    }

    private var maximum: Double {
        Double(max(buckets.map(\.tokens).max() ?? 0, 1))
    }

    private var total: Int64 {
        buckets.reduce(Int64(0)) { $0 + $1.tokens }
    }

    private var barSpacing: CGFloat {
        switch range {
        case .week: 7
        case .month: 2
        case .quarter: 5
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            GeometryReader { geometry in
                HStack(alignment: .bottom, spacing: barSpacing) {
                    ForEach(Array(buckets.enumerated()), id: \.element.id) { index, bucket in
                        let fraction = Double(bucket.tokens) / maximum
                        VStack(spacing: 5) {
                            Spacer(minLength: 0)

                            RoundedRectangle(
                                cornerRadius: range == .month ? 2 : 4,
                                style: .continuous
                            )
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            tint.opacity(bucket.tokens == 0 ? 0.12 : 0.38),
                                            tint.opacity(bucket.tokens == 0 ? 0.22 : 0.95)
                                        ],
                                        startPoint: .bottom,
                                        endPoint: .top
                                    )
                                )
                                .frame(
                                    height: max(
                                        4,
                                        (geometry.size.height - 19) * max(fraction, 0.025)
                                    )
                                )
                                .overlay(alignment: .top) {
                                    if Calendar.current.isDateInToday(bucket.endDate) {
                                        Capsule()
                                            .fill(.white.opacity(0.85))
                                            .frame(
                                                width: range == .month ? 3 : 9,
                                                height: 2
                                            )
                                            .padding(.top, 3)
                                    }
                                }
                                .help(tooltip(for: bucket))

                            Text(axisLabel(for: bucket, index: index))
                                .font(
                                    .system(
                                        size: range == .month ? 8 : 9,
                                        weight: .medium,
                                        design: .rounded
                                    )
                                )
                                .foregroundStyle(
                                    Calendar.current.isDateInToday(bucket.endDate)
                                        ? tint
                                        : .secondary
                                )
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .frame(height: 76)
            .animation(.snappy(duration: 0.28), value: range)

            HStack {
                Label(
                    range == .quarter ? "Tokens by week" : "Tokens by day",
                    systemImage: "waveform.path.ecg"
                )
                Spacer()
                Text(
                    "\(total.formatted(.number.notation(.compactName))) · \(range.summaryTitle)"
                )
                    .monospacedDigit()
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 11)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(
            LinearGradient(
                colors: [tint.opacity(0.09), tint.opacity(0.025)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(tint.opacity(0.13), lineWidth: 0.5)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Token usage over the last \(range.summaryTitle)")
        .accessibilityValue("\(total) tokens")
    }

    private func axisLabel(for bucket: ActivityPulseBucket, index: Int) -> String {
        switch range {
        case .week:
            bucket.startDate.formatted(.dateTime.weekday(.narrow))
        case .month:
            if index == 0 || index == buckets.count - 1 || index.isMultiple(of: 7) {
                bucket.startDate.formatted(.dateTime.day())
            } else {
                ""
            }
        case .quarter:
            if index == 0 || index == buckets.count - 1 || index.isMultiple(of: 2) {
                bucket.startDate.formatted(.dateTime.month(.abbreviated).day())
            } else {
                ""
            }
        }
    }

    private func tooltip(for bucket: ActivityPulseBucket) -> String {
        let count = bucket.tokens.formatted(.number.notation(.compactName))
        if Calendar.current.isDate(bucket.startDate, inSameDayAs: bucket.endDate) {
            return "\(bucket.startDate.formatted(date: .abbreviated, time: .omitted)): \(count) tokens"
        }
        return "\(bucket.startDate.formatted(date: .abbreviated, time: .omitted))–\(bucket.endDate.formatted(date: .abbreviated, time: .omitted)): \(count) tokens"
    }
}

private struct QuotaGaugeView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    let title: String
    let fraction: Double
    let percent: Int
    let metricWord: String
    let color: Color
    let resetLabel: String?
    let diameter: CGFloat
    let compact: Bool

    var body: some View {
        VStack(spacing: compact ? 3 : 5) {
            ZStack {
                Circle()
                    .stroke(
                        .primary.opacity(contrast == .increased ? 0.18 : 0.085),
                        lineWidth: compact ? 5 : 7
                    )

                Circle()
                    .stroke(
                        .primary.opacity(contrast == .increased ? 0.18 : 0.1),
                        style: StrokeStyle(
                            lineWidth: 0.7,
                            lineCap: .round,
                            dash: [1, compact ? 3.3 : 4.2]
                        )
                    )
                    .scaleEffect(1.13)

                Circle()
                    .trim(from: 0, to: min(max(fraction, 0), 1))
                    .stroke(
                        AngularGradient(
                            colors: [color.opacity(0.58), color, color.opacity(0.82)],
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(270)
                        ),
                        style: StrokeStyle(
                            lineWidth: compact ? 5 : 7,
                            lineCap: .round
                        )
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: color.opacity(0.3), radius: compact ? 2.5 : 3.5)

                VStack(spacing: -1) {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text("\(percent)")
                            .font(
                                .system(
                                    size: compact ? 15 : 19,
                                    weight: compact ? .medium : .semibold,
                                    design: .monospaced
                                )
                            )

                        Text("%")
                            .font(
                                .system(
                                    size: compact ? 8 : 10,
                                    weight: .medium,
                                    design: .rounded
                                )
                            )
                    }
                    .foregroundStyle(color)
                    .monospacedDigit()

                    Text(metricWord.uppercased())
                        .font(
                            .system(
                                size: compact ? 6.5 : 7,
                                weight: .semibold,
                                design: .rounded
                            )
                        )
                        .tracking(compact ? 0.65 : 0.8)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: diameter, height: diameter)

            Text(title)
                .font(
                    .system(
                        size: compact ? 9 : 11,
                        weight: .semibold,
                        design: .rounded
                    )
                )
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity)

            Group {
                if let resetLabel {
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: compact ? 7.5 : 8, weight: .semibold))

                        Text(resetLabel)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                } else {
                    Color.clear
                }
            }
            .font(.system(size: compact ? 8.5 : 9, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary.opacity(0.82))
            .frame(maxWidth: .infinity, minHeight: compact ? 10 : 11)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.top, compact ? 1 : 4)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: fraction)
    }
}
