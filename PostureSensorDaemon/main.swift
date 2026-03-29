import Foundation

/// PostureSensorDaemon - Privileged helper that reads sensor data via IOKit HID
/// and exposes it to the main app over XPC.

// MARK: - Sensor & XPC Setup

let sensorManager = SensorManager()
let xpcServer = XPCServer(sensorManager: sensorManager)

sensorManager.start()

print("PostureSensorDaemon started")
print("  Accelerometer: \(sensorManager.hasAccelerometer ? "found" : "NOT FOUND")")
print("  Lid angle: \(sensorManager.hasLidAngle ? "found" : "NOT FOUND")")

// MARK: - XPC Listener

final class DaemonDelegate: NSObject, NSXPCListenerDelegate {
    let server: XPCServer

    init(server: XPCServer) {
        self.server = server
        super.init()
    }

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        let interface = NSXPCInterface(with: PostureSensorProtocol.self)

        let snapshotClasses = NSSet(array: [
            SensorSnapshot.self,
            NSNumber.self,
            NSString.self,
        ])
        interface.setClasses(
            snapshotClasses as! Set<AnyHashable>,
            for: #selector(PostureSensorProtocol.getSensorSnapshot(withReply:)),
            argumentIndex: 0,
            ofReply: true
        )

        let availabilityClasses = NSSet(array: [
            SensorAvailability.self,
            NSNumber.self,
        ])
        interface.setClasses(
            availabilityClasses as! Set<AnyHashable>,
            for: #selector(PostureSensorProtocol.getSensorStatus(withReply:)),
            argumentIndex: 0,
            ofReply: true
        )

        newConnection.exportedInterface = interface
        newConnection.exportedObject = server
        newConnection.resume()
        print("[XPC] New client connected")
        return true
    }
}

let delegate = DaemonDelegate(server: xpcServer)
let listener = NSXPCListener(machServiceName: "com.posturedesk.sensor-daemon")
listener.delegate = delegate
listener.resume()

print("XPC listener active on com.posturedesk.sensor-daemon")

// Keep the run loop alive
RunLoop.current.run()
