import Foundation

public enum DiagnosticSeverity: String, Codable, Sendable {
    case info = "Info"
    case warning = "Warning"
    case error = "Error"
    case success = "Pass"
}

public struct DiagnosticCheckItem: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public var category: String
    public var title: String
    public var passed: Bool
    public var severity: DiagnosticSeverity
    public var message: String
    public var details: String?
    public var remediationSuggestion: String?
    
    public init(
        id: String = UUID().uuidString,
        category: String,
        title: String,
        passed: Bool,
        severity: DiagnosticSeverity,
        message: String,
        details: String? = nil,
        remediationSuggestion: String? = nil
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.passed = passed
        self.severity = severity
        self.message = message
        self.details = details
        self.remediationSuggestion = remediationSuggestion
    }
}

public struct DiagnosticReport: Identifiable, Codable, Sendable {
    public let id: String
    public var timestamp: Date
    public var hardwareSummary: HardwareSpecs
    public var items: [DiagnosticCheckItem]
    public var overallPassed: Bool
    public var summaryMessage: String
    
    public init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        hardwareSummary: HardwareSpecs,
        items: [DiagnosticCheckItem],
        overallPassed: Bool,
        summaryMessage: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.hardwareSummary = hardwareSummary
        self.items = items
        self.overallPassed = overallPassed
        self.summaryMessage = summaryMessage
    }
}
