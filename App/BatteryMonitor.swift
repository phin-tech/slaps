import Foundation
import IOKit.ps
import SlapsKit

/// Reads the internal battery, and calls back whenever macOS says a power source changed (charge, plugged in or not).
/// No permissions needed.
@MainActor
enum BatteryMonitor {
    private static var source: CFRunLoopSource?
    private static var changed: (@MainActor () -> Void)?

    /// The internal battery, or nil on a Mac without one.
    static func read() -> BatteryReading? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = d[kIOPSCurrentCapacityKey] as? Int,
                  let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            let onPower = d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            return BatteryReading(percent: Int((Double(current) / Double(max) * 100).rounded()), onPower: onPower)
        }
        return nil
    }

    static var hasBattery: Bool { read() != nil }

    /// Calls `onChange` on the main thread from now on. Once is enough.
    static func observe(_ onChange: @escaping @MainActor () -> Void) {
        guard source == nil else { return }
        changed = onChange
        // A C callback, so it can't capture anything: it reaches `changed` through the type.
        guard let s = IOPSNotificationCreateRunLoopSource({ _ in
            MainActor.assumeIsolated { BatteryMonitor.changed?() }
        }, nil)?.takeRetainedValue() else { return }
        source = s
        CFRunLoopAddSource(CFRunLoopGetMain(), s, .defaultMode)
    }
}
