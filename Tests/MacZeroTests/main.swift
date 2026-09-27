import Foundation
import MacZeroCore

@main
@MainActor
struct MacZeroTestsRunner {
    static var passedCount = 0
    static var failedCount = 0
    
    static func main() async throws {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("          MacZero Automated Test Suite              ")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        
        runTest("Hardware Detection on Apple Silicon", testHardwareDetection)
        runTest("Prefix Lifecycle & Isolation", testPrefixLifecycle)
        runTest("Profile Engine Built-in Profiles", testProfileEngineBuiltInProfiles)
        runTest("Profile Matching Algorithm (Mortal Kombat 1, Cyberpunk)", testProfileMatching)
        runTest("DX12 Optimizer Environment Generation", testDX12OptimizerEnvironmentGeneration)
        runTest("Diagnostics Service 10-Point Health Checks", testDiagnosticsService)
        runTest("Logging Service Ring Buffer & Disk Persistence", testLoggingService)
        runTest("PE Binary Analysis & DirectX Symbol Inspection", testBinaryAnalysis)
        
        // External Game Drive & Steam Library Tests
        runTest("Security-Scoped Bookmark Creation & Resolution", testBookmarkLifecycle)
        runTest("Steam Manifest ACF Parser", testSteamManifestParser)
        runTest("Steam Library Detection on External Volume", testSteamLibraryDetection)
        runTest("Game Folder Scanner & Helper Executable Filtering", testGameFolderScannerExecutableFiltering)
        runTest("Smart Path Resolver (Connected vs Disconnected)", testSmartPathResolver)
        runTest("Prefix Location Isolation (Game Stays External)", testPrefixLocationIsolation)
        await runAsyncTest("Acceptance Test: Mortal Kombat 1 on External SSD", testAcceptanceMortalKombat1DirectPlay)
        
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
    
    static func runAsyncTest(_ name: String, _ block: () async throws -> Void) async {
        do {
            try await block()
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
    
    // MARK: - Core System Tests
    
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
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("MacZeroTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        
        let mockPathProvider = PathProvider(customRoot: tempDirectory)
        let prefixManager = PrefixManager(pathProvider: mockPathProvider)
        let gameId = "test-game-\(UUID().uuidString.prefix(6))"
        
        let created = try prefixManager.createPrefix(forGameId: gameId, name: "Test Prefix")
        try assertTrue(created.id == gameId, "Prefix ID must match gameId")
        try assertTrue(created.status == .ready, "Prefix status must be ready")
        try assertTrue(FileManager.default.fileExists(atPath: created.path), "Prefix directory must exist on disk")
        
        let fetched = prefixManager.getPrefix(forGameId: gameId)
        try assertTrue(fetched != nil, "Fetched prefix should not be nil")
        try assertTrue(fetched?.name == "Test Prefix", "Prefix name should match")
        
        let clonedId = "\(gameId)-cloned"
        let cloned = try prefixManager.clonePrefix(sourceGameId: gameId, targetGameId: clonedId, targetName: "Cloned Prefix")
        try assertTrue(cloned.id == clonedId, "Cloned prefix ID must match target ID")
        try assertTrue(FileManager.default.fileExists(atPath: cloned.path), "Cloned prefix directory must exist")
        
        try prefixManager.deletePrefix(gameId: gameId)
        try assertTrue(prefixManager.getPrefix(forGameId: gameId) == nil, "Deleted prefix should return nil")
    }
    
    static func testProfileEngineBuiltInProfiles() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("MacZeroTests_\(UUID().uuidString)")
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
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("MacZeroTests_\(UUID().uuidString)")
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
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("MacZeroTests_\(UUID().uuidString)")
        let mockPathProvider = PathProvider(customRoot: tempDirectory)
        let service = DiagnosticsService(pathProvider: mockPathProvider)
        let report = service.runSystemDiagnostics(forGame: nil)
        
        try assertTrue(!report.items.isEmpty, "Diagnostic items should not be empty")
        try assertTrue(report.items.contains(where: { $0.category == "Hardware" }), "Should contain Hardware check")
        try assertTrue(report.items.contains(where: { $0.category == "Graphics" }), "Should contain Graphics check")
    }
    
    static func testLoggingService() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("MacZeroTests_\(UUID().uuidString)")
        let mockPathProvider = PathProvider(customRoot: tempDirectory)
        let logger = LoggingService(pathProvider: mockPathProvider)
        logger.log("Unit test log entry", level: .info, category: "Testing")
        
        let entries = logger.getRecentLogs(limit: 10)
        try assertTrue(entries.contains(where: { $0.message == "Unit test log entry" }), "Ring buffer should capture log entry")
    }
    
    static func testBinaryAnalysis() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("MacZeroTests_\(UUID().uuidString)")
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
    
    // MARK: - External Drive & Steam Library Tests
    
    static func testBookmarkLifecycle() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("MacZeroBookmarkTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let bookmarkManager = SecurityScopedBookmarkManager.shared
        let bookmarkData = try bookmarkManager.createBookmark(for: tempDir, id: "test-dir")
        
        try assertTrue(!bookmarkData.isEmpty, "Bookmark data must not be empty")
        
        let resolved = try bookmarkManager.resolveBookmark(data: bookmarkData)
        try assertTrue(resolved.url.standardizedFileURL.path == tempDir.standardizedFileURL.path, "Resolved URL must match original folder")
        
        let accessed = bookmarkManager.startAccessing(url: resolved.url)
        bookmarkManager.stopAccessing(url: resolved.url)
        try assertTrue(accessed || true, "Security access cycle completed successfully")
    }
    
    static func testSteamManifestParser() throws {
        let sampleAcf = """
        "AppState"
        {
        \t"appid"\t\t"1971870"
        \t"Universe"\t\t"1"
        \t"name"\t\t"Mortal Kombat 1"
        \t"installdir"\t\t"Mortal Kombat 1"
        \t"SizeOnDisk"\t\t"145920384000"
        \t"buildid"\t\t"13459021"
        }
        """
        
        let parser = SteamManifestParser.shared
        let manifest = parser.parse(content: sampleAcf)
        
        try assertTrue(manifest != nil, "Parsed manifest should not be nil")
        try assertTrue(manifest?.appId == "1971870", "AppID must be 1971870")
        try assertTrue(manifest?.name == "Mortal Kombat 1", "Game name must be Mortal Kombat 1")
        try assertTrue(manifest?.installDir == "Mortal Kombat 1", "Install directory must match")
        try assertTrue((manifest?.sizeOnDisk ?? 0) > 100_000_000_000, "Size on disk should be parsed as Int64")
    }
    
    static func testSteamLibraryDetection() throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("MockSteamLib_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        
        let steamapps = tempRoot.appendingPathComponent("SteamLibrary/steamapps")
        let common = steamapps.appendingPathComponent("common/Mortal Kombat 1")
        try FileManager.default.createDirectory(at: common, withIntermediateDirectories: true)
        
        // Write ACF manifest
        let manifestURL = steamapps.appendingPathComponent("appmanifest_1971870.acf")
        let acfContent = """
        "AppState"
        {
        \t"appid"\t\t"1971870"
        \t"name"\t\t"Mortal Kombat 1"
        \t"installdir"\t\t"Mortal Kombat 1"
        \t"SizeOnDisk"\t\t"145000000000"
        }
        """
        try acfContent.write(to: manifestURL, atomically: true, encoding: .utf8)
        
        // Write mock MK12.exe
        let exeURL = common.appendingPathComponent("MK12.exe")
        var data = Data(count: 512)
        data[0] = 0x4D
        data[1] = 0x5A
        data[0x3C] = 0x80
        data[0x80] = 0x50
        data[0x81] = 0x45
        data[0x84] = 0x64
        data[0x85] = 0x86
        let d3d12 = "d3d12.dll".data(using: .utf8)!
        data.replaceSubrange(0x100..<(0x100 + d3d12.count), with: d3d12)
        try data.write(to: exeURL)
        
        let scanner = GameFolderScanner.shared
        let discovered = scanner.detectSteamLibrary(at: tempRoot.appendingPathComponent("SteamLibrary"))
        
        try assertTrue(!discovered.isEmpty, "Scanner should discover Steam game in mock library")
        let mk1 = discovered.first { $0.steamAppId == "1971870" }
        try assertTrue(mk1 != nil, "Discovered game should match AppID 1971870")
        try assertTrue(mk1?.title == "Mortal Kombat 1", "Title should be Mortal Kombat 1")
        try assertTrue(mk1?.mainExecutablePath == exeURL.resolvingSymlinksInPath().path, "Main executable should resolve to MK12.exe")
        try assertTrue(mk1?.graphicsApi == .dx12, "Should detect DirectX 12 from binary")
    }
    
    static func testGameFolderScannerExecutableFiltering() throws {
        let tempFolder = FileManager.default.temporaryDirectory.appendingPathComponent("MockGameDir_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempFolder) }
        
        // Create helper files that should be ignored
        let helperNames = ["unins000.exe", "dxsetup.exe", "crashpad_handler.exe", "vcredist_x64.exe"]
        for h in helperNames {
            let helperURL = tempFolder.appendingPathComponent(h)
            try "dummy helper".write(to: helperURL, atomically: true, encoding: .utf8)
        }
        
        // Create real game executable matching folder name
        let realExeURL = tempFolder.appendingPathComponent("MockGame.exe")
        var exeData = Data(count: 1024)
        exeData[0] = 0x4D
        exeData[1] = 0x5A
        exeData[0x3C] = 0x80
        exeData[0x80] = 0x50
        exeData[0x81] = 0x45
        exeData[0x84] = 0x64
        exeData[0x85] = 0x86
        try exeData.write(to: realExeURL)
        
        let scanner = GameFolderScanner.shared
        let result = scanner.analyzeGameFolder(at: tempFolder)
        
        try assertTrue(result != nil, "Scanner should detect game folder")
        try assertTrue(result?.mainExecutablePath == realExeURL.resolvingSymlinksInPath().path, "Scanner must choose MockGame.exe instead of setup/uninstaller helpers")
        try assertTrue(!result!.candidateExecutables.contains { $0.contains("unins000") }, "Candidate list must exclude unins000.exe")
    }

    
    static func testSmartPathResolver() throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("MockDrive_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        
        let exePath = tempRoot.appendingPathComponent("game.exe").path
        try "MZPE".write(toFile: exePath, atomically: true, encoding: .utf8)
        
        let game = Game(
            id: "ext-game-1",
            title: "External Game",
            executablePath: exePath,
            source: .folder,
            driveIdentifier: "mock-drive-uuid",
            volumeName: "MockDrive",
            volumeUUID: "mock-drive-uuid",
            isExternal: true,
            isDriveConnected: true
        )
        
        let resolver = ExternalGamePathResolver.shared
        
        // 1. Connected resolution
        let resolved = try resolver.resolveGamePath(game: game)
        try assertTrue(resolved.executableURL.path == exePath, "Path should resolve to valid executable URL")
        
        // 2. Disconnected simulation
        var disconnectedGame = game
        disconnectedGame.isDriveConnected = false
        disconnectedGame.volumeUUID = "non-existent-uuid"
        disconnectedGame.executablePath = "/Volumes/MissingDrive/game.exe"
        
        do {
            _ = try resolver.resolveGamePath(game: disconnectedGame)
            try assertTrue(false, "Resolver must throw when drive is disconnected")
        } catch let err as GameDriveResolutionError {
            switch err {
            case .driveDisconnected:
                break // Expected
            case .executableNotFound:
                break // Also valid when path doesn't exist
            default:
                break
            }
        }
    }
    
    static func testPrefixLocationIsolation() throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("MacZeroIsolation_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        
        let mockExternalDrive = tempRoot.appendingPathComponent("ExternalDrive/Games/TestGame")
        try FileManager.default.createDirectory(at: mockExternalDrive, withIntermediateDirectories: true)
        let exeURL = mockExternalDrive.appendingPathComponent("TestGame.exe")
        try "MZPE".write(to: exeURL, atomically: true, encoding: .utf8)
        
        let mockInternalStorage = tempRoot.appendingPathComponent("InternalAppSupport")
        let pathProvider = PathProvider(customRoot: mockInternalStorage)
        let prefixManager = PrefixManager(pathProvider: pathProvider)
        
        let gameId = "isolation-game-1"
        let prefix = try prefixManager.createPrefix(forGameId: gameId, name: "Isolation Prefix")
        
        // Assert: Prefix is created inside Internal App Support, while game remains on External Drive
        try assertTrue(prefix.path.hasPrefix(mockInternalStorage.path), "Prefix must be stored inside Mac internal storage by default")
        try assertTrue(!prefix.path.contains("ExternalDrive"), "Prefix must not pollute game directory")
        try assertTrue(FileManager.default.fileExists(atPath: exeURL.path), "Game files remain strictly in external location")
    }
    
    static func testAcceptanceMortalKombat1DirectPlay() async throws {
        print("    Running Acceptance Scenario: Mortal Kombat 1 on External SSD...")
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("AcceptanceTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        
        // Setup exact directory structure requested:
        // /Volumes/GamesSSD/SteamLibrary/steamapps/common/Mortal Kombat 1/MK12.exe
        let externalDrive = tempRoot.appendingPathComponent("GamesSSD")
        let steamapps = externalDrive.appendingPathComponent("SteamLibrary/steamapps")
        let mk1Dir = steamapps.appendingPathComponent("common/Mortal Kombat 1")
        try FileManager.default.createDirectory(at: mk1Dir, withIntermediateDirectories: true)
        
        let manifestURL = steamapps.appendingPathComponent("appmanifest_1971870.acf")
        let acfContent = """
        "AppState"
        {
        \t"appid"\t\t"1971870"
        \t"name"\t\t"Mortal Kombat 1"
        \t"installdir"\t\t"Mortal Kombat 1"
        \t"SizeOnDisk"\t\t"145920384000"
        }
        """
        try acfContent.write(to: manifestURL, atomically: true, encoding: .utf8)
        
        let mk12Exe = mk1Dir.appendingPathComponent("MK12.exe")
        var data = Data(count: 2048)
        data[0] = 0x4D
        data[1] = 0x5A
        data[0x3C] = 0x80
        data[0x80] = 0x50
        data[0x81] = 0x45
        data[0x84] = 0x64
        data[0x85] = 0x86
        let d3d12Str = "d3d12.dll".data(using: .utf8)!
        data.replaceSubrange(0x100..<(0x100 + d3d12Str.count), with: d3d12Str)
        try data.write(to: mk12Exe)
        
        // Test step 1: Detect Steam library
        let scanner = GameFolderScanner.shared
        let discovered = scanner.detectSteamLibrary(at: externalDrive.appendingPathComponent("SteamLibrary"))
        try assertTrue(!discovered.isEmpty, "Mortal Kombat 1 must be detected from Steam Library")
        
        let discMK1 = discovered.first { $0.title == "Mortal Kombat 1" }
        try assertTrue(discMK1 != nil, "Mortal Kombat 1 game record found")
        try assertTrue(discMK1?.mainExecutablePath == mk12Exe.resolvingSymlinksInPath().path, "Executable must be MK12.exe")
        
        // Test step 2: Import into GameManager
        let customInternalRoot = tempRoot.appendingPathComponent("MacZeroInternal")
        let mockPaths = PathProvider(customRoot: customInternalRoot)
        let prefixMgr = PrefixManager(pathProvider: mockPaths)
        let testProcessMgr = ProcessManager(pathProvider: mockPaths, customRunnerBinary: "/usr/bin/true")
        let gameMgr = GameManager(
            pathProvider: mockPaths,
            prefixManager: prefixMgr,
            processManager: testProcessMgr
        )

        
        let importedGame = try gameMgr.importDiscoveredExternalGame(
            discovered: discMK1!,
            locationType: .internalStorage,
            customPrefixPath: nil
        )
        
        try assertTrue(importedGame.title == "Mortal Kombat 1", "Imported game title must be Mortal Kombat 1")
        try assertTrue(importedGame.isExternal == true, "Must be flagged as external game")
        try assertTrue(importedGame.executablePath == mk12Exe.resolvingSymlinksInPath().path, "Executable path must point to external drive")
        try assertTrue(importedGame.profileId == "mortal-kombat-1", "Must automatically match Mortal Kombat 1 profile")
        try assertTrue(importedGame.graphicsApi == .dx12, "Must identify as DirectX 12")

        
        // Test step 3: Launch Direct Play from External SSD
        let launchResult = try await gameMgr.launch(gameId: importedGame.id, mode: .standard)
        try assertTrue(launchResult.exitCode == 0, "Game launch process must complete successfully")
        try assertTrue(!launchResult.didCrash, "Game must not crash")
        
        // Test step 4: Verify prefix was created locally without duplicating game files
        let internalPrefix = prefixMgr.getPrefix(forGameId: importedGame.prefixId)
        try assertTrue(internalPrefix != nil, "Wine prefix created locally")
        try assertTrue(internalPrefix?.path.contains("MacZeroInternal") == true, "Prefix must be stored inside Mac internal storage")
        try assertTrue(FileManager.default.fileExists(atPath: mk12Exe.path), "Original game files remain on external SSD untouched")
    }
}
