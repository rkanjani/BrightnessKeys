import AppKit
import CoreGraphics
import IOKit

// MARK: - Private framework symbols (loaded at runtime)

private func symbol<T>(_ path: String, _ name: String, as type: T.Type) -> T? {
    guard let handle = dlopen(path, RTLD_NOW), let sym = dlsym(handle, name) else { return nil }
    return unsafeBitCast(sym, to: type)
}

private let ioKitPath = "/System/Library/Frameworks/IOKit.framework/IOKit"
private let displayServicesPath = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
private let coreDisplayPath = "/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay"

private typealias AVCreateFn = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
private typealias AVI2CFn = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn
private typealias DSGetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
private typealias DSSetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
private typealias DSCanFn = @convention(c) (CGDirectDisplayID) -> Bool
private typealias CDInfoFn = @convention(c) (CGDirectDisplayID) -> Unmanaged<CFDictionary>?

private let avCreate = symbol(ioKitPath, "IOAVServiceCreateWithService", as: AVCreateFn.self)
private let avRead = symbol(ioKitPath, "IOAVServiceReadI2C", as: AVI2CFn.self)
private let avWrite = symbol(ioKitPath, "IOAVServiceWriteI2C", as: AVI2CFn.self)
private let dsGet = symbol(displayServicesPath, "DisplayServicesGetBrightness", as: DSGetFn.self)
private let dsSet = symbol(displayServicesPath, "DisplayServicesSetBrightness", as: DSSetFn.self)
private let dsCan = symbol(displayServicesPath, "DisplayServicesCanChangeBrightness", as: DSCanFn.self)
private let cdInfo = symbol(coreDisplayPath, "CoreDisplay_DisplayCreateInfoDictionary", as: CDInfoFn.self)

// MARK: - Display model

/// A display whose brightness we can read and write. Brightness is normalized to 0...1.
class Display {
    let id: CGDirectDisplayID
    let name: String
    let isBuiltIn: Bool

    /// Last known brightness; nil until read.
    fileprivate(set) var cached: Double?
    fileprivate var lastRead = Date.distantPast

    init(id: CGDirectDisplayID, name: String) {
        self.id = id
        self.name = name
        self.isBuiltIn = CGDisplayIsBuiltin(id) != 0
    }

    /// Reads brightness (possibly slowly) and calls back on the main thread.
    func read(_ completion: @escaping (Double?) -> Void) { completion(nil) }
    /// Sets brightness. Call from the main thread; hardware writes happen asynchronously.
    func set(_ value: Double) {}
    var kind: String { "" }
}

/// Built-in panels and Apple displays, controlled through DisplayServices.
final class AppleDisplay: Display {
    static func canControl(_ id: CGDirectDisplayID) -> Bool {
        guard let dsCan, dsGet != nil, dsSet != nil else { return false }
        return dsCan(id)
    }

    override func read(_ completion: @escaping (Double?) -> Void) {
        var value: Float = 0
        if let dsGet, dsGet(id, &value) == 0 {
            cached = Double(value)
            lastRead = Date()
        }
        completion(cached)
    }

    override func set(_ value: Double) {
        cached = value
        _ = dsSet?(id, Float(value))
    }

    override var kind: String { "Apple" }
}

/// Third-party monitors, controlled over DDC/CI (VCP 0x10 = luminance).
final class DDCDisplay: Display {
    private let service: CFTypeRef
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var pending: Int?
    private var writing = false
    private var maxValue = 100

    init(id: CGDirectDisplayID, name: String, service: CFTypeRef) {
        self.service = service
        self.queue = DispatchQueue(label: "ddc.\(id)", qos: .userInitiated)
        super.init(id: id, name: name)
    }

    override var kind: String { "DDC" }

    override func read(_ completion: @escaping (Double?) -> Void) {
        queue.async { [self] in
            let result = readVCP(0x10)
            DispatchQueue.main.async { [self] in
                if let (cur, max) = result {
                    maxValue = max
                    cached = Double(cur) / Double(max)
                    lastRead = Date()
                }
                completion(cached)
            }
        }
    }

    override func set(_ value: Double) {
        cached = value
        lastRead = Date()
        lock.lock()
        pending = Int((value * Double(maxValue)).rounded())
        let start = !writing
        writing = true
        lock.unlock()
        if start { queue.async { self.drain() } }
    }

    /// Writes only the latest requested value, so holding a key never queues up a backlog.
    private func drain() {
        while true {
            lock.lock()
            guard let value = pending else { writing = false; lock.unlock(); return }
            pending = nil
            lock.unlock()
            writeVCP(0x10, value)
        }
    }

    // DDC/CI framing: dest 0x6E, source 0x51, checksum is XOR of everything.
    private func writeVCP(_ vcp: UInt8, _ value: Int) {
        guard let avWrite else { return }
        var packet: [UInt8] = [0x84, 0x03, vcp, UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF), 0]
        packet[5] = packet[0..<5].reduce(0x6E ^ 0x51, ^)
        for _ in 0..<2 {
            _ = packet.withUnsafeMutableBytes { avWrite(service, 0x37, 0x51, $0.baseAddress!, UInt32($0.count)) }
            usleep(10_000)
        }
    }

    private func readVCP(_ vcp: UInt8) -> (Int, Int)? {
        guard let avWrite, let avRead else { return nil }
        var request: [UInt8] = [0x82, 0x01, vcp, 0]
        request[3] = request[0..<3].reduce(0x6E ^ 0x51, ^)
        for _ in 0..<5 {
            _ = request.withUnsafeMutableBytes { avWrite(service, 0x37, 0x51, $0.baseAddress!, UInt32($0.count)) }
            usleep(40_000)
            var reply = [UInt8](repeating: 0, count: 12)
            let status = reply.withUnsafeMutableBytes { avRead(service, 0x37, 0x51, $0.baseAddress!, UInt32($0.count)) }
            // Reply: 6E 88 02 <result> <vcp> <type> <maxH> <maxL> <curH> <curL> <chk>
            let checksum = reply[0..<10].reduce(0x50, ^)
            if status == kIOReturnSuccess, reply[2] == 0x02, reply[3] == 0, reply[4] == vcp, reply[10] == checksum {
                let max = Int(reply[6]) << 8 | Int(reply[7])
                let cur = Int(reply[8]) << 8 | Int(reply[9])
                if max > 0 { return (min(cur, max), max) }
            }
            usleep(20_000)
        }
        return nil
    }
}

// MARK: - Discovery

enum DisplayDiscovery {
    /// External AV services from the IORegistry, keyed by their framebuffer's registry path.
    private static func externalAVServices() -> [(location: String, service: CFTypeRef)] {
        guard let avCreate else { return [] }
        var result: [(String, CFTypeRef)] = []
        var iterator = io_iterator_t()
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard IORegistryEntryCreateIterator(root, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var framebufferPath: String?
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            var nameBuf = [CChar](repeating: 0, count: 128)
            IORegistryEntryGetName(entry, &nameBuf)
            let name = String(cString: nameBuf)
            if name == "AppleCLCD2" || name == "IOMobileFramebufferShim" {
                var pathBuf = [CChar](repeating: 0, count: 1024)
                IORegistryEntryGetPath(entry, kIOServicePlane, &pathBuf)
                framebufferPath = String(cString: pathBuf)
            } else if name == "DCPAVServiceProxy" {
                let location = IORegistryEntryCreateCFProperty(entry, "Location" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? String
                if location == "External", let path = framebufferPath, let service = avCreate(kCFAllocatorDefault, entry) {
                    result.append((path, service.takeRetainedValue()))
                }
            }
        }
        return result
    }

    private static func ioDisplayLocation(_ id: CGDirectDisplayID) -> String? {
        guard let info = cdInfo?(id)?.takeRetainedValue() as? [String: Any] else { return nil }
        return info["IODisplayLocation"] as? String
    }

    static func discover() -> [CGDirectDisplayID: Display] {
        var displays: [CGDirectDisplayID: Display] = [:]
        var services = externalAVServices()
        let screens = NSScreen.screens.compactMap { screen -> (CGDirectDisplayID, String)? in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return nil }
            return (id, screen.localizedName)
        }

        var unmatched: [(CGDirectDisplayID, String)] = []
        for (id, name) in screens {
            if CGDisplayIsBuiltin(id) != 0 || AppleDisplay.canControl(id) {
                displays[id] = AppleDisplay(id: id, name: name)
            } else if let location = ioDisplayLocation(id),
                      let index = services.firstIndex(where: { $0.location == location }) {
                displays[id] = DDCDisplay(id: id, name: name, service: services.remove(at: index).service)
            } else {
                unmatched.append((id, name))
            }
        }
        // Fall back to pairing leftovers in order (covers the common one-monitor case).
        for (id, name) in unmatched where !services.isEmpty {
            displays[id] = DDCDisplay(id: id, name: name, service: services.removeFirst().service)
        }
        return displays
    }
}

extension Display {
    /// True when the cached value is recent enough to trust (the monitor's own buttons can change it).
    var isFresh: Bool { cached != nil && Date().timeIntervalSince(lastRead) < 5 }
}
