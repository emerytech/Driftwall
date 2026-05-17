import Foundation
import IOKit.ps

/// Reports AC vs. battery power and fires `onChange` when it flips.
final class PowerMonitor {
    private var runLoopSource: CFRunLoopSource?
    var onChange: ((_ onBattery: Bool) -> Void)?

    var isOnBattery: Bool {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(blob)?.takeUnretainedValue()
        else { return false }
        return (type as String) == kIOPSBatteryPowerValue
    }

    func start() {
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        // Non-capturing C callback; `self` travels through the context pointer.
        guard let src = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<PowerMonitor>.fromOpaque(context).takeUnretainedValue()
            monitor.onChange?(monitor.isOnBattery)
        }, ctx)?.takeRetainedValue() else { return }
        runLoopSource = src
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
    }

    func stop() {
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .defaultMode)
        }
        runLoopSource = nil
    }
}
