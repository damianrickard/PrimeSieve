import Foundation
import Darwin

public struct MachineDetails: Codable, Sendable {
    public var cpu: String
    public var logicalCores: Int
    public var physicalCores: Int?
    public var executionArchitecture: String
    public var hardwareArchitecture: String
    public var translation: String
    public var operatingSystem: String

    public static func capture() -> Self {
        func value(_ name: String) -> String? {
            var size = 0
            guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
            var bytes = [CChar](repeating: 0, count: size)
            guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else { return nil }
            return String(cString: bytes)
        }
        func number(_ name: String) -> Int32? {
            var value: Int32 = 0, size = MemoryLayout<Int32>.size
            return sysctlbyname(name, &value, &size, nil, 0) == 0 ? value : nil
        }
        let arm = number("hw.optional.arm64") == 1
        return .init(cpu: value("machdep.cpu.brand_string") ?? value("hw.model") ?? "Unknown",
                     logicalCores: ProcessInfo.processInfo.processorCount,
                     physicalCores: number("hw.physicalcpu").map(Int.init),
                     executionArchitecture: BenchmarkSession.architecture,
                     hardwareArchitecture: arm ? "arm64" : "x86_64",
                     translation: number("sysctl.proc_translated") == 1 ? "Rosetta host; worker architecture not inspected" : "Native host; worker architecture not inspected",
                     operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString)
    }
}
