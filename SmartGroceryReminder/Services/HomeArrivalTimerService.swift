import Foundation
import Combine

/// A running countdown, saved so it survives iOS killing and relaunching the app.
struct ArrivalTimerState: Codable, Equatable {
    let endDate: Date
    let duration: TimeInterval
}

@MainActor
final class HomeArrivalTimerService: ObservableObject {
    @Published var isActive = false
    @Published var remainingSeconds: Int = 0
    @Published var selectedDelay: TimeInterval = 10 * 60

    /// When the running countdown ends (also read by the widget); nil when none is running.
    @Published private(set) var endDate: Date?

    private var timer: Timer?
    private let store: JSONFileStore<ArrivalTimerState>?

    let presetDelays: [(label: String, seconds: TimeInterval)] = [
        ("5 min", 5 * 60),
        ("10 min", 10 * 60),
        ("15 min", 15 * 60),
        ("30 min", 30 * 60)
    ]

    /// - Parameter store: where a running countdown is saved; `nil` keeps it in memory.
    init(store: JSONFileStore<ArrivalTimerState>? = nil, now: Date = Date()) {
        self.store = store
        guard let store, case .loaded(let saved) = store.load(), saved.endDate > now else { return }
        selectedDelay = saved.duration
        endDate = saved.endDate
        isActive = true
        refresh(now: now)
        startTicking()
    }

    /// - Parameter startedAt: when the countdown began (the arrival), which can be earlier than now
    ///   when the arrival is handled late, e.g. after iOS relaunched the app.
    func start(duration: TimeInterval, startedAt: Date = Date()) {
        cancel()
        selectedDelay = duration
        endDate = startedAt.addingTimeInterval(duration)
        isActive = true
        refresh()
        guard isActive, let endDate else { return }
        try? store?.save(ArrivalTimerState(endDate: endDate, duration: duration))
        startTicking()
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        isActive = false
        remainingSeconds = 0
        endDate = nil
        store?.remove()
    }

    private func startTicking() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func completeUnload() {
        cancel()
    }

    /// Recomputes the countdown from `endDate`. Also called when the app returns to the
    /// foreground, since the Timer does not fire while suspended.
    func refresh(now: Date = Date()) {
        guard let endDate else { return }
        let remaining = Int(endDate.timeIntervalSince(now).rounded())
        if remaining <= 0 {
            remainingSeconds = 0
            isActive = false
            timer?.invalidate()
            timer = nil
            store?.remove()
        } else {
            remainingSeconds = remaining
        }
    }

    var formattedRemaining: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
