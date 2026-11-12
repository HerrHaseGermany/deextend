import Foundation
import IOKit
import OSLog

/// On Apple Silicon the display connection service exists independently of its
/// CoreGraphics online flag. A physically replugged, software-disabled display
/// may remain offline and therefore never trigger the re-enable polling path.
final class PhysicalDisplayMonitor {
    var onConnection: (() -> Void)?
    private var port: IONotificationPortRef?
    private var iterator: io_iterator_t = 0
    private let logger = Logger(subsystem: "de.christianraudzis.deextend", category: "physical-display")

    init() {
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        self.port = port
        IONotificationPortSetDispatchQueue(port, .main)
        let match = IOServiceMatching("DCPAVServiceProxy") as NSMutableDictionary
        match[kIOPropertyMatchKey] = ["Location": "External"]
        let result = IOServiceAddMatchingNotification(port, kIOFirstMatchNotification,
                                                     match, Self.connected,
                                                     Unmanaged.passUnretained(self).toOpaque(), &iterator)
        guard result == KERN_SUCCESS else {
            logger.error("Could not register physical display notifications: \(result)")
            return
        }
        // Draining arms the notification. Existing connections at app launch are not insertions.
        drain(iterator, announce: false)
    }

    private static let connected: IOServiceMatchingCallback = { context, iterator in
        guard let context else { return }
        Unmanaged<PhysicalDisplayMonitor>.fromOpaque(context).takeUnretainedValue()
            .drain(iterator, announce: true)
    }

    private func drain(_ iterator: io_iterator_t, announce: Bool) {
        var found = false
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            IOObjectRelease(service)
            found = true
        }
        if found && announce {
            logger.info("External physical display connection detected")
            onConnection?()
        }
    }

    deinit {
        if iterator != 0 { IOObjectRelease(iterator) }
        if let port { IONotificationPortDestroy(port) }
    }
}
