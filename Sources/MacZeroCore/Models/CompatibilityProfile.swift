import Foundation

public struct CompatibilityProfile: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public var gameTitle: String
    public var graphicsApi: GraphicsAPI
    public var runtimeRecommendation: String
    public var vkd3dConfig: [String]
    public var dxvkConfig: [String: String]
    public var environment: [String: String]
    public var dllOverrides: [String: String]
    public var launchArguments: [String]
    public var dependencies: [String]
    public var knownIssues: [String]
    public var recommendedSettings: [String: String]
    public var version: Int
    public var author: String
    public var notes: String?
    
    public var name: String { gameTitle }
    
    public init(
        id: String,
        gameTitle: String,
        graphicsApi: GraphicsAPI = .dx12,
        runtimeRecommendation: String = "wine-staging-9.0",
        vkd3dConfig: [String] = ["shader_cache"],
        dxvkConfig: [String: String] = [:],
        environment: [String: String] = [:],
        dllOverrides: [String: String] = ["d3d12": "native,builtin"],
        launchArguments: [String] = [],
        dependencies: [String] = [],
        knownIssues: [String] = [],
        recommendedSettings: [String: String] = [:],
        version: Int = 1,
        author: String = "MacZero Team",
        notes: String? = nil
    ) {
        self.id = id
        self.gameTitle = gameTitle
        self.graphicsApi = graphicsApi
        self.runtimeRecommendation = runtimeRecommendation
        self.vkd3dConfig = vkd3dConfig
        self.dxvkConfig = dxvkConfig
        self.environment = environment
        self.dllOverrides = dllOverrides
        self.launchArguments = launchArguments
        self.dependencies = dependencies
        self.knownIssues = knownIssues
        self.recommendedSettings = recommendedSettings
        self.version = version
        self.author = author
        self.notes = notes
    }
}
