import SwiftUI

enum ProviderCardActivityStyle: Sendable {
    case compact
    case expanded
}

struct ProviderUsageCard: View {
    let provider: ProviderID
    let state: ProviderLoadState
    let displayMode: UsageDisplayMode
    var activityStyle: ProviderCardActivityStyle = .compact
    var openWindow: (@MainActor () -> Void)? = nil

    private let staleInterval: TimeInterval = 10 * 60

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 13) {
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
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modelMeterGlass(
                style: .regular,
                tint: provider.tint.opacity(0.08),
                cornerRadius: 18
            )
        }
    }

    private func header(at date: Date) -> some View {
        HStack(spacing: 10) {
            Image(systemName: provider.systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(provider.tint)
                .frame(width: 32, height: 32)
                .background(
                    LinearGradient(
                        colors: [provider.tint.opacity(0.22), provider.tint.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(provider.displayName)
                    .font(.headline)

                Text(state.snapshot?.plan ?? "CLI usage")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            statusBadge(at: date)

            if let openWindow {
                Button(action: openWindow) {
                    Image(systemName: "arrow.up.right.square")
                }
                .modelMeterGlassButton()
                .controlSize(.mini)
                .help("Open \(provider.displayName) window")
                .accessibilityLabel("Open \(provider.displayName) window")
            }
        }
    }

    @ViewBuilder
    private func statusBadge(at date: Date) -> some View {
        switch state {
        case .loading:
            StatusBadge(title: "Refreshing", color: provider.tint, showsProgress: true)
        case .failed(_, let previous):
            StatusBadge(
                title: previous == nil ? "Error" : "Stale",
                color: previous == nil ? .red : .orange,
                systemImage: previous == nil ? "exclamationmark" : "clock"
            )
        case .loaded(let snapshot) where isStale(snapshot, at: date):
            StatusBadge(title: "Stale", color: .orange, systemImage: "clock")
        case .loaded:
            StatusBadge(title: "Current", color: .green, systemImage: "checkmark")
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
        VStack(alignment: .leading, spacing: 13) {
            if snapshot.limits.isEmpty {
                Label("No quota windows reported", systemImage: "gauge.with.dots.needle.0percent")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 11) {
                    ForEach(snapshot.limits) { limit in
                        quotaRow(limit, now: now)
                    }
                }
            }

            if provider == .codex, let resetCredits = snapshot.resetCredits {
                Divider()
                resetCreditsSection(resetCredits, now: now)
            }

            let metrics = activityMetrics(snapshot.activity)
            if !metrics.isEmpty || !snapshot.activity.dailyTokens.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Activity")
                            .font(.callout.weight(.semibold))

                        Spacer()

                        if activityStyle == .expanded,
                           !snapshot.activity.dailyTokens.isEmpty {
                            Text("7-day pulse")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }

                    if activityStyle == .expanded,
                       !snapshot.activity.dailyTokens.isEmpty {
                        WeeklyTokenPulseView(
                            days: snapshot.activity.dailyTokens,
                            tint: provider.tint
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

            if let note = snapshot.note, !note.isEmpty {
                Label(note, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            footer(snapshot, now: now)
        }
    }

    private func quotaRow(_ limit: UsageLimit, now: Date) -> some View {
        let displayedFraction = displayMode.fraction(forUsedFraction: limit.usedFraction)
        let displayedPercent = Int((displayedFraction * 100).rounded())

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(limit.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text("\(displayedPercent)% \(displayMode.metricWord)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(quotaColor(limit.usedFraction))
                    .monospacedDigit()
            }

            QuotaProgressBar(
                fraction: displayedFraction,
                color: quotaColor(limit.usedFraction)
            )
                .accessibilityLabel(limit.title)
                .accessibilityValue("\(displayedPercent) percent \(displayMode.metricWord)")

            if let details = resetDetails(for: limit, now: now) {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .padding(.top, 1)
                    Text(details)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func resetCreditsSection(_ resetCredits: UsageResetCredits, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Usage limit resets")
                    .font(.callout.weight(.semibold))

                Spacer(minLength: 8)

                Text("\(resetCredits.availableCount) available")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.green.opacity(0.14), in: Capsule())
            }

            ForEach(resetCredits.credits) { credit in
                VStack(alignment: .leading, spacing: 2) {
                    Text(credit.title)
                        .font(.callout.weight(.medium))

                    if let expiresAt = credit.expiresAt {
                        Text(expiryDetails(for: expiresAt, now: now))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Usage limit resets")
        .accessibilityValue("\(resetCredits.availableCount) available")
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

    private func activityMetrics(_ activity: UsageActivity) -> [ActivityMetric] {
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
                title: "Lifetime",
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

        if let sessions = activity.totalSessions {
            metrics.append(ActivityMetric(
                id: "totalSessions",
                systemImage: "tray.full",
                title: "Total sessions",
                value: sessions.formatted(.number.notation(.compactName))
            ))
        }

        if let messages = activity.totalMessages {
            metrics.append(ActivityMetric(
                id: "totalMessages",
                systemImage: "bubble.left.and.bubble.right",
                title: "Messages",
                value: messages.formatted(.number.notation(.compactName))
            ))
        }

        return metrics
    }

    private func formattedCount(_ value: Int64) -> String {
        value.formatted(.number.notation(.compactName))
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

    var body: some View {
        HStack(spacing: 4) {
            if showsProgress {
                ProgressView()
                    .controlSize(.mini)
                    .tint(color)
            } else if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 8, weight: .bold))
            }

            Text(title)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(color.opacity(0.12), in: Capsule())
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

private struct ActivityMetric: Identifiable {
    let id: String
    let systemImage: String
    let title: String
    let value: String
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

private struct WeeklyTokenPulseView: View {
    let days: [UsageActivityDay]
    let tint: Color

    private var maximum: Double {
        Double(max(days.map(\.tokens).max() ?? 0, 1))
    }

    private var total: Int64 {
        days.reduce(Int64(0)) { $0 + $1.tokens }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            GeometryReader { geometry in
                HStack(alignment: .bottom, spacing: 7) {
                    ForEach(days) { day in
                        let fraction = Double(day.tokens) / maximum
                        VStack(spacing: 5) {
                            Spacer(minLength: 0)

                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            tint.opacity(day.tokens == 0 ? 0.12 : 0.38),
                                            tint.opacity(day.tokens == 0 ? 0.22 : 0.95)
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
                                    if Calendar.current.isDateInToday(day.date) {
                                        Capsule()
                                            .fill(.white.opacity(0.85))
                                            .frame(width: 9, height: 2)
                                            .padding(.top, 3)
                                    }
                                }
                                .help(
                                    "\(day.date.formatted(date: .abbreviated, time: .omitted)): \(day.tokens.formatted(.number.notation(.compactName))) tokens"
                                )

                            Text(day.date.formatted(.dateTime.weekday(.narrow)))
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                .foregroundStyle(
                                    Calendar.current.isDateInToday(day.date)
                                        ? tint
                                        : .secondary
                                )
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .frame(height: 76)

            HStack {
                Label("Tokens by day", systemImage: "waveform.path.ecg")
                Spacer()
                Text("\(total.formatted(.number.notation(.compactName))) this week")
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
        .accessibilityLabel("Token usage over the last seven days")
        .accessibilityValue("\(total) tokens this week")
    }
}

private struct QuotaProgressBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.primary.opacity(0.09))

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.72), color],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(
                        width: max(
                            fraction > 0 ? 3 : 0,
                            geometry.size.width * min(max(fraction, 0), 1)
                        )
                    )
            }
        }
        .frame(height: 7)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: fraction)
    }
}
