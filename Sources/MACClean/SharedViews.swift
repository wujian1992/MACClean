import SwiftUI

struct HeaderView: View {
    let title: String
    let subtitle: String
    let actionTitle: String
    let actionIcon: String
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 34, weight: .bold))
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Button(action: action) {
                HStack(spacing: 9) {
                    if isBusy {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: actionIcon)
                    }
                    Text(actionTitle)
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Color.teal)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
        }
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(tint)
                Spacer()
            }

            Text(value)
                .font(.system(size: 26, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.08))
        )
    }
}

struct WorkStatusPanel: View {
    let mode: WorkMode
    let title: String
    let detail: String
    let progress: Double
    let activity: [ActivityLine]
    let tint: Color

    private var isActive: Bool {
        mode == .scanning || mode == .cleaning || mode == .uninstalling
    }

    var body: some View {
        HStack(spacing: 18) {
            ScannerOrb(mode: mode, progress: progress, tint: tint)
                .frame(width: 104, height: 104)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text(mode.displayTitle)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(tint.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    Text("\(Int((min(max(progress, 0), 1)) * 100))%")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Text(title)
                    .font(.system(size: 18, weight: .bold))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                ProgressView(value: min(max(progress, 0), 1))
                    .progressViewStyle(.linear)
                    .tint(tint)

                if !activity.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(activity.prefix(3)) { item in
                            ActivityChip(item: item)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }

            Spacer()

            if isActive {
                VStack(alignment: .trailing, spacing: 8) {
                    ForEach(activity.prefix(4)) { item in
                        HStack(spacing: 7) {
                            Circle()
                                .fill(tint)
                                .frame(width: 6, height: 6)
                            Text(item.title)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 220, alignment: .trailing)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .leading)
        .background(
            LinearGradient(
                colors: [tint.opacity(0.14), Color(nsColor: .controlBackgroundColor).opacity(0.78)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(tint.opacity(0.20)))
        .animation(.snappy(duration: 0.28), value: title)
        .animation(.snappy(duration: 0.28), value: activity)
    }
}

struct ScannerOrb: View {
    let mode: WorkMode
    let progress: Double
    let tint: Color

    private var isActive: Bool {
        mode == .scanning || mode == .cleaning || mode == .uninstalling
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            let seconds = timeline.date.timeIntervalSinceReferenceDate
            let rotation = isActive ? seconds * 170 : 0
            let pulse = isActive ? 0.92 + 0.08 * sin(seconds * 5) : 1

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [tint.opacity(0.28), tint.opacity(0.06), .clear],
                            center: .center,
                            startRadius: 8,
                            endRadius: 58
                        )
                    )
                    .scaleEffect(pulse)

                Circle()
                    .stroke(tint.opacity(0.12), lineWidth: 13)

                Circle()
                    .trim(from: 0, to: min(max(progress, 0.08), 1))
                    .stroke(
                        AngularGradient(colors: [tint.opacity(0.25), tint, .cyan, tint.opacity(0.35)], center: .center),
                        style: StrokeStyle(lineWidth: 13, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                Circle()
                    .trim(from: 0, to: 0.22)
                    .stroke(.white.opacity(isActive ? 0.75 : 0.18), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(rotation))
                    .padding(7)

                Circle()
                    .fill(.background.opacity(0.92))
                    .frame(width: 58, height: 58)
                    .shadow(color: tint.opacity(0.16), radius: 12, x: 0, y: 6)

                Image(systemName: mode.symbolName)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(tint)
                    .symbolEffect(.pulse, options: .repeating, value: isActive)
            }
        }
    }
}

struct ActivityChip: View {
    let item: ActivityLine

    var body: some View {
        Text(item.title)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.background.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.06)))
    }
}

struct SearchStatusPill: View {
    let query: String
    let count: Int

    var body: some View {
        TimelineView(.animation) { timeline in
            let opacity = 0.62 + 0.38 * abs(sin(timeline.date.timeIntervalSinceReferenceDate * 4))

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.teal)
                    .opacity(opacity)
                Text("正在筛选")
                    .fontWeight(.semibold)
                Text("\"\(query)\"")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(count) 个结果")
                    .foregroundStyle(.teal)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.teal.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.background.opacity(0.78))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.teal.opacity(0.20)))
        }
    }
}

struct RiskBadge: View {
    let risk: CleanupRisk

    var body: some View {
        Text(risk.rawValue)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(risk.tint)
            .background(risk.tint.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct EmptyStateView: View {
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.teal)
            Text(title)
                .font(.title3.weight(.bold))
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ErrorBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.red)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
