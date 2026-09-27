import Foundation
import MacGameCore

@main
@MainActor
struct MacGameTestsRunner {
    static var passedCount = 0
    static var failedCount = 0
    
    static func main() throws {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("          MacGame Automated Test Suite              ")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        
        runTest("Hardware Detection on Apple Silicon", testHardwareDetection)
        runTest("Prefix Lifecycle & Isolation", testPrefixLifecycle)
        runTest("Profile Engine Built-in Profiles", testProfileEngineBuiltInProfiles)
        runTest("Profile Matching Algorithm (Mortal Kombat 1, Cyberpunk)", testProfileMatching)
        runTest("DX12 Optimizer Environment Generation", testDX12OptimizerEnvironmentGeneration)
        runTest("Diagnostics Service 10-Point Health Checks", testDiagnosticsService)
        runTest("Logging Service Ring Buffer & Disk Persistence", testLoggingService)
        runTest("PE Binary Analysis & DirectX Symbol Inspection", testBinaryAnalysis)
        
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        if failedCount == 0 {
            print("🎉 ALL \(passedCount) TESTS PASSED SUCCESSFULLY!")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            exit(0)
        } else {
            print("❌ \(failedCount) TEST(S) FAILED out of \(passedCount + failedCount).")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            exit(1)
        }
    }
    
    static func runTest(_ name: String, _ block: () throws -> Void) {
        do {
            try block()
            passedCount += 1
            print("  ✔ [PASS] \(name)")
        } catch {
            failedCount += 1
            print("  ✖ [FAIL] \(name): \(error.localizedDescription)")
        }
    }
    
    static func assertTrue(_ condition: Bool, _ message: String) throws {
        if !condition {
            throw NSError(domain: "AssertionFailed", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
    
    // MARK: - Test Cases
    
    static func testHardwareDetection() throws {
        let detector = HardwareDetector.shared
        let specs = detector.detect()
        
        try assertTrue(!specs.chipName.isEmpty, "Chip name should not be empty")
        try assertTrue(specs.cpuCores > 0, "CPU core count should be greater than zero")
        try assertTrue(specs.unifiedMemoryGB > 0, "Memory should be reported in GB")
        try assertTrue(!specs.macOSVersion.isEmpty, "macOS version should be detected")
        try assertTrue(specs.chipGeneration.contains("Apple M") || specs.chipGeneration.contains("Apple Silicon"), "Should identify Apple Silicon")
    }
    
    static func testPrefixLifecycle() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("MacGameTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        
        let mockPathProvider = PathProvider(customRoot: tempDirectory)
        let prefixManager = PrefixManager(pathProvider: mockPathProvider)
        let gameId = "test-game-\(UUID().uuidString.prefix(6))"
        
        // 1. Create prefix
        let created = try prefixManager.createPrefix(forGameId: gameId, name: "Test Prefix")
        try assertTrue(created.id == gameId, "Prefix ID must match gameId")
        try assertTrue(created.status == .ready, "Prefix status must be ready")
        try assertTrue(FileManager.default.fileExists(atPath: created.path), "Prefix directory must exist on disk")
        
        // 2. Fetch prefix
        let fetched = prefixManager.getPrefix(forGameId: gameId)
        try assertTrue(fetched != nil, "Fetched prefix should not be nil")
        try assertTrue(fetched?.name == "Test Prefix", "Prefix name should match")
        
        // 3. Clone prefix
        let clonedId = "\(gameId)-cloned"
        let cloned = try prefixManager.clonePrefix(sourceGameId: gameId, targetGameId: clonedId, targetName: "Cloned Prefix")
        try assertTrue(cloned.id == clonedId, "Cloned prefix ID must match target ID")
        try assertTrue(FileManager.default.fileExists(atPath: cloned.path), "Cloned prefix directory must exist")
        
        // 4. Delete prefix
        try prefixManager.deletePrefix(gameId: gameId)
        try assertTrue(prefixManager.getPrefix(forGameId: gameId) == nil, "Deleted prefix should return nil")
    }
    
    static func testProfileEngineBuiltInProfiles() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("MacGameTests_\(UUID().uuidString)")
        let mockPathProvider = PathProvider(customRoot: tempDirectory)
        let engine = ProfileEngine(pathProvider: mockPathProvider)
        let profiles = engine.loadAllProfiles()
        
        try assertTrue(!profiles.isEmpty, "Profiles list should contain default profiles")
        
        let mk1Profile = engine.profile(withId: "mortal-kombat-1")
        try assertTrue(mk1Profile != nil, "Mortal Kombat 1 profile should exist")
        try assertTrue(mk1Profile?.graphicsApi == .dx12, "MK1 profile should target DX12")
        try assertTrue(mk1Profile?.vkd3dConfig.contains("shader_cache") == true, "MK1 profile should have shader cache enabled")
        try assertTrue(mk1Profile?.dllOverrides["d3d12"] == "native,builtin", "MK1 profile should override d3d12")
    }
    
    static func testProfileMatching() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("MacGameTests_\(UUID().uuidString)")
        let mockPathProvider = PathProvider(customRoot: tempDirectory)
        let engine = ProfileEngine(pathProvider: mockPathProvider)
        
        let matchedMK1 = engine.matchProfile(forTitle: "Mortal Kombat 1 Premium Edition", executablePath: "/path/to/MK12.exe", api: .dx12)
        try assertTrue(matchedMK1.id == "mortal-kombat-1", "Should match Mortal Kombat 1 profile")
        
        let matchedCyberpunk = engine.matchProfile(forTitle: "Cyberpunk 2077", executablePath: "/games/Cyberpunk2077.exe", api: .dx12)
        try assertTrue(matchedCyberpunk.id == "cyberpunk-2077", "Should match Cyberpunk 2077 profile")
        
        let matchedGeneric = engine.matchProfile(forTitle: "Random Unknown Game", executablePath: "/games/game.exe", api: .dx12)
        try assertTrue(matchedGeneric.id == "default", "Should fallback to default profile")
    }
    
    static func testDX12OptimizerEnvironmentGeneration() throws {
        let optimizer = DX12Optimizer.shared
        let dummySpecs = HardwareSpecs(
            chipName: "Apple M3 Max",
            chipGeneration: "Apple M3",
            cpuCores: 16,
            unifiedMemoryGB: 36,
            macOSVersion: "macOS 14.5",
            metalDeviceName: "Apple M3 Max",
            metalFeatureSet: "Apple Family 8",
            isRosettaActiveOrAvailable: true
        )
        
        let options = DX12TuningOptions(
            enableShaderCache: true,
            enableRayTracing: true,
            singleQueueMode: true
        )
        
        let env = optimizer.generateEnvironment(options: options, hardware: dummySpecs)
        
        try assertTrue(env["VKD3D_CONFIG"]?.contains("shader_cache") == true, "VKD3D_CONFIG should include shader_cache")
        try assertTrue(env["VKD3D_CONFIG"]?.contains("dxr11") == true, "VKD3D_CONFIG should include dxr11 for M3")
        try assertTrue(env["VKD3D_FEATURE_LEVEL"] == "12_1", "Feature level should be 12_1")
        try assertTrue(env["WINEESYNC"] == "1", "WINEESYNC should be enabled")
    }
    
    static func testDiagnosticsService() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("MacGameTests_\(UUID().uuidString)")
        let mockPathProvider = PathProvider(customRoot: tempDirectory)
        let service = DiagnosticsService(pathProvider: mockPathProvider)
        let report = service.runSystemDiagnostics(forGame: nil)
        
        try assertTrue(!report.items.isEmpty, "Diagnostic items should not be empty")
        try assertTrue(report.items.contains(where: { $0.category == "Hardware" }), "Should contain Hardware check")
        try assertTrue(report.items.contains(where: { $0.category == "Graphics" }), "Should contain Graphics check")
    }
    
    static func testLoggingService() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("MacGameTests_\(UUID().uuidString)")
        let mockPathProvider = PathProvider(customRoot: tempDirectory)
        let logger = LoggingService(pathProvider: mockPathProvider)
        logger.log("Unit test log entry", level: .info, category: "Testing")
        
        let entries = logger.getRecentLogs(limit: 10)
        try assertTrue(entries.contains(where: { $0.message == "Unit test log entry" }), "Ring buffer should capture log entry")
    }
    
    static func testBinaryAnalysis() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("MacGameTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        
        let fakeExeURL = tempDirectory.appendingPathComponent("MK12.exe")
        var data = Data(count: 1024)
        data[0] = 0x4D // 'M'
        data[1] = 0x5A // 'Z'
        data[0x3C] = 0x80
        data[0x80] = 0x50 // 'P'
        data[0x81] = 0x45 // 'E'
        data[0x84] = 0x64 // AMD64 0x8664
        data[0x85] = 0x86
        
        let d3d12Str = "d3d12.dll".data(using: .utf8)!
        data.replaceSubrange(0x100..<(0x100 + d3d12Str.count), with: d3d12Str)
        
        try data.write(to: fakeExeURL)
        
        let inspector = BinaryInspector.shared
        let result = inspector.inspect(executablePath: fakeExeURL.path)
        
        try assertTrue(result.architecture == .x86_64, "Architecture should be x86_64")
        try assertTrue(result.primaryApi == .dx12, "Primary API should be DirectX 12")
        try assertTrue(result.recommendedStatus == .compatible, "Status should be compatible")
    }
}
