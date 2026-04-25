import Foundation
import IOKit
import IOKit.hid

/// Raw 3-axis acceleration sample from the IMU
struct AccelSample {
    let x: Double  // g-force
    let y: Double  // g-force
    let z: Double  // g-force
    let timestamp: TimeInterval
}

/// Manages IOKit HID connections to the Apple Silicon accelerometer and lid angle sensor.
final class SensorManager: NSObject {

    // MARK: - State

    private var accelManager: IOHIDManager?
    private var accelDevice: IOHIDDevice?
    private var accelReportBuffer: UnsafeMutablePointer<UInt8>?

    private var lidAngleManager: IOHIDManager?
    private var lidAngleDevice: IOHIDDevice?
    private var lidAnglePollTimer: Timer?

    private let stateLock = NSLock()
    private var workerThread: Thread?
    private var workerReadySemaphore = DispatchSemaphore(value: 0)
    private var keepAlivePort: Port?
    private var isRunning = false

    private var _hasAccelerometer = false
    private var _hasGyroscope = false
    private var _hasLidAngle = false
    private var _currentLidAngle: Double = -1
    private var _onAccelSample: ((AccelSample) -> Void)?
    private var _onLidAngleUpdate: ((Double) -> Void)?

    // S5 — Hot-plug re-check throttle for lid-angle sensor.
    // Incremented on each accelerometer sample (~100Hz). Re-enumeration is triggered
    // every `lidAngleRecheckSampleInterval` samples (~60s @ 100Hz) when the lid-angle
    // sensor is currently unavailable. Plain Int — no allocations on the hot path.
    private var lidAngleRecheckCounter: Int = 0
    private let lidAngleRecheckSampleInterval = 6000  // ~60s at 100Hz

    var hasAccelerometer: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _hasAccelerometer
    }

    var hasGyroscope: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _hasGyroscope
    }

    var hasLidAngle: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _hasLidAngle
    }

    // Prevent deallocation while IOKit callbacks are active
    private var retainedSelf: SensorManager?

    /// Called on each new accelerometer sample (~100Hz)
    var onAccelSample: ((AccelSample) -> Void)? {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return _onAccelSample
        }
        set {
            stateLock.lock()
            _onAccelSample = newValue
            stateLock.unlock()
        }
    }

    /// Called when lid angle updates (~10Hz)
    var onLidAngleUpdate: ((Double) -> Void)? {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return _onLidAngleUpdate
        }
        set {
            stateLock.lock()
            _onLidAngleUpdate = newValue
            stateLock.unlock()
        }
    }

    /// Latest lid angle in degrees (-1 if unavailable)
    var currentLidAngle: Double {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _currentLidAngle
    }

    // MARK: - Lifecycle

    func start() {
        let thread: Thread? = stateLock.withCriticalScope {
            guard !isRunning else { return nil }
            isRunning = true
            retainedSelf = self  // prevent deallocation while callbacks are registered
            workerReadySemaphore = DispatchSemaphore(value: 0)

            let thread = Thread(target: self, selector: #selector(workerThreadMain), object: nil)
            thread.name = "com.gooseneck.sensor-manager"
            thread.qualityOfService = .userInitiated
            workerThread = thread
            return thread
        }

        guard let thread else { return }
        thread.start()
        workerReadySemaphore.wait()
        perform(#selector(startOnWorkerThread), on: thread, with: nil, waitUntilDone: false)
    }

    func stop() {
        let thread: Thread? = stateLock.withCriticalScope {
            guard isRunning else {
                retainedSelf = nil
                return nil
            }
            isRunning = false
            return workerThread
        }

        if let thread {
            perform(#selector(stopOnWorkerThread), on: thread, with: nil, waitUntilDone: true)
        } else {
            stopAccelerometer()
            stopLidAngleSensor()
        }

        stateLock.withCriticalScope {
            workerThread = nil
            keepAlivePort = nil
            retainedSelf = nil
        }
    }

    deinit {
        stop()
    }

    @objc private func workerThreadMain() {
        autoreleasepool {
            let runLoop = RunLoop.current
            let keepAlivePort = Port()
            stateLock.withCriticalScope {
                self.keepAlivePort = keepAlivePort
            }
            runLoop.add(keepAlivePort, forMode: .default)
            workerReadySemaphore.signal()

            while !Thread.current.isCancelled {
                runLoop.run(mode: .default, before: .distantFuture)
            }
        }
    }

    @objc private func startOnWorkerThread() {
        wakeSPUDrivers()
        startAccelerometer()
        startLidAngleSensor()
    }

    /// macOS Tahoe (26+) defaults SPU sensors to powered-down state.
    /// Set reporting and power properties on all AppleSPUHIDDriver services
    /// so the hardware actually starts delivering reports.
    private func wakeSPUDrivers() {
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("AppleSPUHIDDriver"),
            &iterator
        )
        guard result == kIOReturnSuccess else { return }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            IORegistryEntrySetCFProperty(service, "SensorPropertyReportingState" as CFString, 1 as CFNumber)
            IORegistryEntrySetCFProperty(service, "SensorPropertyPowerState" as CFString, 1 as CFNumber)
            IORegistryEntrySetCFProperty(service, "ReportInterval" as CFString, HIDConstants.reportIntervalUS as CFNumber)
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        IOObjectRelease(iterator)
    }

    @objc private func stopOnWorkerThread() {
        stopAccelerometer()
        stopLidAngleSensor()
        Thread.current.cancel()
        CFRunLoopStop(CFRunLoopGetCurrent())
    }

    // MARK: - Accelerometer

    private func startAccelerometer() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.accelManager = manager

        let matchingDict: [String: Any] = [
            kIOHIDVendorIDKey as String: HIDConstants.appleVendorID,
            kIOHIDDeviceUsagePageKey as String: HIDConstants.accelUsagePage,
            kIOHIDDeviceUsageKey as String: HIDConstants.accelUsageID,
        ]
        IOHIDManagerSetDeviceMatching(manager, matchingDict as CFDictionary)

        let context = Unmanaged.passUnretained(self).toOpaque()

        IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, _, _, device in
            guard let ctx else { return }
            let mgr = Unmanaged<SensorManager>.fromOpaque(ctx).takeUnretainedValue()
            mgr.accelDeviceMatched(device)
        }, context)

        IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, _, _, device in
            guard let ctx else { return }
            let mgr = Unmanaged<SensorManager>.fromOpaque(ctx).takeUnretainedValue()
            mgr.accelDeviceRemoved(device)
        }, context)

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if result != kIOReturnSuccess {
            print("[SensorManager] Failed to open accelerometer manager: \(result)")
        }
    }

    private func accelDeviceMatched(_ device: IOHIDDevice) {
        print("[SensorManager] Accelerometer device matched")
        self.accelDevice = device

        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        if result != kIOReturnSuccess {
            print("[SensorManager] Failed to open accelerometer device: \(result)")
            self.accelDevice = nil
            return
        }

        stateLock.withCriticalScope {
            _hasAccelerometer = true
        }

        // Allocate persistent report buffer (must outlive the callback)
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: HIDConstants.reportSize)
        buffer.initialize(repeating: 0, count: HIDConstants.reportSize)
        self.accelReportBuffer = buffer

        let context = Unmanaged.passUnretained(self).toOpaque()

        IOHIDDeviceRegisterInputReportCallback(
            device,
            buffer,
            HIDConstants.reportSize,
            { ctx, _, _, _, _, report, reportLength in
                guard let ctx else { return }
                let mgr = Unmanaged<SensorManager>.fromOpaque(ctx).takeUnretainedValue()
                mgr.parseAccelReport(report: report, length: Int(reportLength))
            },
            context
        )
    }

    private func accelDeviceRemoved(_ device: IOHIDDevice) {
        print("[SensorManager] Accelerometer device removed")
        self.accelDevice = nil
        stateLock.withCriticalScope {
            _hasAccelerometer = false
        }
        // Buffer is freed in stopAccelerometer() to avoid race with in-flight report callbacks.
    }

    private func stopAccelerometer() {
        // Deregister callback BEFORE closing the device or freeing the buffer
        // to prevent IOKit from invoking a stale function pointer.
        if let device = accelDevice, let buffer = accelReportBuffer {
            IOHIDDeviceRegisterInputReportCallback(device, buffer, HIDConstants.reportSize, nil, nil)
        }
        if let device = accelDevice {
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
            accelDevice = nil
        }
        if let manager = accelManager {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            accelManager = nil
        }
        if let buffer = accelReportBuffer {
            buffer.deallocate()
            accelReportBuffer = nil
        }
        stateLock.withCriticalScope {
            _hasAccelerometer = false
        }
    }

    // MARK: - Accelerometer Report Parsing

    private func parseAccelReport(report: UnsafePointer<UInt8>, length: Int) {
        guard length >= 18 else { return }

        let x = readInt32LE(from: report, at: HIDConstants.xOffset)
        let y = readInt32LE(from: report, at: HIDConstants.yOffset)
        let z = readInt32LE(from: report, at: HIDConstants.zOffset)

        let sx = Double(x) / HIDConstants.scaleFactor
        let sy = Double(y) / HIDConstants.scaleFactor
        let sz = Double(z) / HIDConstants.scaleFactor

        // S3 — Sanity check: drop NaN or saturated/garbage packets.
        // A sane MacBook accelerometer never reports >2g sustained; >4g indicates
        // sensor saturation or a corrupted packet that would poison downstream filters.
        guard sx.isFinite, sy.isFinite, sz.isFinite else { return }
        let magnitudeSq = sx * sx + sy * sy + sz * sz
        guard magnitudeSq.isFinite, magnitudeSq <= 16.0 else { return }  // 4g squared

        let sample = AccelSample(
            x: sx, y: sy, z: sz,
            timestamp: Date.timeIntervalSinceReferenceDate
        )

        // S1 — Capture callback and running state under stateLock into locals
        // before invoking. Prevents a concurrent stop() from nulling the closure
        // between the read and the call (use-after-null risk on the C-callback path).
        // S5 — Bump hot-plug re-check counter and decide whether to schedule re-enumeration.
        var callback: ((AccelSample) -> Void)?
        var shouldRecheckLidAngle = false
        stateLock.lock()
        let running = isRunning
        if running {
            callback = _onAccelSample
            if !_hasLidAngle {
                lidAngleRecheckCounter &+= 1
                if lidAngleRecheckCounter >= lidAngleRecheckSampleInterval {
                    lidAngleRecheckCounter = 0
                    shouldRecheckLidAngle = true
                }
            } else {
                lidAngleRecheckCounter = 0
            }
        }
        stateLock.unlock()

        guard running else { return }
        callback?(sample)

        if shouldRecheckLidAngle {
            scheduleLidAngleRecheck()
        }
    }

    private func readInt32LE(from ptr: UnsafePointer<UInt8>, at offset: Int) -> Int32 {
        let b0 = UInt32(ptr[offset])
        let b1 = UInt32(ptr[offset + 1]) << 8
        let b2 = UInt32(ptr[offset + 2]) << 16
        let b3 = UInt32(ptr[offset + 3]) << 24
        return Int32(bitPattern: b0 | b1 | b2 | b3)
    }

    // MARK: - Lid Angle Sensor

    private func startLidAngleSensor() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.lidAngleManager = manager

        let matchingDict: [String: Any] = [
            kIOHIDVendorIDKey as String: HIDConstants.appleVendorID,
            kIOHIDDeviceUsagePageKey as String: HIDConstants.lidAngleUsagePage,
            kIOHIDDeviceUsageKey as String: HIDConstants.lidAngleUsageID,
        ]
        IOHIDManagerSetDeviceMatching(manager, matchingDict as CFDictionary)

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if result != kIOReturnSuccess {
            print("[SensorManager] Failed to open lid angle manager: \(result)")
            return
        }

        // Find the device directly (lid angle uses polling, not streaming callbacks)
        if let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
           let device = deviceSet.first {
            self.lidAngleDevice = device
            stateLock.withCriticalScope {
                _hasLidAngle = true
            }

            let openResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
            if openResult != kIOReturnSuccess {
                print("[SensorManager] Failed to open lid angle device: \(openResult)")
                stateLock.withCriticalScope {
                    _hasLidAngle = false
                }
                return
            }

            print("[SensorManager] Lid angle sensor found")

            // Poll at 10Hz
            lidAnglePollTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                self?.pollLidAngle()
            }
        } else {
            // S5 — Mark unavailable so the accel-sample-driven re-check can detect a
            // future hot-plug (e.g. peripheral attach, late driver enumeration).
            stateLock.withCriticalScope {
                _hasLidAngle = false
            }
            // Tear down the manager we just created — startLidAngleSensor() recreates
            // a fresh one on every retry.
            if let manager = lidAngleManager {
                IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
                IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
                lidAngleManager = nil
            }
            print("[SensorManager] Lid angle sensor not found on this device (will re-check periodically)")
        }
    }

    /// S5 — Schedule a hot-plug lid-angle re-enumeration on the worker thread.
    /// Called from the accelerometer hot path (must be cheap) — defers actual work
    /// to the worker runloop so enumeration is serialized with other IOKit calls.
    private func scheduleLidAngleRecheck() {
        let (thread, running): (Thread?, Bool) = stateLock.withCriticalScope { (workerThread, isRunning) }
        guard let thread, running else { return }
        perform(#selector(lidAngleRecheckOnWorkerThread), on: thread, with: nil, waitUntilDone: false)
    }

    @objc private func lidAngleRecheckOnWorkerThread() {
        // Re-check under lock — another path may have already attached the sensor,
        // or stop() may have been called since the recheck was scheduled.
        let (alreadyHave, running): (Bool, Bool) = stateLock.withCriticalScope { (_hasLidAngle, isRunning) }
        guard !alreadyHave, running else { return }
        #if DEBUG
        print("[SensorManager] Lid angle re-enumeration attempt (hot-plug check)")
        #endif
        startLidAngleSensor()
    }

    private func pollLidAngle() {
        guard let device = lidAngleDevice else { return }

        var reportBuffer = [UInt8](repeating: 0, count: HIDConstants.lidAngleReportBufferSize)
        var reportLength = CFIndex(reportBuffer.count)

        let result = IOHIDDeviceGetReport(
            device,
            kIOHIDReportTypeFeature,
            HIDConstants.lidAngleReportID,
            &reportBuffer,
            &reportLength
        )

        guard result == kIOReturnSuccess, reportLength >= 2 else { return }

        // Lid angle: 16-bit LE in centidegrees
        let low = UInt16(reportBuffer[0])
        let high = UInt16(reportBuffer[1]) << 8
        let centidegrees = Int16(bitPattern: low | high)
        let degrees = Double(centidegrees) / 100.0

        // S1 — Capture closure under stateLock into a local before invoking.
        // Prevents a concurrent stop() / setter from nulling the closure between
        // read and call.
        var callback: ((Double) -> Void)?
        stateLock.lock()
        _currentLidAngle = degrees
        let running = isRunning
        if running {
            callback = _onLidAngleUpdate
        }
        stateLock.unlock()

        guard running else { return }
        callback?(degrees)
    }

    private func stopLidAngleSensor() {
        lidAnglePollTimer?.invalidate()
        lidAnglePollTimer = nil

        if let device = lidAngleDevice {
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
            lidAngleDevice = nil
        }
        if let manager = lidAngleManager {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            lidAngleManager = nil
        }
        stateLock.withCriticalScope {
            _hasLidAngle = false
            _currentLidAngle = -1
        }
    }
}

private extension NSLock {
    func withCriticalScope<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
