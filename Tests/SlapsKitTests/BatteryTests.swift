import Foundation
import Testing
@testable import SlapsKit

struct BatteryTests {
    private func on(_ p: Int) -> BatteryReading { BatteryReading(percent: p, onPower: true) }
    private func off(_ p: Int) -> BatteryReading { BatteryReading(percent: p, onPower: false) }

    @Test func warnsOnceWhenItRunsDownToTheLevel() {
        var watch = BatteryWatch(level: 20)
        #expect(watch.update(off(40)) == .none)
        #expect(watch.update(off(21)) == .none)
        #expect(watch.update(off(20)) == .warn)
        #expect(watch.update(off(19)) == .none)
        #expect(watch.update(off(5)) == .none)
    }

    @Test func warnsAtLaunchWhenAlreadyLow() {
        var watch = BatteryWatch(level: 20)
        #expect(watch.update(off(12)) == .warn)
    }

    @Test func pluggingInClearsAndRearms() {
        var watch = BatteryWatch(level: 20)
        #expect(watch.update(off(18)) == .warn)
        #expect(watch.update(on(18)) == .clear)
        #expect(watch.update(off(18)) == .warn)
    }

    @Test func neverWarnsOnPower() {
        var watch = BatteryWatch(level: 20)
        #expect(watch.update(on(3)) == .clear)
        #expect(watch.armed)
    }

    @Test func changingTheLevelRearms() {
        var watch = BatteryWatch(level: 20)
        #expect(watch.update(off(18)) == .warn)
        watch.level = 30
        #expect(watch.update(off(18)) == .warn)
        watch.level = 30
        #expect(watch.update(off(17)) == .none)
    }

    @Test func noReadingChangesNothing() {
        var watch = BatteryWatch(level: 20)
        #expect(watch.update(nil) == .none)
        #expect(watch.armed)
    }

    @Test func theAlertIsACustomAlertDueNow() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let m = BatteryWatch.alert(for: off(15), at: now)
        #expect(m.title == "Battery at 15%")
        #expect(m.kind == .custom && m.start == now)
        #expect(BatteryWatch.isAlert(m))
        #expect(AlertSchedule().due([m], at: now, state: AlertState()).map(\.id) == [m.id])
    }
}
