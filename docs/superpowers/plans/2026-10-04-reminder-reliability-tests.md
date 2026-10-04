# Reminder Reliability Tests Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Put CoreLocation behind a `LocationManaging` seam and add a scenario-based reliability suite covering permission changes, region-monitoring failures, duplicate events and app relaunch, fixing any bugs the suite exposes.

**Architecture:** A small `LocationManaging` protocol that `CLLocationManager` adopts via an empty extension; `LocationService`'s `nonisolated` delegate methods become thin wrappers over `@MainActor` `handle…` methods that a test-only `FakeLocationManager` drives directly. `AppState` accepts an injected manager so scenarios run the whole app. Relaunch is simulated by building a second `AppState` on the same `stateDirectory`.

**Tech Stack:** Swift 5 mode, SwiftUI, CoreLocation, XCTest, XcodeGen (`project.yml`), GitHub Actions macOS runner (`.github/workflows/ios-ci.yml`).

**Spec:** No separate spec file. The design was agreed in the brainstorming conversation on 2026-10-04 and is reproduced in "Agreed design" below.

## Agreed design

- Option C: close the real gaps **and** present them as a showcase suite in `SmartGroceryReminderTests/Reliability/`, one file per lifecycle risk, test names written as scenarios.
- Approach 1: `LocationManaging` protocol + `FakeLocationManager`. The existing inert mode (`manager == nil`, `monitoredForTesting`) stays untouched so the ~90 existing tests don't change; merging the two paths is a later follow-up, out of scope.
- Known bug to fix test-first: `monitoringDidFailFor` only logs, so `systemRegionCount` stays stale and Reminder health stays green while a geofence is dead.
- No duplicate tests: where existing tests already cover a case (e.g. refused notification requests in `LocationEventTests`), the suite doesn't repeat it.
- If a scenario exposes broken behavior, the fix lands in the same PR with its failing test first.
- Delivery: one branch, one PR, merge on green CI (project's phased workflow).

## Global Constraints

- No Mac locally: tests run only in CI (`ios-ci.yml`, `xcodebuild ... build test` on a simulator). "Run the test" in this plan means: commit, push the branch, and read the run's conclusion with `gh run watch` / `gh run view --log-failed`. Batch several red/green steps per push where noted to save CI minutes.
- Tests never touch real geofences, notifications, or permission prompts (`AppState.forTesting` keeps `systemServices: false`).
- Production behavior must not change except the monitoring-failure bug fix (and any fix a failing scenario proves necessary).
- Match surrounding style: doc comments in plain sentences, `@MainActor` on test methods that touch `AppState`/`LocationService`, `waitUntil` for async polling, fixed dates over the real clock where the API allows it.
- New test files are picked up automatically: `project.yml` includes the whole `SmartGroceryReminderTests` folder, and CI regenerates the project.

## Review Focus

1. **Monitoring fails after the region was accepted** (real iOS adds the region to `monitoredRegions`, then fails asynchronously). The health count must drop. Pinned in Task 3.
2. **The same authorization callback twice** (iOS fires it on every launch). It must be one diagnostic, not one per callback. Pinned in Task 2.
3. **An enter delivered twice while the list is still loading** (relaunch replay). It must produce exactly one reminder. Pinned in Task 4.
4. **The app relaunches after the countdown should have ended.** No countdown and no repeat reminder. Pinned in Task 5.
5. **Corrupt state files on cold start.** The app starts clean and never crashes. Pinned in Task 5.

---

## File Structure

| File | Responsibility |
|---|---|
| Create `SmartGroceryReminder/Services/LocationManaging.swift` | The protocol and the `CLLocationManager` conformance |
| Modify `SmartGroceryReminder/Services/LocationService.swift` | Take `LocationManaging?`; delegate wrappers call `handle…` methods; the bug fix |
| Modify `SmartGroceryReminder/App/AppState.swift:73-101` | Optional `locationManager:` injection |
| Modify `SmartGroceryReminderTests/TestSupport.swift` | `forTesting(locationManager:)` |
| Create `SmartGroceryReminderTests/Reliability/FakeLocationManager.swift` | A scriptable fake plus helpers that drive the service |
| Create `SmartGroceryReminderTests/Reliability/ReliabilityFixtures.swift` | Shared places, a loaded-session builder, health helper |
| Create `…/Reliability/PermissionReliabilityTests.swift` | Permission scenarios |
| Create `…/Reliability/RegionMonitoringReliabilityTests.swift` | Monitoring scenarios and the bug fix |
| Create `…/Reliability/DuplicateEventReliabilityTests.swift` | Duplicate and flapping scenarios |
| Create `…/Reliability/RelaunchReliabilityTests.swift` | Cold-start scenarios |
| Modify `README.md` | A "Reliability suite" section |

---

### Task 0: Branch

- [ ] **Step 1:** `git checkout -b reminder-reliability-tests`

---

### Task 1: The `LocationManaging` seam, the fake and injection

**Files:**
- Create: `SmartGroceryReminder/Services/LocationManaging.swift`
- Modify: `SmartGroceryReminder/Services/LocationService.swift` (init, `manager` property, delegate extension at the bottom)
- Modify: `SmartGroceryReminder/App/AppState.swift` (init signature and the `LocationService(...)` line, ~line 101)
- Modify: `SmartGroceryReminderTests/TestSupport.swift`
- Create: `SmartGroceryReminderTests/Reliability/FakeLocationManager.swift`, `ReliabilityFixtures.swift`
- Test: `SmartGroceryReminderTests/Reliability/RegionMonitoringReliabilityTests.swift` (smoke test only, for now)

**Interfaces:**
- Produces: `protocol LocationManaging`; `LocationService.init(diagnostics:manager: LocationManaging?)`; `@MainActor` methods on `LocationService`: `handleAuthorizationChange(status:accuracy:)`, `handleMonitoringFailure(identifier:message:)`, `handleDidStartMonitoring(regionCount:)`, `handleRegionState(_:identifier:)`, `handleLocationFix(_:)`, `handleLocationError(message:)` (plus the existing `handleRegionTransition(identifier:transition:date:)`); `AppState.init(..., locationManager: LocationManaging? = nil)`; `AppState.forTesting(..., locationManager:)`; `FakeLocationManager` (API below); `Reliability` fixtures.

- [ ] **Step 1: Create the protocol**

```swift
// SmartGroceryReminder/Services/LocationManaging.swift
import CoreLocation

/// The parts of `CLLocationManager` that `LocationService` uses, so tests can stand in a fake
/// that scripts permission changes, monitoring failures and region events.
protocol LocationManaging: AnyObject {
    var delegate: CLLocationManagerDelegate? { get set }
    var desiredAccuracy: CLLocationAccuracy { get set }
    var authorizationStatus: CLAuthorizationStatus { get }
    var accuracyAuthorization: CLAccuracyAuthorization { get }
    var monitoredRegions: Set<CLRegion> { get }
    func requestAlwaysAuthorization()
    func requestLocation()
    func startMonitoring(for region: CLRegion)
    func stopMonitoring(for region: CLRegion)
    func requestState(for region: CLRegion)
}

extension CLLocationManager: LocationManaging {}
```

- [ ] **Step 2: Switch `LocationService` to the protocol**

Change the stored property and init:

```swift
    /// `nil` when inert (tests): nothing reaches iOS and no permission is requested.
    private let manager: LocationManaging?
```
```swift
    init(diagnostics: DiagnosticsLog? = nil, manager: LocationManaging? = CLLocationManager()) {
```
The rest of the init body is unchanged.

- [ ] **Step 3: Move the delegate logic into `handle…` methods**

Replace the whole `extension LocationService: CLLocationManagerDelegate { ... }` with the following. Behavior is identical, except that `handleMonitoringFailure` does **not** fix the bug yet (Task 3 does that, test first).

```swift
// MARK: - Delegate handling
// The delegate callbacks below only hop to the main actor; the logic lives here so tests can
// drive it with a fake manager.
extension LocationService {
    func handleAuthorizationChange(status: CLAuthorizationStatus, accuracy: CLAccuracyAuthorization) {
        guard status != authorizationStatus || accuracy != accuracyAuthorization else { return }
        authorizationStatus = status
        accuracyAuthorization = accuracy
        diagnostics.record(
            .permission,
            "Location access: \(Self.describe(status)), \(accuracy == .fullAccuracy ? "precise" : "approximate")"
        )
    }

    func handleLocationError(message: String) {
        diagnostics.record(.error, "Location fix failed: \(message)")
    }

    func handleMonitoringFailure(identifier: String, message: String) {
        diagnostics.record(.error, "Couldn't monitor \(Self.describe(regionIdentifier: identifier)): \(message)")
    }

    func handleDidStartMonitoring(regionCount: Int) {
        systemRegionCount = regionCount
    }

    func handleRegionState(_ state: CLRegionState, identifier: String) {
        guard regionStates[identifier] != state else { return }
        regionStates[identifier] = state
        diagnostics.record(
            .regionState,
            "\(Self.describe(regionIdentifier: identifier)): \(Self.describe(state))",
            placeId: RegionID.parse(identifier)?.placeId
        )
    }

    func handleLocationFix(_ coordinate: CLLocationCoordinate2D) {
        currentLocation = coordinate
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        let accuracy = manager.accuracyAuthorization
        Task { @MainActor in self.handleAuthorizationChange(status: status, accuracy: accuracy) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Required by requestLocation(). Transient "location unknown" errors are expected indoors.
        let message = error.localizedDescription
        Task { @MainActor in self.handleLocationError(message: message) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        let identifier = region?.identifier ?? "a region"
        let message = error.localizedDescription
        Task { @MainActor in self.handleMonitoringFailure(identifier: identifier, message: message) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) {
        manager.requestState(for: region)
        let count = manager.monitoredRegions.count
        Task { @MainActor in self.handleDidStartMonitoring(regionCount: count) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        // Also reported alongside every enter/exit; only the state is recorded, never an event.
        let identifier = region.identifier
        Task { @MainActor in self.handleRegionState(state, identifier: identifier) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        Task { @MainActor in self.handleLocationFix(coordinate) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        let identifier = region.identifier
        let date = Date()
        Task { @MainActor in self.handleRegionTransition(identifier: identifier, transition: .enter, date: date) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        let identifier = region.identifier
        let date = Date()
        Task { @MainActor in self.handleRegionTransition(identifier: identifier, transition: .exit, date: date) }
    }
}
```

The new extension is in the same file, so it can use `private let diagnostics` and the `private(set)` setters (`systemRegionCount`, `accuracyAuthorization`, `regionStates`) without changing their access.

- [ ] **Step 4: Inject into `AppState`**

Add a parameter after `showsTestTools`:

```swift
        showsTestTools: Bool = true,
        locationManager: LocationManaging? = nil
```
Document it in the parameter list:
```swift
    ///   - locationManager: replaces the system location manager (tests); `nil` follows `systemServices`.
```
Replace the `LocationService` line:
```swift
        self.locationService = LocationService(
            diagnostics: diagnostics,
            manager: locationManager ?? (systemServices ? CLLocationManager() : nil)
        )
```

- [ ] **Step 5: Thread it through `forTesting`**

In `TestSupport.swift`, add `locationManager: LocationManaging? = nil` as the last parameter of `forTesting` and pass `locationManager: locationManager` to `AppState(...)`. Update the doc comment: "Pass a `FakeLocationManager` to script what iOS reports."

- [ ] **Step 6: Write the fake**

```swift
// SmartGroceryReminderTests/Reliability/FakeLocationManager.swift
import CoreLocation
@testable import SmartGroceryReminder

/// Stands in for `CLLocationManager`. Like iOS, it accepts every region it's asked to monitor
/// straight away; failures (a scripted id, or going over the region limit) are reported later,
/// when a test calls `deliverMonitoringFailures(to:)`.
final class FakeLocationManager: LocationManaging {
    weak var delegate: CLLocationManagerDelegate?
    var desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyBest
    var authorizationStatus: CLAuthorizationStatus = .authorizedAlways
    var accuracyAuthorization: CLAccuracyAuthorization = .fullAccuracy
    private(set) var monitoredRegions: Set<CLRegion> = []

    /// iOS lets one app monitor at most 20 regions.
    var regionLimit = 20
    /// Region identifiers iOS will refuse to monitor.
    var failingRegionIds: Set<String> = []

    private(set) var startCalls: [String] = []
    private(set) var stopCalls: [String] = []
    private(set) var stateRequests: [String] = []
    private(set) var locationRequests = 0
    private(set) var authorizationRequests = 0

    func requestAlwaysAuthorization() { authorizationRequests += 1 }
    func requestLocation() { locationRequests += 1 }

    func startMonitoring(for region: CLRegion) {
        startCalls.append(region.identifier)
        monitoredRegions.insert(region)
    }

    func stopMonitoring(for region: CLRegion) {
        stopCalls.append(region.identifier)
        monitoredRegions = monitoredRegions.filter { $0.identifier != region.identifier }
    }

    func requestState(for region: CLRegion) { stateRequests.append(region.identifier) }

    /// Regions iOS would refuse: scripted failures, then any over the limit (in start order).
    var regionsThatWillFail: [CLRegion] {
        let ordered = startCalls.compactMap { id in monitoredRegions.first { $0.identifier == id } }
        var unique: [CLRegion] = []
        for region in ordered where !unique.contains(where: { $0.identifier == region.identifier }) {
            unique.append(region)
        }
        let scripted = unique.filter { failingRegionIds.contains($0.identifier) }
        let rest = unique.filter { !failingRegionIds.contains($0.identifier) }
        return scripted + rest.dropFirst(regionLimit)
    }
}

@MainActor
extension FakeLocationManager {
    /// Drops the regions iOS refuses and reports each failure, the way `monitoringDidFailFor` would.
    func deliverMonitoringFailures(to service: LocationService) {
        for region in regionsThatWillFail {
            monitoredRegions = monitoredRegions.filter { $0.identifier != region.identifier }
            service.handleMonitoringFailure(identifier: region.identifier, message: "The operation couldn't be completed.")
        }
    }

    /// The user changes access in Settings; iOS then calls `locationManagerDidChangeAuthorization`.
    func changeAuthorization(to status: CLAuthorizationStatus, accuracy: CLAccuracyAuthorization = .fullAccuracy, on service: LocationService) {
        authorizationStatus = status
        accuracyAuthorization = accuracy
        service.handleAuthorizationChange(status: status, accuracy: accuracy)
    }

    /// iOS reports crossing into `place`'s geofence.
    func deliverEnter(_ place: GeoPlace, at date: Date = Date(), to service: LocationService) {
        service.handleRegionTransition(identifier: RegionID.make(for: place), transition: .enter, date: date)
    }

    func deliverExit(_ place: GeoPlace, at date: Date = Date(), to service: LocationService) {
        service.handleRegionTransition(identifier: RegionID.make(for: place), transition: .exit, date: date)
    }
}
```

- [ ] **Step 7: Write the shared fixtures**

```swift
// SmartGroceryReminderTests/Reliability/ReliabilityFixtures.swift
import XCTest
import CoreLocation
@testable import SmartGroceryReminder

enum Reliability {
    static let home = GeoPlace(id: "rel-home", name: "Home", latitude: 40.7, longitude: -74.0, kind: .home)
    static let store = GeoPlace(id: "rel-store", name: "Market", latitude: 40.71, longitude: -74.01, kind: .groceryStore)
    static let userId = "reliability-user"

    /// Home and one store saved; the daily reminder off so it doesn't add requests to check.
    static var preferences: UserPreferences {
        var prefs = UserPreferences.default
        prefs.homeLocation = home
        prefs.savedStores = [store]
        prefs.dailyListReminderEnabled = false
        return prefs
    }

    /// Something this user just checked off: a home arrival is a trip worth an unload reminder.
    static var justBought: [GroceryItem] {
        [GroceryItem(title: "Milk", isCompleted: true, completedBy: userId)]
    }
}

extension XCTestCase {
    /// A signed-in session whose preferences and list have loaded, on a fake location manager.
    @MainActor
    func reliabilitySession(
        manager: FakeLocationManager = FakeLocationManager(),
        items: [GroceryItem] = Reliability.justBought,
        stateDirectory: URL? = nil
    ) async throws -> AppState {
        let state = AppState.forTesting(stateDirectory: stateDirectory, locationManager: manager)
        let user = AppUser(id: Reliability.userId, email: "r@b.c", displayName: "R")
        try await state.listService.savePreferences(Reliability.preferences, userId: user.id)
        for item in items {
            try await state.listService.upsert(item: item, listId: user.id)
        }
        state.currentUser = user
        state.isAuthenticated = true
        state.startSync(for: user)
        try await waitUntil { state.sessionDataLoaded && state.shoppingList.count == items.count }
        return state
    }

    /// The Reminder health checklist as the Diagnostics screen would build it.
    @MainActor
    func health(of service: LocationService, expectedRegionCount: Int = 2) -> [String: HealthItem] {
        let items = ReminderHealth.check(
            authorization: service.authorizationStatus,
            accuracy: service.accuracyAuthorization,
            notifications: .authorized,
            backgroundRefresh: .available,
            lowPowerMode: false,
            hasHome: true,
            systemRegionCount: service.systemRegionCount,
            expectedRegionCount: expectedRegionCount
        )
        return Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    }

    /// A temporary directory removed after the test, for state that must survive a "relaunch".
    func temporaryDirectory() -> URL {
        temporaryFileURL("unused").deletingLastPathComponent()
    }
}
```

- [ ] **Step 8: Smoke test: a session arms geofences on the fake**

```swift
// SmartGroceryReminderTests/Reliability/RegionMonitoringReliabilityTests.swift
import XCTest
import CoreLocation
@testable import SmartGroceryReminder

/// Geofences are the only thing that wakes the app at a store or at home. These scenarios cover
/// what iOS does to them behind the app's back.
final class RegionMonitoringReliabilityTests: XCTestCase {
    @MainActor
    func testASessionArmsHomeAndStoreOnTheLocationManager() async throws {
        let manager = FakeLocationManager()
        let state = try await reliabilitySession(manager: manager)

        try await waitUntil { manager.monitoredRegions.count == 2 }
        XCTAssertEqual(
            Set(manager.monitoredRegions.map(\.identifier)),
            [RegionID.make(for: Reliability.home), RegionID.make(for: Reliability.store)]
        )
        XCTAssertEqual(state.locationService.systemRegionCount, 2)
        state.signOut()
    }
}
```

- [ ] **Step 9: Run in CI**

```bash
git add -A && git commit -m "Tests: put CoreLocation behind LocationManaging so reliability scenarios can script what iOS reports"
git push -u origin reminder-reliability-tests
gh run watch --exit-status $(gh run list --branch reminder-reliability-tests --limit 1 --json databaseId -q '.[0].databaseId')
```
Expected: the whole existing suite and `testASessionArmsHomeAndStoreOnTheLocationManager` pass. On failure, `gh run view --log-failed`.

---

### Task 2: Permission scenarios

**Files:**
- Create: `SmartGroceryReminderTests/Reliability/PermissionReliabilityTests.swift`

**Interfaces:**
- Consumes: `FakeLocationManager.changeAuthorization(to:accuracy:on:)`, `health(of:)`, `reliabilitySession`, `LocationService.requestCurrentLocation()`, `DiagnosticsLog.entries` (`.kind == .permission`)

These describe current behavior, so they are expected to pass. A failure is a real bug: fix it in this task, test first.

- [ ] **Step 1: Write the tests**

```swift
import XCTest
import CoreLocation
@testable import SmartGroceryReminder

/// People change location access in Settings at any time, often without opening the app.
final class PermissionReliabilityTests: XCTestCase {
    @MainActor
    private func service(_ manager: FakeLocationManager) -> (LocationService, DiagnosticsLog) {
        let log = DiagnosticsLog()
        return (LocationService(diagnostics: log, manager: manager), log)
    }

    @MainActor
    func testDowngradingFromAlwaysToWhileUsingTurnsHealthRedAndIsLogged() {
        let manager = FakeLocationManager()
        let (service, log) = service(manager)
        service.startMonitoring(home: Reliability.home, stores: [Reliability.store])
        XCTAssertTrue(health(of: service)["location"]!.isOK)

        manager.changeAuthorization(to: .authorizedWhenInUse, on: service)

        XCTAssertEqual(service.authorizationStatus, .authorizedWhenInUse)
        XCTAssertFalse(health(of: service)["location"]!.isOK)
        XCTAssertNotNil(health(of: service)["location"]!.fix)
        XCTAssertTrue(log.entries.contains { $0.kind == .permission && $0.message.contains("While") })
    }

    @MainActor
    func testTurningOffPreciseLocationTurnsHealthRedEvenWithAlways() {
        let manager = FakeLocationManager()
        let (service, _) = service(manager)

        manager.changeAuthorization(to: .authorizedAlways, accuracy: .reducedAccuracy, on: service)

        XCTAssertTrue(health(of: service)["location"]!.isOK)
        XCTAssertFalse(health(of: service)["precise"]!.isOK)
    }

    @MainActor
    func testWithAccessDeniedNoLocationFixIsRequested() {
        let manager = FakeLocationManager()
        manager.authorizationStatus = .denied
        let (service, _) = service(manager)

        service.requestCurrentLocation()

        XCTAssertEqual(manager.locationRequests, 0)
    }

    @MainActor
    func testTheSameAuthorizationReportedTwiceIsLoggedOnce() {
        // iOS calls locationManagerDidChangeAuthorization on every launch, changed or not.
        let manager = FakeLocationManager()
        let (service, log) = service(manager)

        manager.changeAuthorization(to: .authorizedWhenInUse, on: service)
        manager.changeAuthorization(to: .authorizedWhenInUse, on: service)

        XCTAssertEqual(log.entries.filter { $0.kind == .permission }.count, 1)
    }

    @MainActor
    func testRestoringAlwaysTurnsHealthGreenAgain() {
        let manager = FakeLocationManager()
        let (service, _) = service(manager)
        service.startMonitoring(home: Reliability.home, stores: [Reliability.store])
        manager.changeAuthorization(to: .authorizedWhenInUse, on: service)

        manager.changeAuthorization(to: .authorizedAlways, on: service)

        XCTAssertTrue(health(of: service).values.filter { !$0.isWarningOnly }.allSatisfy(\.isOK))
    }
}
```

Before pushing, confirm that `LocationService.describe(.authorizedWhenInUse)` contains "While". If it doesn't, assert on the string it does return.

Notification denial is already covered by `testARefusedUnloadReminderIsNotCountedAndStartsNoCooldown` and `testARefusedStoreReminderIsNotCountedAndStartsNoCooldown` in `LocationEventTests`. Don't repeat them.

- [ ] **Step 2: Commit.** Run it in CI together with Task 3 (see Task 3, Step 6).

```bash
git add SmartGroceryReminderTests/Reliability/PermissionReliabilityTests.swift
git commit -m "Reliability tests: location access downgraded, approximate, denied, reported twice, restored"
```

---

### Task 3: Region-monitoring scenarios and the stale-count bug fix

**Files:**
- Modify: `SmartGroceryReminderTests/Reliability/RegionMonitoringReliabilityTests.swift`
- Modify: `SmartGroceryReminder/Services/LocationService.swift` (`handleMonitoringFailure`)

**Interfaces:**
- Consumes: `FakeLocationManager.failingRegionIds`, `regionLimit`, `deliverMonitoringFailures(to:)`, `startCalls`, `stopCalls`; `LocationService.events`, `handleRegionState(_:identifier:)`, `regionStates`

- [ ] **Step 1: Write the failing tests**

Add the following to `RegionMonitoringReliabilityTests`:

```swift
    @MainActor
    func testARegionIOSRefusesToMonitorShowsInHealth() {
        let manager = FakeLocationManager()
        manager.failingRegionIds = [RegionID.make(for: Reliability.store)]
        let log = DiagnosticsLog()
        let service = LocationService(diagnostics: log, manager: manager)
        service.startMonitoring(home: Reliability.home, stores: [Reliability.store])
        XCTAssertEqual(service.systemRegionCount, 2) // iOS accepts it first...

        manager.deliverMonitoringFailures(to: service) // ...then reports the failure

        XCTAssertEqual(service.systemRegionCount, 1)
        XCTAssertFalse(health(of: service)["regions"]!.isOK)
        XCTAssertEqual(health(of: service)["regions"]!.title, "iOS is watching 1 of 2 places")
        XCTAssertTrue(log.entries.contains { $0.kind == .error })
    }

    @MainActor
    func testPlacesOverTheIOSLimitAreReportedNotSilentlyDropped() {
        let manager = FakeLocationManager()
        let service = LocationService(diagnostics: DiagnosticsLog(), manager: manager)
        let stores = (1...20).map {
            GeoPlace(id: "s\($0)", name: "Store \($0)", latitude: 40 + Double($0) / 100, longitude: -74, kind: .groceryStore)
        }
        service.startMonitoring(home: Reliability.home, stores: stores) // 21 places

        manager.deliverMonitoringFailures(to: service)

        XCTAssertEqual(service.systemRegionCount, 20)
        XCTAssertEqual(health(of: service, expectedRegionCount: 21)["regions"]!.title, "iOS is watching 20 of 21 places")
        XCTAssertFalse(health(of: service, expectedRegionCount: 21)["regions"]!.isOK)
    }
```

- [ ] **Step 2: Add the scenarios that should already pass**

```swift
    @MainActor
    func testReapplyingTheSamePlacesTouchesNoGeofence() {
        let manager = FakeLocationManager()
        let service = LocationService(diagnostics: DiagnosticsLog(), manager: manager)
        service.startMonitoring(home: Reliability.home, stores: [Reliability.store])
        let starts = manager.startCalls.count

        service.startMonitoring(home: Reliability.home, stores: [Reliability.store])

        XCTAssertEqual(manager.startCalls.count, starts)
        XCTAssertTrue(manager.stopCalls.isEmpty)
    }

    @MainActor
    func testAddingAStoreStartsOnlyThatStore() {
        let manager = FakeLocationManager()
        let service = LocationService(diagnostics: DiagnosticsLog(), manager: manager)
        service.startMonitoring(home: Reliability.home, stores: [Reliability.store])
        let second = GeoPlace(id: "rel-store-2", name: "Corner shop", latitude: 40.72, longitude: -74.02, kind: .groceryStore)

        service.startMonitoring(home: Reliability.home, stores: [Reliability.store, second])

        XCTAssertEqual(manager.startCalls.last, RegionID.make(for: second))
        XCTAssertEqual(manager.startCalls.count, 3)
        XCTAssertTrue(manager.stopCalls.isEmpty)
    }

    @MainActor
    func testRegionStateReportsNeverBecomeEventsAndRepeatsAreLoggedOnce() {
        let log = DiagnosticsLog()
        let service = LocationService(diagnostics: log, manager: FakeLocationManager())
        var events: [LocationEvent] = []
        let subscription = service.events.sink { events.append($0) }
        let id = RegionID.make(for: Reliability.home)

        service.handleRegionState(.inside, identifier: id)
        service.handleRegionState(.inside, identifier: id)

        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(service.regionStates[id], .inside)
        XCTAssertEqual(log.entries.filter { $0.kind == .regionState }.count, 1)
        subscription.cancel()
    }
```

- [ ] **Step 3: Confirm the first two tests fail (red)**

```bash
git add SmartGroceryReminderTests/Reliability/RegionMonitoringReliabilityTests.swift
git commit -m "Reliability tests: a geofence iOS refuses must show in Reminder health (failing)"
git push
```
Read the run. Expected: `testARegionIOSRefusesToMonitorShowsInHealth` and `testPlacesOverTheIOSLimitAreReportedNotSilentlyDropped` fail with `systemRegionCount` 2 or 21 when 1 or 20 was expected. Every other test passes.

- [ ] **Step 4: Fix it**

In `LocationService.swift`:

```swift
    /// iOS accepts a region, then reports here when it can't monitor it (e.g. over the 20-region
    /// limit) and drops it. Recount, so Reminder health stops claiming the place is watched.
    func handleMonitoringFailure(identifier: String, message: String) {
        systemRegionCount = currentRegions.count
        diagnostics.record(.error, "Couldn't monitor \(Self.describe(regionIdentifier: identifier)): \(message)")
    }
```

- [ ] **Step 5: Commit the fix**

```bash
git add SmartGroceryReminder/Services/LocationService.swift
git commit -m "Fix: recount monitored regions when iOS refuses one, so Reminder health turns red instead of staying green"
```

- [ ] **Step 6: Run in CI (green)**

`git push`, then watch the run. Expected: all tests pass, including Task 2's.

---

### Task 4: Duplicate and flapping events

**Files:**
- Create: `SmartGroceryReminderTests/Reliability/DuplicateEventReliabilityTests.swift`

**Interfaces:**
- Consumes: `reliabilitySession`, `FakeLocationManager.deliverEnter/deliverExit(_:at:to:)`, `AppState.forTesting(locationManager:)`, `AppState.startSync(for:)`, `DiagnosticsLog` kinds `.unloadScheduled`, `.skipped`, `.queued`

- [ ] **Step 1: Write the tests**

```swift
import XCTest
@testable import SmartGroceryReminder

/// iOS can report the same geofence crossing more than once: GPS jitter at the edge, and a replay
/// after it relaunches the app. Each real arrival must remind exactly once.
final class DuplicateEventReliabilityTests: XCTestCase {
    @MainActor
    private func unloadsScheduled(_ state: AppState) -> Int {
        state.diagnostics.entries.filter { $0.kind == .unloadScheduled }.count
    }

    @MainActor
    func testTheSameHomeEnterTwiceInAMomentRemindsOnce() async throws {
        let manager = FakeLocationManager()
        let state = try await reliabilitySession(manager: manager)

        manager.deliverEnter(Reliability.home, to: state.locationService)
        manager.deliverEnter(Reliability.home, to: state.locationService)

        try await waitUntil { state.diagnostics.entries.contains { $0.kind == .skipped } }
        XCTAssertEqual(unloadsScheduled(state), 1)
        state.signOut()
    }

    @MainActor
    func testFlappingAtTheHomeBoundaryRemindsOnce() async throws {
        let manager = FakeLocationManager()
        let state = try await reliabilitySession(manager: manager)

        manager.deliverEnter(Reliability.home, to: state.locationService)
        manager.deliverExit(Reliability.home, to: state.locationService)
        manager.deliverEnter(Reliability.home, to: state.locationService)
        manager.deliverExit(Reliability.home, to: state.locationService)
        manager.deliverEnter(Reliability.home, to: state.locationService)

        try await waitUntil { state.diagnostics.entries.filter { $0.kind == .skipped }.count == 2 }
        XCTAssertEqual(unloadsScheduled(state), 1)
        state.signOut()
    }

    @MainActor
    func testAnEnterReplayedWhileTheListLoadsRemindsOnce() async throws {
        // iOS relaunches the app for the enter and may deliver it again; the list isn't loaded yet.
        let manager = FakeLocationManager()
        let state = AppState.forTesting(locationManager: manager)
        let user = AppUser(id: Reliability.userId, email: "r@b.c", displayName: "R")
        try await state.listService.savePreferences(Reliability.preferences, userId: user.id)
        for item in Reliability.justBought {
            try await state.listService.upsert(item: item, listId: user.id)
        }
        state.currentUser = user
        state.isAuthenticated = true

        manager.deliverEnter(Reliability.home, to: state.locationService)
        manager.deliverEnter(Reliability.home, to: state.locationService)
        XCTAssertTrue(state.diagnostics.entries.contains { $0.kind == .queued })

        state.startSync(for: user)

        try await waitUntil { self.unloadsScheduled(state) >= 1 }
        // Give a second, late reminder the chance to appear before asserting it didn't.
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(unloadsScheduled(state), 1)
        state.signOut()
    }
}
```

If `testTheSameHomeEnterTwiceInAMomentRemindsOnce` times out waiting for `.skipped`, open `processPendingLocationEvents` in `AppState.swift` and check how a cooldown ignore is recorded. Then wait on the kind it actually logs. Don't loosen the `== 1` assertion.

- [ ] **Step 2: Commit and run in CI**

```bash
git add SmartGroceryReminderTests/Reliability/DuplicateEventReliabilityTests.swift
git commit -m "Reliability tests: a duplicate enter, boundary flapping and a relaunch replay each remind once"
git push
```
Expected: pass. If one fails on `== 1`, that's a real duplicate-reminder bug. Write down the cause (systematic-debugging), fix it in `AppState.processPendingLocationEvents` and commit the fix separately.

---

### Task 5: Relaunch (cold start) scenarios

**Files:**
- Create: `SmartGroceryReminderTests/Reliability/RelaunchReliabilityTests.swift`

**Interfaces:**
- Consumes: `reliabilitySession(manager:items:stateDirectory:)`, `temporaryDirectory()`, `AppState.homeArrivalTimer` (`isActive`, `endDate`), `AppState.lastUnloadScheduled`, files `arrival-timer.json` / `reminder-cooldowns.json` in `stateDirectory`

A "relaunch" here means: drop the first `AppState` without calling `signOut()`, because `signOut()` cancels the timer and clears cooldowns, which a kill doesn't do. Then build a new `AppState` on the same `stateDirectory`.

- [ ] **Step 1: Write the tests**

```swift
import XCTest
@testable import SmartGroceryReminder

/// iOS kills the app in the background whenever it likes, and relaunches it for a geofence.
/// What the user was in the middle of must survive that.
final class RelaunchReliabilityTests: XCTestCase {
    @MainActor
    func testARunningCountdownSurvivesTheAppBeingKilled() async throws {
        let directory = temporaryDirectory()
        let manager = FakeLocationManager()
        var first: AppState? = try await reliabilitySession(manager: manager, stateDirectory: directory)
        manager.deliverEnter(Reliability.home, to: first!.locationService)
        try await waitUntil { first!.homeArrivalTimer.isActive }
        let endDate = try XCTUnwrap(first!.homeArrivalTimer.endDate)
        first!.homeArrivalTimer.cancelTickingForTesting()
        first = nil // killed: no sign-out, nothing cleaned up

        let relaunched = AppState.forTesting(stateDirectory: directory, locationManager: FakeLocationManager())

        XCTAssertTrue(relaunched.homeArrivalTimer.isActive)
        XCTAssertEqual(relaunched.homeArrivalTimer.endDate, endDate)
        relaunched.homeArrivalTimer.cancel()
    }

    @MainActor
    func testACooldownSurvivesTheAppBeingKilled() async throws {
        let directory = temporaryDirectory()
        let firstManager = FakeLocationManager()
        let first = try await reliabilitySession(manager: firstManager, stateDirectory: directory)
        firstManager.deliverEnter(Reliability.home, to: first.locationService)
        try await waitUntil { first.diagnostics.entries.contains { $0.kind == .unloadScheduled } }
        first.homeArrivalTimer.cancel() // only the cooldown matters here

        let secondManager = FakeLocationManager()
        let relaunched = try await reliabilitySession(manager: secondManager, stateDirectory: directory)
        secondManager.deliverEnter(Reliability.home, to: relaunched.locationService)

        try await waitUntil { relaunched.diagnostics.entries.contains { $0.kind == .skipped } }
        XCTAssertFalse(relaunched.diagnostics.entries.contains { $0.kind == .unloadScheduled })
        relaunched.signOut()
    }

    @MainActor
    func testACountdownThatEndedWhileKilledDoesNotComeBack() throws {
        let directory = temporaryDirectory()
        let store = JSONFileStore<ArrivalTimerState>(url: directory.appendingPathComponent("arrival-timer.json"))
        try store.save(ArrivalTimerState(endDate: Date().addingTimeInterval(-60), duration: 600))

        let relaunched = AppState.forTesting(stateDirectory: directory, locationManager: FakeLocationManager())

        XCTAssertFalse(relaunched.homeArrivalTimer.isActive)
        XCTAssertNil(relaunched.homeArrivalTimer.endDate)
    }

    @MainActor
    func testCorruptStateFilesStartCleanInsteadOfCrashing() throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: directory.appendingPathComponent("arrival-timer.json"))
        try Data("{not json".utf8).write(to: directory.appendingPathComponent("reminder-cooldowns.json"))

        let relaunched = AppState.forTesting(stateDirectory: directory, locationManager: FakeLocationManager())

        XCTAssertFalse(relaunched.homeArrivalTimer.isActive)
        XCTAssertNil(relaunched.lastUnloadScheduled)
        XCTAssertNil(relaunched.lastUnloadDone)
        XCTAssertFalse(relaunched.unloadOutstanding)
    }
}
```

The first test needs the first instance's ticking `Timer` to stop without deleting the saved file, since `cancel()` would remove it. Before adding a test hook, check `HomeArrivalTimerService` for an existing method that stops ticking but keeps the store (`grep -n "func " SmartGroceryReminder/Services/HomeArrivalTimerService.swift`). If there isn't one, add the following inside `HomeArrivalTimerService`:

```swift
    /// Tests only: stops the ticking timer the way the app being killed does, leaving the saved
    /// countdown on disk for the next launch.
    func cancelTickingForTesting() {
        timer?.invalidate()
        timer = nil
    }
```

Relaunching by iOS for an enter before the session has restored is covered by `testAnEnterReplayedWhileTheListLoadsRemindsOnce` (Task 4) and the existing `testArrivalBeforeTheListLoadsIsHandledOnceItDoes`. Don't add a third version.

- [ ] **Step 2: Commit and run in CI**

```bash
git add SmartGroceryReminderTests/Reliability/RelaunchReliabilityTests.swift SmartGroceryReminder/Services/HomeArrivalTimerService.swift
git commit -m "Reliability tests: a countdown and a cooldown survive the app being killed; an ended countdown and corrupt state files start clean"
git push
```
Expected: pass. A failure means a real relaunch bug: debug it, fix it and commit the fix separately.

---

### Task 6: README section and PR

**Files:**
- Modify: `README.md` (add the section after the existing testing or CI section; find it with `grep -n "^## " README.md`)

- [ ] **Step 1: Add the section**

```markdown
## Reliability suite

Location reminders run when iOS decides, not when the app does, so the riskiest code is the code
that reacts to iOS. `SmartGroceryReminderTests/Reliability/` tests it scenario by scenario, with
a `FakeLocationManager` standing in for CoreLocation (behind the `LocationManaging` protocol):

| Risk | Scenarios |
|---|---|
| Permissions | Always downgraded to While Using, Precise Location off, access denied, the same change reported twice, access restored |
| Region monitoring | iOS refuses a geofence, more than 20 places, re-applying places touches nothing, region-state reports never become reminders |
| Duplicate events | the same enter twice, flapping at the home boundary, a replay while the list loads: one reminder each |
| Relaunch | the countdown and cooldowns survive the app being killed; an ended countdown and corrupt state files start clean |

The suite found one bug: when iOS refused to monitor a place, Reminder health kept showing it as watched.
```

- [ ] **Step 2: Commit, push, open the PR**

```bash
git add README.md
git commit -m "Docs: describe the reminder reliability suite"
git push
gh pr create --title "Reminder reliability suite" --body "CoreLocation behind LocationManaging with a FakeLocationManager; scenario tests for permissions, region monitoring, duplicate events and relaunch; fixes Reminder health staying green when iOS refuses a geofence. Plan: docs/superpowers/plans/2026-10-04-reminder-reliability-tests.md"
```

- [ ] **Step 3: Merge on green**

`gh pr checks --watch`. When every check has concluded successfully (check the conclusion, not just that the run finished), run `gh pr merge --merge --delete-branch`.
