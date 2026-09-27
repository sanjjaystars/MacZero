import Foundation

public enum LogLevel: String, Codable, Sendable {
    case debug = "DEBUG"
    case info = "INFO"
    case warn = "WARN"
    case error = "ERROR"
}

public struct LogEntry: Identifiable, Codable, Sendable {
    public let id: String
    public let timestamp: Date
    public let level: LogLevel
    public let category: String
    public let message: String
    
    public init(level: LogLevel, category: String, message: String) {
        self.id = UUID().uuidString
        self.timestamp = Date()
        self.level = level
        self.category = category
        self.message = message
    }
    
    public var formattedLine: String {
        let formatter = ISO8601DateFormatter()
        let timeStr = formatter.string(from: timestamp)
        return "[\(timeStr)] [\(level.rawValue)] [\(category)] \(message)"
    }
}

public final class LoggingService: @unchecked Sendable {
    public static let shared = LoggingService()
    
    private let pathProvider: PathProvider
    private let queue = DispatchQueue(label: "com.maczero.logging", qos: .utility)
    private var inMemoryLogs: [LogEntry] = []
    private let maxInMemoryEntries = 1000
    
    public init(pathProvider: PathProvider = .shared) {
        self.pathProvider = pathProvider
    }
    
    public func log(_ message: String, level: LogLevel = .info, category: String = "Core", gameId: String? = nil) {
        let entry = LogEntry(level: level, category: category, message: message)
        
        queue.async {
            self.inMemoryLogs.append(entry)
            if self.inMemoryLogs.count > self.maxInMemoryEntries {
                self.inMemoryLogs.removeFirst(self.inMemoryLogs.count - self.maxInMemoryEntries)
            }
            
            // Console print for dev/CLI
            print(entry.formattedLine)
            
            // Write to global log
            try? self.pathProvider.ensureDirectoriesExist()
            let globalLogURL = self.pathProvider.logsDirectory.appendingPathComponent("maczero.log")
            self.appendLine(entry.formattedLine, to: globalLogURL)
            
            // Write to game specific log if present
            if let gid = gameId {
                let gameLogURL = self.pathProvider.logPath(forGameId: gid)
                self.appendLine(entry.formattedLine, to: gameLogURL)
            }
        }
    }
    
    public func getRecentLogs(limit: Int = 100) -> [LogEntry] {
        return queue.sync {
            Array(inMemoryLogs.suffix(limit))
        }
    }
    
    public func getGameLog(gameId: String) -> String? {
        let logURL = pathProvider.logPath(forGameId: gameId)
        return try? String(contentsOf: logURL, encoding: .utf8)
    }
    
    private func appendLine(_ line: String, to fileURL: URL) {
        let lineData = (line + "\n").data(using: .utf8)!
        if FileManager.default.fileExists(atPath: fileURL.path) {
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                handle.seekToEndOfFile()
                handle.write(lineData)
                try? handle.close()
            }
        } else {
            try? lineData.write(to: fileURL)
        }
    }
}
