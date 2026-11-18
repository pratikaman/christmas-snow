import Foundation
import IOKit
import IOKit.hid

/// A nonexclusive subscription to the built-in Apple SPU accelerometer.
final class MacMotion {
    private var device: IOHIDDevice?
    private let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 256)
    private var baseline: SIMD3<Double>?
    private var filtered = SIMD3<Double>.zero
    private var sampleTime = 0.0
    private(set) var impulse = 0.0
    private(set) var samples = 0
    private(set) var detail = "Accelerometer unavailable"
    var active: Bool { samples > 0 && ProcessInfo.processInfo.systemUptime - sampleTime < 1 }
    var tilt: Double { active ? min(1, max(-1, (filtered.x - (baseline?.x ?? 0)) * 1.8)) : 0 }
    func calibrate() { if active { baseline = filtered } }

    private func accelerometer(_ serviceClass: String) -> io_service_t {
        let match = IOServiceMatching(serviceClass) as NSMutableDictionary
        match["IOPropertyMatch"] = ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 3]
        return IOServiceGetMatchingService(kIOMainPortDefault, match)
    }

    func start() {
        guard device == nil else { return }
        let service = accelerometer("AppleSPUHIDDevice")
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        guard let hid = IOHIDDeviceCreate(kCFAllocatorDefault, service) else { return }
        let result = IOHIDDeviceOpen(hid, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            detail = String(format: "Accelerometer access unavailable (0x%08x)", result)
            return
        }
        device = hid
        detail = "Waiting for accelerometer samples"
        IOHIDDeviceRegisterInputReportCallback(hid, buffer, 256, { context, result, _, _, _, bytes, length in
            guard result == kIOReturnSuccess, length == 22, let context else { return }
            let reader = Unmanaged<MacMotion>.fromOpaque(context).takeUnretainedValue()
            func axis(_ offset: Int) -> Double {
                let raw = UnsafeRawPointer(bytes + offset).loadUnaligned(as: Int32.self)
                return Double(Int32(littleEndian: raw)) / 65536
            }
            reader.accept(SIMD3(axis(6), axis(10), axis(14)))
        }, Unmanaged.passUnretained(self).toOpaque())
        IOHIDDeviceScheduleWithRunLoop(hid, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        let driver = accelerometer("AppleSPUHIDDriver")
        if driver != 0 {
            for (key, value) in [("SensorPropertyPowerState", 1), ("SensorPropertyReportingState", 1), ("ReportInterval", 20000)] {
                IORegistryEntrySetCFProperty(driver, key as CFString, value as CFNumber)
            }
            IOObjectRelease(driver)
        }
    }

    private func accept(_ value: SIMD3<Double>) {
        let now = ProcessInfo.processInfo.systemUptime
        if baseline == nil || now - sampleTime > 1 {
            filtered = value
            baseline = value
        }
        let delta = value - filtered
        filtered += 0.12 * delta
        impulse = max(impulse, min(2, sqrt(delta.x * delta.x + delta.y * delta.y + delta.z * delta.z)))
        samples += 1
        sampleTime = now
        detail = "Mac motion active"
    }

    func takeImpulse() -> Double {
        defer { impulse = 0 }
        return active ? impulse : 0
    }

    func stop() {
        guard let hid = device else { return }
        IOHIDDeviceUnscheduleFromRunLoop(hid, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDDeviceClose(hid, 0)
        device = nil
        baseline = nil
        samples = 0
        impulse = 0
    }
    deinit { stop(); buffer.deallocate() }
}
