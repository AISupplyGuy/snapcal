import SwiftUI
import Charts

// The big immersive weight block on Insights. Built as a vertical
// composition because each card answers a different question:
//
//   1. Hero: "Where am I right now, and how is it trending?"
//   2. Chart: "What does the trajectory actually look like?" (interactive
//      scrubber so the user can inspect any day)
//   3. Projection: "If I keep going like this, where do I land — and
//      when?" (Pro-gated — reasoning that gets better with more data)
//   4. Net calories: "How does what I eat line up with what I burn?"
//      (uses HealthKit active energy from Apple Watch)
//   5. Quick log: one-tap CTA to add today's weight without leaving
//      Insights, because reviewing your trend is exactly the moment
//      you're motivated to step on the scale.
struct WeightInsightsSection: View {
    @State private var weightLog = WeightLog.shared
    @State private var weightGoalStore = WeightGoalStore.shared
    @State private var subs = Subscriptions.shared
    @State private var health = HealthKitService.shared

    @State private var scrubbedEntry: WeightEntry?
    @State private var showingLogWeight = false
    @State private var dailyActiveEnergy: [(date: Date, kcal: Double)] = []
    @State private var paywallTrigger: PaywallTrigger?

    @AppStorage(ProfilePrefsKeys.weightUnit) private var weightUnitRaw = WeightUnit.pounds.rawValue
    private var weightUnit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .pounds }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader
            heroCard
            chartCard
            projectionCard
            netCaloriesCard
        }
        .sheet(isPresented: $showingLogWeight) {
            LogWeightSheet()
                .presentationDetents([.medium])
        }
        .sheet(item: $paywallTrigger) { trigger in
            PaywallSheet(trigger: trigger.eyebrow, valueProps: trigger.valueProps)
                .presentationDetents([.large])
        }
        .task {
            if health.authState == .granted {
                dailyActiveEnergy = await health.dailyActiveEnergy(days: 30)
            }
        }
    }

    // MARK: Header

    private var sectionHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("WEIGHT")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.0)
                    .foregroundStyle(SCTheme.Colors.proteinBlue)
                Text("Trajectory")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .tracking(-0.4)
                    .foregroundStyle(.primary)
            }
            Spacer()
            Button {
                showingLogWeight = true
            } label: {
                Label("Log", systemImage: "plus")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(SCTheme.Gradients.cta, in: Capsule())
                    .shadow(color: SCTheme.Colors.accentPink.opacity(0.3), radius: 6, y: 3)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Hero

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let latest = weightLog.latest {
                let display = weightUnit == .kilograms ? latest.kilograms : latest.pounds
                let deltaWeek = weightLog.change(overLastDays: 7, unit: weightUnit)
                let deltaMonth = weightLog.change(overLastDays: 30, unit: weightUnit)
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(String(format: "%.1f", display))
                        .font(.system(size: 56, weight: .heavy, design: .rounded))
                        .tracking(-1.0)
                        .foregroundStyle(SCTheme.Gradients.heroText)
                        .contentTransition(.numericText(value: display))
                        .animation(.easeOut(duration: 0.3), value: display)
                    Text(weightUnit.label)
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                    sparkline
                        .frame(width: 80, height: 40)
                }
                HStack(spacing: 14) {
                    deltaPill(label: "7-day", delta: deltaWeek)
                    deltaPill(label: "30-day", delta: deltaMonth)
                    Spacer(minLength: 0)
                }
                if let goal = weightGoalStore.goal {
                    goalProgressLine(goal: goal, currentKg: latest.kilograms)
                }
            } else {
                emptyHero
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .scCardStyle()
    }

    private var emptyHero: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Step on the scale.")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(.primary)
            Text("Log your first weight and the chart, projection, and net-calorie correlation light up immediately.")
                .font(SCTheme.Type_.body())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                showingLogWeight = true
            } label: {
                Label("Log weight", systemImage: "scalemass.fill")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(SCTheme.Gradients.cta, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
    }

    private func deltaPill(label: String, delta: Double?) -> some View {
        let value = delta ?? 0
        let positive = value > 0
        let zero = abs(value) < 0.05
        let symbol = zero ? "minus" : (positive ? "arrow.up.right" : "arrow.down.right")
        let tint: Color = zero ? .secondary : (positive ? SCTheme.Colors.accentPink : SCTheme.Colors.carbGreen)
        let formatted: String = delta == nil
            ? "—"
            : "\(positive ? "+" : "")\(String(format: "%.1f", value)) \(weightUnit.label)"
        return HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .heavy))
            Text(formatted)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(.primary)
            Text(label)
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.12), in: Capsule())
    }

    @ViewBuilder
    private func goalProgressLine(goal: WeightGoal, currentKg: Double) -> some View {
        let progress = goal.progress(currentKilograms: currentKg)
        let pct = Int((progress * 100).rounded())
        HStack(spacing: 8) {
            Image(systemName: "target")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(SCTheme.Colors.accentPink)
            Text("\(pct)% to your goal")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.top, 4)
    }

    // Tiny chart embedded in the hero. Last 14 entries, no axes — pure
    // shape signal.
    @ViewBuilder
    private var sparkline: some View {
        let recent = Array(weightLog.entries.suffix(14))
        if recent.count >= 2 {
            Chart {
                ForEach(recent) { entry in
                    LineMark(
                        x: .value("d", entry.measuredAt),
                        y: .value("w", weightUnit == .kilograms ? entry.kilograms : entry.pounds)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(SCTheme.Colors.proteinBlue)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartPlotStyle { $0.background(.clear) }
        } else {
            EmptyView()
        }
    }

    // MARK: Big chart

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("LAST 30 DAYS")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.0)
                    .foregroundStyle(.secondary)
                Spacer()
                if let scrubbed = scrubbedEntry {
                    let v = weightUnit == .kilograms ? scrubbed.kilograms : scrubbed.pounds
                    Text("\(String(format: "%.1f", v)) \(weightUnit.label) · \(scrubbedDateLabel(scrubbed.measuredAt))")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(SCTheme.Colors.accentPink)
                        .transition(.opacity)
                }
            }

            if weightLog.entries.count >= 2 {
                bigChart
            } else {
                Text("Two weigh-ins lights up the trend chart.")
                    .font(SCTheme.Type_.caption())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 160, alignment: .leading)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .scCardStyle()
    }

    private var bigChart: some View {
        let entries = Array(weightLog.entries.suffix(30))
        let goalKg = weightGoalStore.goal?.targetKilograms
        let goalDisplay = goalKg.map { weightUnit == .kilograms ? $0 : $0 * 2.20462 }
        return Chart {
            ForEach(entries) { entry in
                let v = weightUnit == .kilograms ? entry.kilograms : entry.pounds
                AreaMark(
                    x: .value("Date", entry.measuredAt),
                    y: .value("Weight", v)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(LinearGradient(
                    colors: [SCTheme.Colors.proteinBlue.opacity(0.22), SCTheme.Colors.proteinBlue.opacity(0.0)],
                    startPoint: .top, endPoint: .bottom
                ))
                LineMark(
                    x: .value("Date", entry.measuredAt),
                    y: .value("Weight", v)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(SCTheme.Colors.proteinBlue)
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                PointMark(
                    x: .value("Date", entry.measuredAt),
                    y: .value("Weight", v)
                )
                .foregroundStyle(SCTheme.Colors.proteinBlue)
                .symbolSize(scrubbedEntry?.id == entry.id ? 80 : 24)
            }
            if let goalDisplay {
                RuleMark(y: .value("Goal", goalDisplay))
                    .foregroundStyle(SCTheme.Colors.accentPink.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Goal \(String(format: "%.1f", goalDisplay))")
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .foregroundStyle(SCTheme.Colors.accentPink)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(SCTheme.Colors.accentPink.opacity(0.14), in: Capsule())
                    }
            }
        }
        .frame(height: 200)
        .clipped()
        .chartYScale(domain: chartYDomain(entries: entries, goalDisplay: goalDisplay))
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: max(1, entries.count / 5))) { _ in
                AxisGridLine().foregroundStyle(.clear)
                AxisTick().foregroundStyle(.primary.opacity(0.15))
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(.primary.opacity(0.06))
                AxisValueLabel()
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard let plotFrame = proxy.plotFrame else { return }
                                let x = value.location.x - geo[plotFrame].minX
                                if let date: Date = proxy.value(atX: x) {
                                    scrubbedEntry = nearest(to: date, in: entries)
                                }
                            }
                            .onEnded { _ in
                                // Linger a beat then clear.
                                Task { @MainActor in
                                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                                    withAnimation { scrubbedEntry = nil }
                                }
                            }
                    )
            }
        }
    }

    private func chartYDomain(entries: [WeightEntry], goalDisplay: Double?) -> ClosedRange<Double> {
        let values = entries.map { weightUnit == .kilograms ? $0.kilograms : $0.pounds }
        var low = values.min() ?? 0
        var high = values.max() ?? 1
        if let goalDisplay {
            low = min(low, goalDisplay)
            high = max(high, goalDisplay)
        }
        let pad = max((high - low) * 0.15, weightUnit == .kilograms ? 0.5 : 1.0)
        return (low - pad)...(high + pad)
    }

    private func nearest(to date: Date, in entries: [WeightEntry]) -> WeightEntry? {
        entries.min(by: {
            abs($0.measuredAt.timeIntervalSince(date)) < abs($1.measuredAt.timeIntervalSince(date))
        })
    }

    private func scrubbedDateLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMd")
        return f.string(from: date)
    }

    // MARK: Projection (Pro)

    private var projectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(SCTheme.Colors.accentPink)
                Text("PROJECTION")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.0)
                    .foregroundStyle(.secondary)
                Spacer()
                if !subs.isPro {
                    proPill
                }
            }

            if subs.isPro {
                projectionContent
            } else {
                projectionTeaser
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .scCardStyle()
    }

    private var proPill: some View {
        HStack(spacing: 4) {
            Image(systemName: "lock.fill")
                .font(.system(size: 9, weight: .heavy))
            Text("PRO")
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .tracking(1.0)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(SCTheme.Gradients.cta, in: Capsule())
    }

    @ViewBuilder
    private var projectionContent: some View {
        if let projection = computeProjection() {
            VStack(alignment: .leading, spacing: 6) {
                Text(projection.headline)
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(projection.subhead)
                    .font(SCTheme.Type_.body())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Text("Log at least 3 weights so we can detect a trend.")
                .font(SCTheme.Type_.body())
                .foregroundStyle(.secondary)
        }
    }

    private var projectionTeaser: some View {
        Button {
            paywallTrigger = .insightsProjection
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text("See where you'll land in 4, 8, 12 weeks")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Pro analyzes your weight pace + Apple Watch active energy and projects your trajectory.")
                    .font(SCTheme.Type_.caption())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 4) {
                    Text("Unlock projections")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .heavy))
                }
                .foregroundStyle(SCTheme.Colors.accentPink)
            }
        }
        .buttonStyle(.plain)
    }

    private struct Projection {
        let headline: String
        let subhead: String
    }

    // Linear regression on the last 30 entries' (day-index, weight) pairs.
    // Linear is the right shape here — biological weight trends over weeks
    // are basically linear within a phase. Once the slope changes phase,
    // the rolling window moves on too.
    private func computeProjection() -> Projection? {
        let recent = Array(weightLog.entries.suffix(30))
        guard recent.count >= 3, let first = recent.first, let last = recent.last else { return nil }
        let xs = recent.map { $0.measuredAt.timeIntervalSince(first.measuredAt) / 86_400 }
        let ys = recent.map { weightUnit == .kilograms ? $0.kilograms : $0.pounds }
        let n = Double(xs.count)
        let sumX = xs.reduce(0, +)
        let sumY = ys.reduce(0, +)
        let sumXY = zip(xs, ys).reduce(0) { $0 + $1.0 * $1.1 }
        let sumXX = xs.reduce(0) { $0 + $1 * $1 }
        let denom = n * sumXX - sumX * sumX
        guard abs(denom) > 0.0001 else { return nil }
        let slope = (n * sumXY - sumX * sumY) / denom        // units/day
        let intercept = (sumY - slope * sumX) / n
        let lastX = xs.last ?? 0
        let projectedIn = { (days: Double) -> Double in intercept + slope * (lastX + days) }

        let inFour = projectedIn(28)
        let inTwelve = projectedIn(84)
        let weeklyPace = slope * 7
        let direction = slope < -0.005 ? "losing" : (slope > 0.005 ? "gaining" : "holding")
        let paceCopy: String = abs(weeklyPace) < 0.05
            ? "Holding within ±0.05 \(weightUnit.label)/week."
            : "About \(String(format: "%+.1f", weeklyPace)) \(weightUnit.label) per week."

        // If a goal exists, compute the date we'd hit it at this slope.
        if let goal = weightGoalStore.goal {
            let goalDisplay = weightUnit == .kilograms ? goal.targetKilograms : goal.targetKilograms * 2.20462
            let lastY = ys.last ?? 0
            let needed = goalDisplay - lastY
            if abs(slope) > 0.005, (needed / slope) > 0 {
                let daysToGoal = needed / slope
                let date = last.measuredAt.addingTimeInterval(daysToGoal * 86_400)
                let f = DateFormatter()
                f.setLocalizedDateFormatFromTemplate("MMMd y")
                return Projection(
                    headline: "On pace to hit \(String(format: "%.1f", goalDisplay)) \(weightUnit.label) by \(f.string(from: date))",
                    subhead: paceCopy
                )
            }
        }

        return Projection(
            headline: "In 12 weeks: \(String(format: "%.1f", inTwelve)) \(weightUnit.label) (\(direction))",
            subhead: "In 4 weeks: \(String(format: "%.1f", inFour)) \(weightUnit.label). \(paceCopy)"
        )
    }

    // MARK: Net calories card

    private var netCaloriesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(SCTheme.Colors.accentOrange)
                Text("NET CALORIES")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.0)
                    .foregroundStyle(.secondary)
                Spacer()
                if health.authState != .granted {
                    Text("Apple Health needed")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            if health.authState == .granted, !dailyActiveEnergy.isEmpty {
                netCaloriesContent
            } else {
                netCaloriesPrompt
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .scCardStyle()
    }

    @ViewBuilder
    private var netCaloriesContent: some View {
        let avgBurn = dailyActiveEnergy.map(\.kcal).reduce(0, +) / Double(max(1, dailyActiveEnergy.count))
        let burnDisplay = Int(avgBurn.rounded())
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(burnDisplay)")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(SCTheme.Colors.accentOrange)
                Text("kcal active / day")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Text("From your Apple Watch — averaged over the last 30 days. Subtract this from what you log to get your net.")
                .font(SCTheme.Type_.caption())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var netCaloriesPrompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Connect Apple Health to see net-calorie correlation.")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Text("We'll pull active energy from your Apple Watch and overlay it on your weight trend.")
                .font(SCTheme.Type_.caption())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
