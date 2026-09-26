import Foundation

/// How the reminders have been doing, computed on the device from the diagnostics log.
/// Nothing here leaves the phone.
struct ReminderStats: Equatable {
    var unloadScheduled = 0
    var unloadDone = 0
    var snoozed = 0
    var storeRemindersSent = 0
    /// Median minutes from an unload reminder being scheduled to the groceries being marked brought in.
    var medianMinutesToDone: Double?

    /// Done ÷ scheduled, capped at 1; nil until a reminder has been scheduled.
    var doneRate: Double? {
        guard unloadScheduled > 0 else { return nil }
        return min(1, Double(unloadDone) / Double(unloadScheduled))
    }

    /// Entries are read oldest first. Each "done" is paired with the latest earlier
    /// schedule that hasn't been paired yet; a "done" with no schedule is only counted.
    static func compute(from entries: [DiagnosticEntry]) -> ReminderStats {
        var stats = ReminderStats()
        var openSchedule: Date?
        var minutesToDone: [Double] = []

        for entry in entries.sorted(by: { $0.date < $1.date }) {
            switch entry.kind {
            case .unloadScheduled:
                stats.unloadScheduled += 1
                openSchedule = entry.date
            case .unloadDone:
                stats.unloadDone += 1
                if let scheduled = openSchedule {
                    minutesToDone.append(entry.date.timeIntervalSince(scheduled) / 60)
                    openSchedule = nil
                }
            case .snoozed:
                stats.snoozed += 1
            case .storeReminderSent:
                stats.storeRemindersSent += 1
            default:
                break
            }
        }

        stats.medianMinutesToDone = median(minutesToDone)
        return stats
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}
