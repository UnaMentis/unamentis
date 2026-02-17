// UnaMentis - Playback Orchestrator Delegate
// Callback interface for module-specific behavior.
//
// Part of Core/Audio (shared audio playback infrastructure)

import Foundation

// MARK: - Playback Orchestrator Delegate

/// Callback interface for module-specific playback behavior.
/// All methods have default no-op implementations so modules
/// only override what they need.
public protocol PlaybackOrchestratorDelegate: AnyObject, Sendable {
    /// Called before playing a segment. Return `false` to skip.
    func orchestratorWillPlaySegment(at index: Int) async -> Bool

    /// Called after a segment finishes playing.
    func orchestratorDidFinishSegment(at index: Int) async

    /// Called when the current segment changes.
    func orchestratorDidChangeSegment(index: Int, total: Int) async

    /// Called when all segments have played.
    func orchestratorDidComplete() async

    /// Called on playback error.
    func orchestratorDidEncounterError(_ error: Error) async
}

// MARK: - Default Implementations

extension PlaybackOrchestratorDelegate {
    public func orchestratorWillPlaySegment(at index: Int) async -> Bool { true }
    public func orchestratorDidFinishSegment(at index: Int) async {}
    public func orchestratorDidChangeSegment(index: Int, total: Int) async {}
    public func orchestratorDidComplete() async {}
    public func orchestratorDidEncounterError(_ error: Error) async {}
}
