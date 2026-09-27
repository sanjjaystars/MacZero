import Foundation

public struct PersistedBookmark: Codable, Sendable {
    public let id: String
    public let originalPath: String
    public let bookmarkData: Data
    public let createdAt: Date
    public var lastResolvedAt: Date?
    
    public init(id: String, originalPath: String, bookmarkData: Data, createdAt: Date = Date(), lastResolvedAt: Date? = nil) {
        self.id = id
        self.originalPath = originalPath
        self.bookmarkData = bookmarkData
        self.createdAt = createdAt
        self.lastResolvedAt = lastResolvedAt
    }
}

public protocol SecurityScopedBookmarkManagerProtocol: Sendable {
    func createBookmark(for url: URL, id: String?) throws -> Data
    func resolveBookmark(data: Data) throws -> (url: URL, isStale: Bool)
    func resolveBookmark(forId id: String) -> (url: URL, isStale: Bool)?
    func startAccessing(url: URL) -> Bool
    func stopAccessing(url: URL)
    func saveBookmark(id: String, url: URL, data: Data) throws
    func removeBookmark(forId id: String) throws
    func listBookmarks() -> [PersistedBookmark]
}

public final class SecurityScopedBookmarkManager: SecurityScopedBookmarkManagerProtocol, @unchecked Sendable {
    public static let shared = SecurityScopedBookmarkManager()
    
    private let pathProvider: PathProvider
    private let loggingService: LoggingService
    private var bookmarks: [String: PersistedBookmark] = [:]
    private let queue = DispatchQueue(label: "com.maczero.bookmarks")
    private var activeAccessUrls: Set<URL> = []
    
    public init(
        pathProvider: PathProvider = .shared,
        loggingService: LoggingService = .shared
    ) {
        self.pathProvider = pathProvider
        self.loggingService = loggingService
        loadBookmarksFromDisk()
    }
    
    public func createBookmark(for url: URL, id: String? = nil) throws -> Data {
        do {
            let data = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: [.volumeIdentifierKey, .volumeUUIDStringKey, .volumeNameKey],
                relativeTo: nil
            )
            
            let key = id ?? url.path
            try saveBookmark(id: key, url: url, data: data)
            loggingService.log("Created security-scoped bookmark for '\(url.path)' [ID: \(key)]", level: .info, category: "Bookmarks")
            return data
        } catch {
            // Fallback for non-sandboxed or file systems where .withSecurityScope might throw
            loggingService.log("Standard security scope failed for '\(url.path)': \(error.localizedDescription). Falling back to minimal bookmark.", level: .warn, category: "Bookmarks")
            let fallbackData = try url.bookmarkData(
                options: .suitableForBookmarkFile,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            let key = id ?? url.path
            try saveBookmark(id: key, url: url, data: fallbackData)
            return fallbackData
        }
    }
    
    public func resolveBookmark(data: Data) throws -> (url: URL, isStale: Bool) {
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            return (url, isStale)
        } catch {
            // Try resolving without security scope option as fallback
            let url = try URL(
                resolvingBookmarkData: data,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            return (url, isStale)
        }
    }
    
    public func resolveBookmark(forId id: String) -> (url: URL, isStale: Bool)? {
        guard let entry = queue.sync(execute: { bookmarks[id] }) else { return nil }
        guard let resolved = try? resolveBookmark(data: entry.bookmarkData) else { return nil }
        
        if resolved.isStale {
            loggingService.log("Bookmark for ID '\(id)' is stale. Attempting refresh...", level: .warn, category: "Bookmarks")
            if let refreshedData = try? createBookmark(for: resolved.url, id: id) {
                try? saveBookmark(id: id, url: resolved.url, data: refreshedData)
            }
        }
        
        return resolved
    }
    
    public func startAccessing(url: URL) -> Bool {
        return queue.sync {
            let isAccessing = url.startAccessingSecurityScopedResource()
            if isAccessing {
                activeAccessUrls.insert(url)
                loggingService.log("Started security-scoped access for: \(url.path)", level: .debug, category: "Bookmarks")
            }
            return isAccessing
        }
    }
    
    public func stopAccessing(url: URL) {
        queue.sync {
            if activeAccessUrls.contains(url) {
                url.stopAccessingSecurityScopedResource()
                activeAccessUrls.remove(url)
                loggingService.log("Stopped security-scoped access for: \(url.path)", level: .debug, category: "Bookmarks")
            }
        }
    }
    
    public func saveBookmark(id: String, url: URL, data: Data) throws {
        try queue.sync {
            let entry = PersistedBookmark(
                id: id,
                originalPath: url.path,
                bookmarkData: data,
                createdAt: Date(),
                lastResolvedAt: Date()
            )
            bookmarks[id] = entry
            try persistToDisk()
        }
    }
    
    public func removeBookmark(forId id: String) throws {
        try queue.sync {
            bookmarks.removeValue(forKey: id)
            try persistToDisk()
        }
    }
    
    public func listBookmarks() -> [PersistedBookmark] {
        return queue.sync { Array(bookmarks.values) }
    }
    
    private func bookmarksFileURL() -> URL {
        return pathProvider.configDirectory.appendingPathComponent("bookmarks.json")
    }
    
    private func loadBookmarksFromDisk() {
        let file = bookmarksFileURL()
        guard let data = try? Data(contentsOf: file),
              let decoded = try? JSONDecoder().decode([String: PersistedBookmark].self, from: data) else {
            return
        }
        self.bookmarks = decoded
    }
    
    private func persistToDisk() throws {
        try pathProvider.ensureDirectoriesExist()
        let file = bookmarksFileURL()
        let data = try JSONEncoder().encode(bookmarks)
        try data.write(to: file)
    }
}
