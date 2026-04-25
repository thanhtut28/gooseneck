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
        guard stateLock.withCriticalScope({ isRunning }), length >= 18 else { return }

        let x = readInt32LE(from: report, at: HIDConstants.xOffset)
        let y = readInt32LE(from: report, at: HIDConstants.yOffset)
        let z = readInt32LE(from: report, at: HIDConstants.zOffset)

        let sample = AccelSample(
            x: Double(x) / HIDConstants.scaleFactor,
            y: Double(y) / HIDConstants.scaleFactor,
            z: Double(z) / HIDConstants.scaleFactor,
            timestamp: Date.timeIntervalSinceReferenceDate
        )

        let callback = onAccelSample
        callback?(sample)
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
            print("[SensorManager] Lid angle sensor not found on this device")
        }
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

        stateLock.withCriticalScope {
            _currentLidAngle = degrees
        }
        let callback = onLidAngleUpdate
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
