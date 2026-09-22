import Foundation
import Combine

@MainActor
final class HomeArrivalTimerService: ObservableObject {
    @Published var isActive = false
    @Published var remainingSeconds: Int = 0
    @Published var selectedDelay: TimeInterval = 10 * 60

    private var timer: Timer?
    private var endDate: Date?

    let presetDelays: [(label: String, seconds: TimeInterval)] = [
        ("5 min", 5 * 60),
        ("10 min", 10 * 60),
        ("15 min", 15 * 60),
        ("30 min", 30 * 60)
    ]

    func start(duration: TimeInterval) {
        cancel()
        selectedDelay = duration
        remainingSeconds = Int(duration)
        endDate = Date().addingTimeInterval(duration)
        isActive = true

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        isActive = false
        remainingSeconds = 0
        endDate = nil
    }

    func completeUnload() {
        cancel()
    }

    private func tick() {
        guard let endDate else { return }
        let remaining = Int(endDate.timeIntervalSinceNow)
        if remaining <= 0 {
            remainingSeconds = 0
            isActive = false
            timer?.invalidate()
            timer = nil
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
