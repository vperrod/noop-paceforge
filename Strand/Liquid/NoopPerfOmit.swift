import Foundation

/// DEBUG `-NoopPerfOmit a,b`: pieces of Today the perf run leaves out, to find which one costs the main thread.
enum NoopPerfOmit {
    static let keys: Set<String> = {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-NoopPerfOmit"), i + 1 < args.count else { return [] }
        return Set(args[i + 1].split(separator: ",").map(String.init))
        #else
        return []
        #endif
    }()
    static func has(_ key: String) -> Bool { keys.contains(key) }
}
