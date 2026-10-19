#if os(iOS)
import Foundation
import Darwin

// MARK: - Where the main thread is during a stall
//
// While the watchdog sees the main thread blocked, it takes samples of the main thread's stack: the thread is suspended
// for the few microseconds it takes to copy its program counter and the return addresses along its frame-pointer chain
// into a buffer allocated once at launch, then resumed. Nothing is allocated, locked or looked up while it is suspended;
// the addresses are turned into function names (dladdr, Swift demangling) only after it runs again.
// The samples are counted per function: `hot` is how many samples had each NOOP function on the stack (inclusive), so
// the functions that hold the main thread rank first. Code symbols only; no data.

enum MainThreadSampler {
    static let maxFrames = 96

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

    /// One sample taken during a stall of `stallMs` so far.
    func add(_ addresses: [UInt], stallMs: Double) {
        guard !addresses.isEmpty else { return }
        let frames = addresses.map { MainThreadSampler.frame($0) }
        let app = frames.filter(\.isApp).map { MainThreadSampler.short($0.symbol) }
        lock.lock()
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
        return ["samples": samples, "hot": top(inclusive, limit), "leaf": top(leaf, limit), "system": top(system, 40),
                "images": top(images, 20),
                "worst_stall_ms": (worstStallMs * 10).rounded() / 10, "worst_stack": worstStack]
    }
}
#endif
