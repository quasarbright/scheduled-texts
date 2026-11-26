import ScheduledTextsCore
import SwiftUI
import WidgetKit

@main
struct ScheduledTextsWidgets: WidgetBundle {
    var body: some Widget {
        ScheduledTextsWidget()
    }
}

/// One widget in every size: small and medium on the home screen, round
/// and wide on the lock screen.
struct ScheduledTextsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ScheduledTexts", provider: Provider()) { entry in
            WidgetView(entry: entry)
                .containerBackground(Color(.systemBackground), for: .widget)
        }
        .configurationDisplayName("Scheduled Texts")
        .description("Texts ready to send, and the ones coming up.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

struct Entry: TimelineEntry {
    let date: Date
    let summary: WidgetSummary
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry {
        Entry(date: Date(), summary: WidgetSummary(queue: Self.sample, now: Date()))
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        let queue = context.isPreview && Self.load().isEmpty ? Self.sample : Self.load()
        completion(Entry(date: Date(), summary: WidgetSummary(queue: queue, now: Date())))
    }

    /// An entry now, and one each time a text comes due. The app reloads
    /// the timeline whenever the list changes.
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let queue = Self.load()
        let now = Date()
        let dates = [now] + WidgetSummary.changeDates(queue: queue, now: now)
        let entries = dates.map { Entry(date: $0, summary: WidgetSummary(queue: queue, now: $0)) }
        completion(Timeline(entries: entries, policy: .never))
    }

    static func load() -> MessageQueue {
        guard let url = SharedContainer.messagesURL else { return MessageQueue() }
        return (try? MessageStorage.load(from: url)) ?? MessageQueue()
    }

    /// For the widget gallery when nothing is scheduled yet.
    static var sample: MessageQueue {
        let now = Date()
        return MessageQueue([
            ScheduledMessage(recipientName: "Kate Bell", recipientAddress: "555", body: "Happy birthday!! Hope it's a great one 🎉", sendAt: now.addingTimeInterval(-600)),
            ScheduledMessage(recipientName: "Mom", recipientAddress: "555", body: "Landed, will call after dinner", sendAt: now.addingTimeInterval(-60)),
            ScheduledMessage(recipientName: "Sam Ortiz", recipientAddress: "555", body: "Still on for climbing?", sendAt: now.addingTimeInterval(86_400 * 2)),
        ])
    }
}

// MARK: - Views

struct WidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: Entry

    var body: some View {
        switch family {
        case .systemMedium: MediumView(entry: entry)
        case .accessoryCircular: CircularView(entry: entry)
        case .accessoryRectangular: RectangularView(entry: entry)
        default: SmallView(entry: entry)
        }
    }
}

/// The app icon's clock in a speech bubble, so a widget never reads as a
/// text someone sent you.
struct Glyph: View {
    var size: CGFloat = 13
    var body: some View {
        Image("BubbleClock").resizable().renderingMode(.template).frame(width: size, height: size)
    }
}

/// "9:00 AM" for today, otherwise "Fri, 6:00 PM" or "Dec 3, 9:00 AM".
func shortTime(_ date: Date, now: Date) -> String {
    let full = SendTimeFormat.string(for: date, now: now)
    return full.hasPrefix("Today, ") ? String(full.dropFirst(7)) : full
}

struct WidgetLabel: View {
    let text: String
    var color: Color = .accentColor
    var body: some View {
        HStack(spacing: 4) {
            Glyph()
            Text(text).textCase(.uppercase)
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(color)
        .lineLimit(1)
    }
}

struct SmallView: View {
    let entry: Entry

    var body: some View {
        let summary = entry.summary
        if let text = summary.next {
            let ready = text.isDue(at: entry.date)
            VStack(alignment: .leading, spacing: 2) {
                if ready {
                    WidgetLabel(text: summary.readyCount > 1 ? "Ready · \(summary.readyCount)" : "Ready")
                } else {
                    WidgetLabel(text: "Next", color: .secondary)
                }
                Text(text.displayRecipient).font(.subheadline.weight(.semibold)).lineLimit(1).padding(.top, 4)
                Text(SendTimeFormat.string(for: text.sendAt, now: entry.date))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ready ? Color.orange : Color.secondary)
                    .lineLimit(1)
                Text(text.body).font(.caption).foregroundStyle(.secondary).lineLimit(3).padding(.top, 2)
                Spacer(minLength: 0)
                if !ready, let repeats = text.repeatSummary() {
                    HStack(spacing: 3) {
                        Image(systemName: "repeat")
                        Text(repeats)
                    }
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetURL(DeepLink.text(text.id).url)
        } else {
            NothingScheduledView(entry: entry)
        }
    }
}

struct NothingScheduledView: View {
    let entry: Entry
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            WidgetLabel(text: "Scheduled")
            Spacer(minLength: 0)
            Text("Nothing scheduled").font(.subheadline.weight(.semibold))
            Text("Tap to schedule one.").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(DeepLink.new.url)
    }
}

struct MediumView: View {
    let entry: Entry

    var body: some View {
        let summary = entry.summary
        if summary.texts.isEmpty {
            NothingScheduledView(entry: entry)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    WidgetLabel(text: "Scheduled Texts")
                    Spacer()
                    if summary.readyCount > 0 {
                        Text("\(summary.readyCount) ready")
                            .font(.caption2.weight(.bold)).textCase(.uppercase)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.bottom, 4)
                ForEach(summary.texts) { text in
                    Link(destination: DeepLink.text(text.id).url) {
                        row(text)
                    }
                    if text.id != summary.texts.last?.id { Divider() }
                }
                Spacer(minLength: 0)
                if summary.moreCount > 0 {
                    Text("+\(summary.moreCount) more").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .widgetURL(DeepLink.list.url)
        }
    }

    private func row(_ text: ScheduledMessage) -> some View {
        let ready = text.isDue(at: entry.date)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(text.displayRecipient).font(.subheadline.weight(.semibold)).lineLimit(1).layoutPriority(1)
            Text(text.body).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 4)
            Text(shortTime(text.sendAt, now: entry.date))
                .font(.caption.weight(.semibold))
                .foregroundStyle(ready ? Color.orange : Color.secondary)
                .lineLimit(1)
                .layoutPriority(1)
        }
        .padding(.vertical, 5)
    }
}

/// Lock screen, round: the clock bubble and how many are ready.
struct CircularView: View {
    let entry: Entry
    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 1) {
                Glyph(size: entry.summary.readyCount > 0 ? 18 : 24)
                if entry.summary.readyCount > 0 {
                    Text("\(entry.summary.readyCount)").font(.system(.body, design: .rounded).weight(.bold))
                }
            }
        }
        .widgetURL(entry.summary.next.map { DeepLink.text($0.id).url } ?? DeepLink.list.url)
    }
}

/// Lock screen, wide: "READY · 9:00 AM", then who and what.
struct RectangularView: View {
    let entry: Entry
    var body: some View {
        if let text = entry.summary.next {
            let ready = text.isDue(at: entry.date)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Glyph(size: 12)
                    Text("\(ready ? "Ready" : "Next") · \(shortTime(text.sendAt, now: entry.date))").textCase(.uppercase)
                }
                .font(.caption2.weight(.bold))
                Text(text.displayRecipient).font(.headline).lineLimit(1)
                Text(text.body).font(.caption).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(DeepLink.text(text.id).url)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) { Glyph(size: 12); Text("SCHEDULED") }.font(.caption2.weight(.bold))
                Text("Nothing scheduled").font(.headline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(DeepLink.new.url)
        }
    }
}
