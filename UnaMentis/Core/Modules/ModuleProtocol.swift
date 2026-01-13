// UnaMentis - Module Protocol
// Defines the interface for specialized training modules
//
// Modules are self-contained training systems that can be registered
// and discovered by the app. Each module provides its own views,
// session management, and progress tracking.

import SwiftUI

/// Protocol defining a specialized training module
///
/// Modules are focused training systems for specific goals like
/// competition preparation or skill development. Each module:
/// - Has its own root view and dashboard
/// - Tracks progress independently
/// - May support team collaboration
/// - May include speed training and competition simulation
public protocol ModuleProtocol: Identifiable, Hashable, Sendable {
    /// Unique identifier for the module
    var id: String { get }

    /// Display name for the module
    var name: String { get }

    /// Brief description (1-2 sentences)
    var shortDescription: String { get }

    /// Detailed description for the module info page
    var longDescription: String { get }

    /// SF Symbol name for the module icon
    var iconName: String { get }

    /// Theme color for the module UI
    var themeColor: Color { get }

    /// Whether the module supports team/multiplayer mode
    var supportsTeamMode: Bool { get }

    /// Whether the module has speed training features
    var supportsSpeedTraining: Bool { get }

    /// Whether the module simulates competition scenarios
    var supportsCompetitionSim: Bool { get }

    /// Version of the module
    var version: String { get }

    /// Creates the root view for the module
    @MainActor
    func makeRootView() -> AnyView

    /// Creates the dashboard/summary view shown in the modules list
    @MainActor
    func makeDashboardView() -> AnyView
}

// MARK: - Default Implementations

extension ModuleProtocol {
    public var supportsTeamMode: Bool { false }
    public var supportsSpeedTraining: Bool { false }
    public var supportsCompetitionSim: Bool { false }
    public var version: String { "1.0.0" }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Type-Erased Module

/// Type-erased wrapper for modules to enable storage in collections
public struct SpecializedModule: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let shortDescription: String
    public let longDescription: String
    public let iconName: String
    public let themeColor: Color
    public let supportsTeamMode: Bool
    public let supportsSpeedTraining: Bool
    public let supportsCompetitionSim: Bool
    public let version: String

    private let _makeRootView: @MainActor @Sendable () -> AnyView
    private let _makeDashboardView: @MainActor @Sendable () -> AnyView

    public init<M: ModuleProtocol>(_ module: M) {
        self.id = module.id
        self.name = module.name
        self.shortDescription = module.shortDescription
        self.longDescription = module.longDescription
        self.iconName = module.iconName
        self.themeColor = module.themeColor
        self.supportsTeamMode = module.supportsTeamMode
        self.supportsSpeedTraining = module.supportsSpeedTraining
        self.supportsCompetitionSim = module.supportsCompetitionSim
        self.version = module.version
        self._makeRootView = { @MainActor @Sendable in module.makeRootView() }
        self._makeDashboardView = { @MainActor @Sendable in module.makeDashboardView() }
    }

    @MainActor
    public func makeRootView() -> AnyView {
        _makeRootView()
    }

    @MainActor
    public func makeDashboardView() -> AnyView {
        _makeDashboardView()
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: SpecializedModule, rhs: SpecializedModule) -> Bool {
        lhs.id == rhs.id
    }
}
