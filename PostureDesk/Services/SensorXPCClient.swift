import Foundation

/// Connects to the PostureSensorDaemon over XPC and provides sensor data to the app.
@Observable
final class SensorXPCClient {

    private(set) var isConnected = false
    private(set) var latestSnapshot: SensorSnapshot?
    private(set) var sensorAvailability: SensorAvailability?

    private var connection: NSXPCConnection?
    private var pollTimer: Timer?

    // MARK: - Lifecycle

    func connect() {
        let conn = NSXPCConnection(machServiceName: "com.posturedesk.sensor-daemon", options: .privileged)

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

        conn.remoteObjectInterface = interface

        conn.interruptionHandler = { [weak self] in
            #if DEBUG
            print("[XPC Client] Connection interrupted")
            #endif
            self?.isConnected = false
            self?.scheduleReconnect()
        }

        conn.invalidationHandler = { [weak self] in
            #if DEBUG
            print("[XPC Client] Connection invalidated")
            #endif
            self?.isConnected = false
            self?.connection = nil
            self?.scheduleReconnect()
        }

        conn.resume()
        self.connection = conn

        // Check if we can actually reach the daemon
        fetchSensorStatus()
        startPolling()
    }

    func disconnect() {
        pollTimer?.invalidate()
        pollTimer = nil
        connection?.invalidate()
        connection = nil
        isConnected = false
    }

    // MARK: - Data Fetching

    func fetchSnapshot() {
        guard let proxy = connection?.remoteObjectProxyWithErrorHandler({ error in
            #if DEBUG
            print("[XPC Client] Remote object error: \(error)")
            #endif
        }) as? PostureSensorProtocol else { return }

        proxy.getSensorSnapshot { [weak self] snapshot in
            DispatchQueue.main.async {
                self?.latestSnapshot = snapshot
                self?.isConnected = true
            }
        }
    }

    func fetchSensorStatus() {
        guard let proxy = connection?.remoteObjectProxyWithErrorHandler({ error in
            #if DEBUG
            print("[XPC Client] Remote object error: \(error)")
            #endif
        }) as? PostureSensorProtocol else { return }

        proxy.getSensorStatus { [weak self] availability in
            DispatchQueue.main.async {
                self?.sensorAvailability = availability
                self?.isConnected = true
                #if DEBUG
                print("[XPC Client] Connected - Accel: \(availability.hasAccelerometer), Lid: \(availability.hasLidAngle)")
                #endif
            }
        }
    }

    func calibrate(completion: @escaping (Bool) -> Void) {
        guard let proxy = connection?.remoteObjectProxyWithErrorHandler({ error in
            #if DEBUG
            print("[XPC Client] Remote object error: \(error)")
            #endif
            completion(false)
        }) as? PostureSensorProtocol else {
            completion(false)
            return
        }

        proxy.calibrateBaseline { success in
            DispatchQueue.main.async {
                completion(success)
            }
        }
    }

    // MARK: - Polling

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.fetchSnapshot()
        }
    }

    private func scheduleReconnect() {
        // Try reconnecting after 5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, !self.isConnected else { return }
            #if DEBUG
            print("[XPC Client] Attempting reconnect...")
            #endif
            self.connect()
        }
    }
}
