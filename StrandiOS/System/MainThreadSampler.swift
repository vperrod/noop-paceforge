#if os(iOS)
import Foundation
import Darwin
import MachO

// MARK: - Where the main thread is during a stall
//
// While the watchdog sees the main thread blocked, it takes samples of the main thread's stack: the thread is suspended
// for the few microseconds it takes to copy its program counter and the return addresses along its frame-pointer chain
// into a buffer allocated once at launch, then resumed. Nothing is allocated, locked or looked up while it is suspended;
// the addresses are turned into function names (dladdr, Swift demangling) only after it runs again.
// The samples are counted per function: `hot` is how many samples had each NOOP function on the stack (inclusive), so
// the functions that hold the main thread rank first. Code symbols only; no data.

enum MainThreadSampler {
    /// Deep enough for a full SwiftUI layout stack; the old 96 cut the interesting end off.
    static let maxFrames = 256

    private static var mainPort: mach_port_t = 0
    private static var stackLow: UInt = 0
    private static var stackHigh: UInt = 0
    private static let buffer = UnsafeMutablePointer<UInt>.allocate(capacity: maxFrames)
    private static var appImagePrefix: String = ""

    /// On the main thread, once, at launch.
    static func captureMainThread() {
        mainPort = mach_thread_self()
        let thread = pthread_self()
        stackHigh = UInt(bitPattern: pthread_get_stackaddr_np(thread))
        stackLow = stackHigh - UInt(pthread_get_stacksize_np(thread))
        appImagePrefix = Bundle.main.bundlePath
        loadImageTable()
    }

    // MARK: Raw frames as Image+offset

    // dladdr hands back "<redacted>" for the local symbols of a stripped release build, which is why the stacks used to
    // arrive as module names only. The raw return addresses are always right, so a frame is kept as the image it falls in
    // plus its offset from that image's load address: offline, the Mach-O symbol table of the matching build (found by
    // `executableUUID`) turns "NOOP+0x1a2b3c" into a function. The image table is read once at launch; looking an address
    // up takes no lock and allocates nothing but the result string, so it is safe next to a stalled main thread.

    struct ImageRange {
        let base: UInt
        let end: UInt
        let name: String
    }

    private static var imageTable: [ImageRange] = []
    /// LC_UUID of the main executable ("?" until captureMainThread has run), the key to its symbol table.
    private(set) static var executableUUID = "?"
    private(set) static var executableName = "NOOP"

    private static func loadImageTable() {
        var table: [ImageRange] = []
        for index in 0..<_dyld_image_count() {
            guard let header = _dyld_get_image_header(index), let cName = _dyld_get_image_name(index),
                  header.pointee.magic == UInt32(truncatingIfNeeded: MH_MAGIC_64) else { continue }
            let raw = UnsafeRawPointer(header)
            var command = raw + MemoryLayout<mach_header_64>.size
            var textSize: UInt = 0
            var uuid: String?
            for _ in 0..<header.pointee.ncmds {
                let base = command.loadUnaligned(as: load_command.self)
                if base.cmd == UInt32(truncatingIfNeeded: LC_SEGMENT_64) {
                    let segment = command.loadUnaligned(as: segment_command_64.self)
                    let name = withUnsafeBytes(of: segment.segname) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
                    if name == "__TEXT" { textSize = UInt(segment.vmsize) }
                } else if base.cmd == UInt32(truncatingIfNeeded: LC_UUID) {
                    uuid = UUID(uuid: command.loadUnaligned(as: uuid_command.self).uuid).uuidString
                }
                command += Int(base.cmdsize)
            }
            let start = UInt(bitPattern: header)
            let name = (String(cString: cName) as NSString).lastPathComponent
            if header.pointee.filetype == UInt32(truncatingIfNeeded: MH_EXECUTE) {
                executableName = name
                if let uuid { executableUUID = uuid }
            }
            if textSize > 0 { table.append(ImageRange(base: start, end: start + textSize, name: name)) }
        }
        imageTable = table.sorted { $0.base < $1.base }
    }

    /// "NOOP+0x1a2b3c": the image the address falls in and its offset from the image's load address. Frame 0 is the
    /// program counter; every other frame is a return address (symbolicate it at offset - 1).
    static func imageOffset(_ address: UInt) -> String {
        let probe = address > 0 ? address - 1 : address
        var low = 0
        var high = imageTable.count - 1
        while low <= high {
            let mid = (low + high) / 2
            let image = imageTable[mid]
            if probe < image.base {
                high = mid - 1
            } else if probe >= image.end {
                low = mid + 1
            } else {
                return "\(image.name)+0x\(String(address - image.base, radix: 16))"
            }
        }
        // Loaded after launch (dlopen): ask dyld, once per frame.
        var info = Dl_info()
        if dladdr(UnsafeRawPointer(bitPattern: probe), &info) != 0, let name = info.dli_fname {
            let image = (String(cString: name) as NSString).lastPathComponent
            return "\(image)+0x\(String(address - UInt(bitPattern: info.dli_fbase), radix: 16))"
        }
        return "?+0x\(String(address, radix: 16))"
    }

    /// The main thread's return addresses, innermost first. Empty when sampling is not possible here.
    static func sample() -> [UInt] {
        #if arch(arm64)
        guard mainPort != 0 else { return [] }
        guard thread_suspend(mainPort) == KERN_SUCCESS else { return [] }
        var count = 0
        var state = arm_thread_state64_t()
        var stateCount = mach_msg_type_number_t(MemoryLayout<arm_thread_state64_t>.size / MemoryLayout<natural_t>.size)
        let got = withUnsafeMutablePointer(to: &state) {
            $0.withMemoryRebound(to: natural_t.self, capacity: Int(stateCount)) {
                thread_get_state(mainPort, ARM_THREAD_STATE64, $0, &stateCount)
            }
        }
        if got == KERN_SUCCESS {
            buffer[0] = UInt(state.__pc) & addressMask
            buffer[1] = UInt(state.__lr) & addressMask
            count = 2
            var fp = UInt(state.__fp)
            while count < maxFrames, fp >= stackLow, fp + 16 <= stackHigh, fp & 0x7 == 0 {
                guard let frame = UnsafePointer<UInt>(bitPattern: fp) else { break }
                let next = frame[0]
                let ret = frame[1] & addressMask
                if ret == 0 { break }
                buffer[count] = ret
                count += 1
                if next <= fp { break }
                fp = next
            }
        }
        thread_resume(mainPort)
        return Array(UnsafeBufferPointer(start: buffer, count: count))
        #else
        return []
        #endif
    }

    /// Strips pointer-authentication bits from a return address.
    private static let addressMask: UInt = 0x0000_000F_FFFF_FFFF

    struct Frame {
        let symbol: String
        let isApp: Bool
        var image: String = "?"
    }

    private static var cache: [UInt: Frame] = [:]
    private static let cacheLock = NSLock()

    /// The function containing `address` (a return address, so the call instruction is just before it).
    static func frame(_ address: UInt) -> Frame {
        cacheLock.lock()
        if let hit = cache[address] {
            cacheLock.unlock()
            return hit
        }
        cacheLock.unlock()
        var info = Dl_info()
        var result = Frame(symbol: String(format: "0x%lx", address), isApp: false)
        if dladdr(UnsafeRawPointer(bitPattern: address > 0 ? address - 1 : address), &info) != 0 {
            let image = info.dli_fname.map { String(cString: $0) } ?? "?"
            let isApp = image.hasPrefix(appImagePrefix)
            let imageName = (image as NSString).lastPathComponent
            if let name = info.dli_sname {
                result = Frame(symbol: demangle(String(cString: name)), isApp: isApp, image: imageName)
            } else {
                let offset = address - UInt(bitPattern: info.dli_fbase)
                result = Frame(symbol: "\(imageName)+0x\(String(offset, radix: 16))", isApp: isApp, image: imageName)
            }
        }
        cacheLock.lock()
        cache[address] = result
        cacheLock.unlock()
        return result
    }

    static func demangle(_ name: String) -> String {
        guard name.hasPrefix("$s") || name.hasPrefix("_$s") || name.hasPrefix("$S") else { return name }
        return name.withCString { pointer -> String in
            guard let out = noopSwiftDemangle(pointer, strlen(pointer), nil, nil, 0) else { return name }
            defer { free(out) }
            return String(cString: out)
        }
    }

    /// A short form of a demangled Swift name: no module prefix, no argument types, at most 140 characters.
    static func short(_ symbol: String) -> String {
        let s = symbol.replacingOccurrences(of: "NOOP.", with: "").replacingOccurrences(of: "StrandDesign.", with: "")
            .replacingOccurrences(of: "SwiftUI.", with: "")
        return String(s.prefix(140))
    }
}

/// The Swift runtime's demangler (exported by libswiftCore); the result is malloc'ed and freed by the caller.
@_silgen_name("swift_demangle")
private func noopSwiftDemangle(_ mangled: UnsafePointer<CChar>?, _ length: Int, _ output: UnsafeMutablePointer<CChar>?,
                               _ outputSize: UnsafeMutablePointer<Int>?, _ flags: UInt32) -> UnsafeMutablePointer<CChar>?

/// Counts the stall samples per NOOP function (inclusive) and keeps the first stack of the longest stall.
final class MainThreadProfile {
    static let shared = MainThreadProfile()

    private let lock = NSLock()
    private var inclusive: [String: Int] = [:]
    private var leaf: [String: Int] = [:]
    /// Frameworks' own functions (SwiftUI, Charts, CoreText, UIKit) on the stack, and samples per binary.
    private var system: [String: Int] = [:]
    private var images: [String: Int] = [:]
    private(set) var samples = 0
    private var worstStack: [String] = []
    private var worstStallMs = 0.0

    private static let interesting: Set<String> = ["SwiftUI", "SwiftUICore", "Charts", "CoreText", "UIKitCore",
                                                   "AttributeGraph", "Foundation", "CoreFoundation", "libswiftCore.dylib",
                                                   "QuartzCore", "CoreGraphics", "MarkdownUI"]

    /// Per screen visit: the NOOP functions on the stack and the innermost frame (where the time is actually spent).
    private var perScreen: [String: (samples: Int, app: [String: Int], leaf: [String: Int])] = [:]

    /// One sample taken during a stall of `stallMs` so far, on screen visit `screen`.
    func add(_ addresses: [UInt], stallMs: Double, screen: String = "") {
        guard !addresses.isEmpty else { return }
        let frames = addresses.map { MainThreadSampler.frame($0) }
        let app = frames.filter(\.isApp).map { MainThreadSampler.short($0.symbol) }
        let innermost = frames.first.map { "\($0.image): \(MainThreadSampler.short($0.symbol))" } ?? "?"
        lock.lock()
        var entry = perScreen[screen] ?? (0, [:], [:])
        entry.samples += 1
        for name in Set(app) { entry.app[name, default: 0] += 1 }
        entry.leaf[innermost, default: 0] += 1
        perScreen[screen] = entry
        samples += 1
        for name in Set(app) { inclusive[name, default: 0] += 1 }
        let framework = frames.filter { !$0.isApp && Self.interesting.contains($0.image) }
        for name in Set(framework.map { "\($0.image): \(MainThreadSampler.short($0.symbol))" }) { system[name, default: 0] += 1 }
        for image in Set(frames.map(\.image)) { images[image, default: 0] += 1 }
        if let top = app.first { leaf[top, default: 0] += 1 }
        if stallMs > worstStallMs {
            worstStallMs = stallMs
            worstStack = frames.prefix(40).map { ($0.isApp ? "" : "· ") + MainThreadSampler.short($0.symbol) }
        }
        lock.unlock()
    }

    /// {"samples": n, "hot": [[name, count]], "leaf": [[name, count]], "worst_stall_ms": x, "worst_stack": [...]}.
    func summary(limit: Int = 25) -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }
        func top(_ table: [String: Int], _ count: Int) -> [[Any]] {
            table.sorted { $0.value > $1.value }.prefix(count).map { [$0.key, $0.value] }
        }
        var screens: [String: Any] = [:]
        for (name, entry) in perScreen {
            screens[name] = ["samples": entry.samples, "app": top(entry.app, 12), "innermost": top(entry.leaf, 15)]
        }
        return ["samples": samples, "hot": top(inclusive, limit), "leaf": top(leaf, limit), "system": top(system, 25),
                "images": top(images, 20), "screens": screens,
                "worst_stall_ms": (worstStallMs * 10).rounded() / 10, "worst_stack": worstStack]
    }
}

// MARK: - Full stacks of a freeze, on disk at once

/// While the main thread is stalled for 1.5 s, 4 s, 8 s (and every 4 s after that), the watchdog thread takes the main
/// thread's whole stack as `Image+offset` frames (never redacted, never symbolicated on the phone) and stores it here,
/// written to `freeze-stacks.json` before the next tick, so it is on disk when a watchdog kill ends the process at ~10 s.
/// The next launch's report carries the file as `freeze_stacks`. The watchdog thread takes only this lock, never one the
/// main thread can hold during a stall; the report builder (any other thread) takes it for a copy.
enum FreezeStacks {
    /// Seconds into a stall at which a capture is taken. The last mark repeats every `repeatEvery` until `maxCaptures`.
    static let marks: [Double] = [1.5, 4, 8]
    static let repeatEvery = 4.0
    static let maxCaptures = 5
    static let maxStalls = 3

    private static let lock = NSLock()
    private static var stalls: [[String: Any]] = []
    /// The stall being captured: the watchdog's chunk number and the record's id.
    private static var current: (chunk: UInt64, id: String)?

    private static var fileURL: URL? { NoopDiagStore.shared.directory?.appendingPathComponent("freeze-stacks.json") }

    /// The second at which capture number `count` (0-based) is due, or nil when the stall has had its share.
    static func dueAt(_ count: Int) -> Double? {
        guard count < maxCaptures else { return nil }
        return count < marks.count ? marks[count] : marks[marks.count - 1] + repeatEvery * Double(count - marks.count + 1)
    }

    /// Once, at launch, before the watchdog starts: the stalls of earlier runs that no upload has delivered yet.
    static func load() {
        lock.lock()
        defer { lock.unlock() }
        guard let url = fileURL, let data = try? Data(contentsOf: url),
              let saved = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return }
        stalls = saved
    }

    /// Watchdog thread. `chunk` identifies the stall; `stallMs` is how long it had lasted when the stack was taken.
    static func record(chunk: UInt64, stallMs: Double, screen: String, section: String?, stack: [UInt]) {
        guard !stack.isEmpty else { return }
        let capture: [String: Any] = ["at_ms": Int(stallMs.rounded()), "n": stack.count,
                                      "frames": stack.map { MainThreadSampler.imageOffset($0) }]
        lock.lock()
        defer { lock.unlock() }
        if current?.chunk != chunk {
            let id = UUID().uuidString
            stalls.append(["id": id, "started_at": NoopDiagStore.now() - stallMs / 1000,
                           "build": NoopDiagStore.appBuild, "version": NoopDiagStore.appVersion,
                           "exe_uuid": MainThreadSampler.executableUUID, "exe": MainThreadSampler.executableName,
                           "pid": Int(ProcessInfo.processInfo.processIdentifier),
                           "screen": screen, "section": section ?? "", "captures": [[String: Any]]()])
            if stalls.count > maxStalls { stalls.removeFirst(stalls.count - maxStalls) }
            current = (chunk, id)
        }
        guard let id = current?.id, let index = stalls.firstIndex(where: { $0["id"] as? String == id }) else { return }
        stalls[index]["captures"] = ((stalls[index]["captures"] as? [[String: Any]]) ?? []) + [capture]
        stalls[index]["max_ms"] = Int(stallMs.rounded())
        stalls[index]["screen_last"] = screen
        write()
    }

    /// Watchdog thread: the stall `chunk` ended after `ms`. A stall without this was ended by the process dying.
    static func finish(chunk: UInt64, ms: Double) {
        lock.lock()
        defer { lock.unlock() }
        guard let now = current, now.chunk == chunk,
              let index = stalls.firstIndex(where: { $0["id"] as? String == now.id }) else { return }
        stalls[index]["ended_ms"] = Int(ms.rounded())
        current = nil
        write()
    }

    /// How many captures the stall `chunk` has so far.
    static func captureCount(chunk: UInt64) -> Int {
        lock.lock()
        defer { lock.unlock() }
        guard let now = current, now.chunk == chunk,
              let entry = stalls.first(where: { $0["id"] as? String == now.id }) else { return 0 }
        return (entry["captures"] as? [[String: Any]])?.count ?? 0
    }

    static func snapshot() -> [[String: Any]] {
        lock.lock()
        defer { lock.unlock() }
        return stalls
    }

    /// After a delivered upload: forget the stalls that began before `cutoff` (when the report was built), except the one
    /// still being captured.
    static func clear(before cutoff: Double) {
        lock.lock()
        defer { lock.unlock() }
        stalls.removeAll { ($0["started_at"] as? Double ?? 0) < cutoff && $0["id"] as? String != current?.id }
        write()
    }

    private static func write() {
        guard let url = fileURL, let data = try? JSONSerialization.data(withJSONObject: stalls) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
#endif
