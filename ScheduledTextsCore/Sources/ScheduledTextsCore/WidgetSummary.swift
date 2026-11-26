import Foundation

/// What the widgets show at one moment: how many texts are ready, and the
/// first few texts, ready ones first (oldest first), then the soonest later
/// ones. The same order as the app's list.
public struct WidgetSummary: Equatable {
    public var readyCount: Int
    public var totalCount: Int
    /// Up to `limit` texts, in list order.
    public var texts: [ScheduledMessage]

    public init(queue: MessageQueue, now: Date, limit: Int = 3) {
        let due = queue.due(at: now)
        let upcoming = queue.upcoming(at: now)
        readyCount = due.count
        totalCount = queue.messages.count
        texts = Array((due + upcoming).prefix(limit))
    }

    public var next: ScheduledMessage? { texts.first }
    /// How many texts didn't fit.
    public var moreCount: Int { max(totalCount - texts.count, 0) }

    /// When the widget has to change on its own: each time a text that
    /// isn't due yet comes due (it turns orange and moves up). Soonest
    /// first, at most `limit` of them.
    public static func changeDates(queue: MessageQueue, now: Date, limit: Int = 40) -> [Date] {
        var dates: [Date] = []
        for message in queue.upcoming(at: now) where dates.last != message.sendAt {
            dates.append(message.sendAt)
            if dates.count == limit { break }
        }
        return dates
    }
}

/// Links from the widgets into the app.
public enum DeepLink: Equatable {
    /// The list.
    case list
    /// New Text.
    case new
    /// One text: "Send this text?" when it's ready, otherwise the editor.
    case text(UUID)

    public static let scheme = "scheduledtexts"

    public var url: URL {
        switch self {
        case .list: return URL(string: "\(Self.scheme)://list")!
        case .new: return URL(string: "\(Self.scheme)://new")!
        case .text(let id): return URL(string: "\(Self.scheme)://text/\(id.uuidString)")!
        }
    }

    public init?(url: URL) {
        guard url.scheme == Self.scheme else { return nil }
        switch url.host {
        case "list": self = .list
        case "new": self = .new
        case "text":
            guard let id = UUID(uuidString: url.lastPathComponent) else { return nil }
            self = .text(id)
        default: return nil
        }
    }
}

/// Where the queue is saved, shared by the app and its widgets.
public enum SharedContainer {
    public static let appGroup = "group.com.quasarbright.ScheduledTexts"

    /// messages.json in the app group, or nil when the app group isn't set
    /// up (in tests, or a build signed without it).
    public static var messagesURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("messages.json")
    }
}
