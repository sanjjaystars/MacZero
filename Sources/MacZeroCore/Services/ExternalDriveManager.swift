import Foundation
import AppKit

public protocol ExternalDriveManagerProtocol: Sendable {
    func listDrives() -> [ExternalDrive]
    func getDrive(byId id: String) -> ExternalDrive?
    func getDrive(forPath path: String) -> ExternalDrive?
    func refreshDrives() -> [ExternalDrive]
    func registerExternalFolder(url: URL) throws -> ExternalDrive
    func removeDrive(id: String)
    func benchmarkDrive(id: String) async throws -> DriveBenchmarkResult
    func registerDriveChangeObserver(_ observer: @escaping @Sendable ([ExternalDrive]) -> Void) -> UUID
    func unregisterDriveChangeObserver(id: UUID)
}

public final class ExternalDriveManager: ExternalDriveManagerProtocol, @unchecked Sendable {
    public static let shared = ExternalDriveManager()
    
    private let pathProvider: PathProvider
    private let bookmarkManager: SecurityScopedBookmarkManagerProtocol
    private let loggingService: LoggingService
    
    private var knownDrives: [String: ExternalDrive] = [:]
    private let queue = DispatchQueue(label: "com.maczero.externaldrives")
    private var observers: [UUID: @Sendable ([ExternalDrive]) -> Void] = [:]
    private var notificationTokens: [NSObjectProtocol] = []
    
    public init(
        pathProvider: PathProvider = .shared,
        bookmarkManager: SecurityScopedBookmarkManagerProtocol = SecurityScopedBookmarkManager.shared,
        loggingService: LoggingService = .shared
    ) {
        self.pathProvider = pathProvider
        self.bookmarkManager = bookmarkManager
        self.loggingService = loggingService
        
        loadDrivesFromDisk()
        _ = refreshDrives()
        setupVolumeNotifications()
    }
    
    deinit {
        for token in notificationTokens {
            NotificationCenter.default.removeObserver(token)
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
    }
    
    public func listDrives() -> [ExternalDrive] {
        return queue.sync { Array(knownDrives.values).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
    }
    
    public func getDrive(byId id: String) -> ExternalDrive? {
        return queue.sync { knownDrives[id] }
    }
    
    public func getDrive(forPath path: String) -> ExternalDrive? {
        let drives = listDrives()
        // Match longest matching mountPath prefix
        return drives
            .filter { path.hasPrefix($0.mountPath) }
            .max { $0.mountPath.count < $1.mountPath.count }
    }
    
    public func refreshDrives() -> [ExternalDrive] {
        let fileManager = FileManager.default
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeUUIDStringKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeIsRemovableKey,
            .volumeIsInternalKey,
            .volumeIsReadOnlyKey,
            .volumeLocalizedFormatDescriptionKey
        ]
        
        let mountedURLs = fileManager.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        
        let driveList: [ExternalDrive] = queue.sync {
            var currentFoundIds = Set<String>()
            
            for volumeURL in mountedURLs {
                guard let values = try? volumeURL.resourceValues(forKeys: Set(keys)) else { continue }
                
                let isInternal = values.volumeIsInternal ?? false
                let isRemovable = values.volumeIsRemovable ?? !isInternal
                
                // We focus on external/removable volumes or mounted secondary volumes in /Volumes
                let isRootVolume = volumeURL.path == "/"
                if isRootVolume { continue }
                
                let name = values.volumeName ?? volumeURL.lastPathComponent
                let uuid = values.volumeUUIDString ?? volumeURL.path
                let total = Int64(values.volumeTotalCapacity ?? 0)
                let free = Int64(values.volumeAvailableCapacityForImportantUsage ?? Int64(values.volumeAvailableCapacity ?? 0))
                let isReadOnly = values.volumeIsReadOnly ?? false
                let format = values.volumeLocalizedFormatDescription ?? detectFileSystem(at: volumeURL.path)
                
                let driveId = uuid
                currentFoundIds.insert(driveId)
                
                let existing = knownDrives[driveId]
                let bookmarkData = existing?.securityBookmarkData ?? (try? bookmarkManager.createBookmark(for: volumeURL, id: driveId))
                
                let updatedDrive = ExternalDrive(
                    id: driveId,
                    name: name,
                    mountPath: volumeURL.path,
                    volumeUUID: uuid,
                    totalCapacityBytes: total,
                    freeCapacityBytes: free,
                    fileSystemType: format,
                    isReadOnly: isReadOnly,
                    isRemovable: isRemovable,
                    isInternal: isInternal,
                    isConnected: true,
                    connectionType: isRemovable ? "USB / External" : "Internal Secondary",
                    detectedGamesCount: existing?.detectedGamesCount ?? 0,
                    securityBookmarkData: bookmarkData,
                    lastScanned: existing?.lastScanned,
                    benchmark: existing?.benchmark
                )
                
                knownDrives[driveId] = updatedDrive
            }
            
            // Mark previously known drives that are no longer mounted as disconnected
            for (id, drive) in knownDrives {
                if !currentFoundIds.contains(id) {
                    var disconnected = drive
                    disconnected.isConnected = false
                    knownDrives[id] = disconnected
                    loggingService.log("External volume '\(drive.name)' (\(drive.mountPath)) is currently disconnected.", level: .warn, category: "ExternalDrives")
                }
            }
            
            try? persistDrivesToDisk()
            return Array(knownDrives.values)
        }
        
        notifyObservers(driveList)
        return driveList
    }

    
    public func registerExternalFolder(url: URL) throws -> ExternalDrive {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            throw NSError(domain: "ExternalDriveManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Selected path is not a valid directory: \(url.path)"])
        }
        
        let bookmarkData = try bookmarkManager.createBookmark(for: url, id: nil)
        
        // Find if this folder belongs to an existing drive
        if let existing = getDrive(forPath: url.path) {
            loggingService.log("Folder '\(url.path)' registered under existing drive '\(existing.name)'", level: .info, category: "ExternalDrives")
            return existing
        }
        
        // Create custom external drive entry
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeUUIDStringKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeIsReadOnlyKey]
        let values = try? url.resourceValues(forKeys: Set(keys))
        
        let driveName = values?.volumeName ?? url.lastPathComponent
        let driveUUID = values?.volumeUUIDString ?? UUID().uuidString
        let total = Int64(values?.volumeTotalCapacity ?? 0)
        let free = Int64(values?.volumeAvailableCapacity ?? 0)
        let isReadOnly = values?.volumeIsReadOnly ?? false
        let format = detectFileSystem(at: url.path)
        
        let drive = ExternalDrive(
            id: driveUUID,
            name: driveName,
            mountPath: url.path,
            volumeUUID: driveUUID,
            totalCapacityBytes: total,
            freeCapacityBytes: free,
            fileSystemType: format,
            isReadOnly: isReadOnly,
            isRemovable: true,
            isInternal: false,
            isConnected: true,
            connectionType: "External Folder",
            detectedGamesCount: 0,
            securityBookmarkData: bookmarkData,
            lastScanned: Date()
        )
        
        queue.sync {
            knownDrives[drive.id] = drive
            try? persistDrivesToDisk()
        }
        
        notifyObservers(listDrives())
        return drive
    }
    
    public func removeDrive(id: String) {
        queue.sync {
            knownDrives.removeValue(forKey: id)
            try? bookmarkManager.removeBookmark(forId: id)
            try? persistDrivesToDisk()
        }
        notifyObservers(listDrives())
    }
    
    public func benchmarkDrive(id: String) async throws -> DriveBenchmarkResult {
        guard let drive = getDrive(byId: id), drive.isConnected else {
            throw NSError(domain: "ExternalDriveManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "Drive not found or disconnected: \(id)"])
        }
        
        if drive.isReadOnly {
            throw NSError(domain: "ExternalDriveManager", code: 403, userInfo: [NSLocalizedDescriptionKey: "Drive is read-only. Cannot run write benchmark."])
        }
        
        let testDir = URL(fileURLWithPath: drive.mountPath).appendingPathComponent(".maczero_benchmark_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testDir) }
        
        let testFile = testDir.appendingPathComponent("bench.bin")
        let sizeMB = 64
        let sizeBytes = sizeMB * 1024 * 1024
        var testData = Data(count: sizeBytes)
        // Fill data with non-zero entropy
        testData.withUnsafeMutableBytes { ptr in
            for i in stride(from: 0, to: ptr.count, by: 4) {
                ptr.storeBytes(of: UInt32(i), toByteOffset: i, as: UInt32.self)
            }
        }
        
        // 1. Measure Write Speed
        let writeStart = CFAbsoluteTimeGetCurrent()
        try testData.write(to: testFile, options: [.atomic])
        let writeEnd = CFAbsoluteTimeGetCurrent()
        let writeDuration = max(0.001, writeEnd - writeStart)
        let writeMBps = Double(sizeMB) / writeDuration
        
        // 2. Measure Read Speed
        let readStart = CFAbsoluteTimeGetCurrent()
        let readBackData = try Data(contentsOf: testFile)
        let readEnd = CFAbsoluteTimeGetCurrent()
        let readDuration = max(0.001, readEnd - readStart)
        let readMBps = Double(readBackData.count) / (1024.0 * 1024.0) / readDuration
        
        let result = DriveBenchmarkResult(readSpeedMBps: readMBps, writeSpeedMBps: writeMBps, testedAt: Date(), testFileSizeMB: sizeMB)
        
        queue.sync {
            if var d = knownDrives[id] {
                d.benchmark = result
                knownDrives[id] = d
                try? persistDrivesToDisk()
            }
        }
        
        notifyObservers(listDrives())
        return result
    }
    
    public func registerDriveChangeObserver(_ observer: @escaping @Sendable ([ExternalDrive]) -> Void) -> UUID {
        let token = UUID()
        queue.sync {
            observers[token] = observer
        }
        // Fire initial state
        observer(listDrives())
        return token
    }
    
    public func unregisterDriveChangeObserver(id: UUID) {
        queue.sync {
            _ = observers.removeValue(forKey: id)
        }
    }
    
    private func notifyObservers(_ drives: [ExternalDrive]) {
        let currentObservers = queue.sync { Array(observers.values) }
        for obs in currentObservers {
            obs(drives)
        }
    }
    
    private func setupVolumeNotifications() {
        let nc = NSWorkspace.shared.notificationCenter
        
        let mountToken = nc.addObserver(
            forName: NSWorkspace.didMountNotification,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            guard let self = self else { return }
            let path = (notif.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL)?.path ?? "Volume"
            self.loggingService.log("Detected external volume mount: \(path)", level: .info, category: "ExternalDrives")
            _ = self.refreshDrives()
        }
        notificationTokens.append(mountToken)
        
        let unmountToken = nc.addObserver(
            forName: NSWorkspace.didUnmountNotification,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            guard let self = self else { return }
            let path = (notif.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL)?.path ?? "Volume"
            self.loggingService.log("Detected external volume unmount: \(path)", level: .warn, category: "ExternalDrives")
            _ = self.refreshDrives()
        }
        notificationTokens.append(unmountToken)
        
        let renameToken = nc.addObserver(
            forName: NSWorkspace.didRenameVolumeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.loggingService.log("Detected volume rename event. Refreshing drives...", level: .info, category: "ExternalDrives")
            _ = self?.refreshDrives()
        }
        notificationTokens.append(renameToken)
    }
    
    private func detectFileSystem(at path: String) -> String {
        var stat = statfs()
        if statfs(path, &stat) == 0 {
            let name = withUnsafePointer(to: &stat.f_fstypename) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MFSTYPENAMELEN)) {
                    String(cString: $0)
                }
            }
            switch name.lowercased() {
            case "apfs": return "APFS"
            case "hfs": return "Mac OS Extended (HFS+)"
            case "msdos": return "FAT32"
            case "exfat": return "exFAT"
            case "ntfs": return "NTFS"
            default: return name.uppercased()
            }
        }
        return "APFS"
    }
    
    private func drivesFileURL() -> URL {
        return pathProvider.configDirectory.appendingPathComponent("external_drives.json")
    }
    
    private func loadDrivesFromDisk() {
        let file = drivesFileURL()
        guard let data = try? Data(contentsOf: file),
              let list = try? JSONDecoder().decode([ExternalDrive].self, from: data) else {
            return
        }
        for d in list {
            knownDrives[d.id] = d
        }
    }
    
    private func persistDrivesToDisk() throws {
        try pathProvider.ensureDirectoriesExist()
        let file = drivesFileURL()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        let data = try encoder.encode(Array(knownDrives.values))
        try data.write(to: file)
    }
}
