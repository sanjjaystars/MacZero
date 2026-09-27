import Foundation
import Metal

public struct HardwareSpecs: Codable, Sendable {
    public let chipName: String
    public let chipGeneration: String
    public let cpuCores: Int
    public let performanceCores: Int?
    public let efficiencyCores: Int?
    public let gpuCores: Int?
    public let unifiedMemoryGB: Int
    public let macOSVersion: String
    public let metalDeviceName: String
    public let metalFeatureSet: String
    public let isRosettaActiveOrAvailable: Bool
    
    public init(
        chipName: String,
        chipGeneration: String,
        cpuCores: Int,
        performanceCores: Int? = nil,
        efficiencyCores: Int? = nil,
        gpuCores: Int? = nil,
        unifiedMemoryGB: Int,
        macOSVersion: String,
        metalDeviceName: String,
        metalFeatureSet: String,
        isRosettaActiveOrAvailable: Bool
    ) {
        self.chipName = chipName
        self.chipGeneration = chipGeneration
        self.cpuCores = cpuCores
        self.performanceCores = performanceCores
        self.efficiencyCores = efficiencyCores
        self.gpuCores = gpuCores
        self.unifiedMemoryGB = unifiedMemoryGB
        self.macOSVersion = macOSVersion
        self.metalDeviceName = metalDeviceName
        self.metalFeatureSet = metalFeatureSet
        self.isRosettaActiveOrAvailable = isRosettaActiveOrAvailable
    }
}

public final class HardwareDetector: Sendable {
    public static let shared = HardwareDetector()
    
    public init() {}
    
    public func detect() -> HardwareSpecs {
        let chipName = getSysctlString("machdep.cpu.brand_string") ?? detectModelIdentifier()
        let chipGen = extractChipGeneration(from: chipName)
        let totalCores = getSysctlInt("hw.ncpu") ?? ProcessInfo.processInfo.activeProcessorCount
        let pCores = getSysctlInt("hw.perflevel0.numcpus")
        let eCores = getSysctlInt("hw.perflevel1.numcpus")
        let memoryBytes = getSysctlUInt64("hw.memsize") ?? ProcessInfo.processInfo.physicalMemory
        let memoryGB = Int(memoryBytes / (1024 * 1024 * 1024))
        
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        
        var metalName = "Unknown GPU"
        var metalFeature = "Metal 3"
        var gpuCoreCount: Int? = nil
        
        if let metalDevice = MTLCreateSystemDefaultDevice() {
            metalName = metalDevice.name
            if metalDevice.supportsFamily(.apple9) {
                metalFeature = "Apple Family 9 (M4/M5 class)"
            } else if metalDevice.supportsFamily(.apple8) {
                metalFeature = "Apple Family 8 (M3 class, Hardware Ray Tracing)"
            } else if metalDevice.supportsFamily(.apple7) {
                metalFeature = "Apple Family 7 (M1/M2 class)"
            } else if metalDevice.supportsFamily(.metal3) {
                metalFeature = "Metal 3 (Standard)"
            }
            
            // Try detecting GPU core count via IOKit/device name if available
            gpuCoreCount = estimateGPUCores(from: metalName, chipGen: chipGen)
        }
        
        let rosetta = checkRosettaAvailability()
        
        return HardwareSpecs(
            chipName: chipName,
            chipGeneration: chipGen,
            cpuCores: totalCores,
            performanceCores: pCores,
            efficiencyCores: eCores,
            gpuCores: gpuCoreCount,
            unifiedMemoryGB: memoryGB,
            macOSVersion: osVersion,
            metalDeviceName: metalName,
            metalFeatureSet: metalFeature,
            isRosettaActiveOrAvailable: rosetta
        )
    }
    
    private func getSysctlString(_ key: String) -> String? {
        var size: Int = 0
        sysctlbyname(key, nil, &size, nil, 0)
        guard size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname(key, &buffer, &size, nil, 0)
        let bytes = buffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
    
    private func getSysctlInt(_ key: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname(key, &value, &size, nil, 0) == 0 {
            return Int(value)
        }
        return nil
    }
    
    private func getSysctlUInt64(_ key: String) -> UInt64? {
        var value: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        if sysctlbyname(key, &value, &size, nil, 0) == 0 {
            return value
        }
        return nil
    }
    
    private func detectModelIdentifier() -> String {
        return getSysctlString("hw.model") ?? "Apple Silicon Mac"
    }
    
    private func extractChipGeneration(from name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("m5") { return "Apple M5" }
        if lower.contains("m4") { return "Apple M4" }
        if lower.contains("m3") { return "Apple M3" }
        if lower.contains("m2") { return "Apple M2" }
        if lower.contains("m1") { return "Apple M1" }
        return "Apple Silicon"
    }
    
    private func estimateGPUCores(from metalName: String, chipGen: String) -> Int? {
        // GPU cores can be identified from chip model variations
        let lower = metalName.lowercased()
        if lower.contains("max") { return 30 }
        if lower.contains("pro") { return 14 }
        if lower.contains("ultra") { return 64 }
        if chipGen.contains("M4") { return 10 }
        if chipGen.contains("M3") { return 10 }
        if chipGen.contains("M2") { return 10 }
        if chipGen.contains("M1") { return 8 }
        return nil
    }
    
    private func checkRosettaAvailability() -> Bool {
        // Check if oahd or Rosetta 2 translation runtime exists on disk
        let rosettaPath = "/Library/Apple/usr/libexec/oah/libRosettaRuntime"
        let rosettaPathAlt = "/Library/Apple/usr/libexec/oah/oahd"
        return FileManager.default.fileExists(atPath: rosettaPath) || FileManager.default.fileExists(atPath: rosettaPathAlt)
    }
}
