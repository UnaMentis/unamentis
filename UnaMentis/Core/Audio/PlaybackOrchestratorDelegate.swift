// UnaMentis - Playback Orchestrator Delegate
// Module-specific hooks for playback events
//
// Each module implements the callbacks it needs (all have defaults)
// to handle position persistence, UI updates, and completion logic.
//
// Part of Core/Audio

import Foundation

// MARK: - Playback Orchestrator Delegate

/// Delegate protocol for module-specific playback event handling.
///
/// All methods have default no-op implementations so modules only
/// need to override the callbacks they care about.
///
/// - Reading List: position persistence, UI chunk change, completion
/// - Session: TTFB recording, turn-end transition
/// - Knowledge Bowl: typically unused (single-segment fire-and-forget)
public protocol PlaybackOrchestratorDelegate: AnyObject, Sendable {

    /// Called before a segment starts playing.
    /// Return `false` to skip this segment (e.g. empty text, filtered content).
    func orchestratorWillPlaySegment(at index: Int) async -> Bool

    /// Called after a segment finishes playing (audio completed).
    /// Use for position persistence, progress tracking, etc.
    func orchestratorDidFinishSegment(at index: Int) async

    /// Called when the current segment index changes.
    /// Use for UI updates (chunk text, progress bar, scroll position).
    func orchestratorDidChangeSegment(index: Int, total: Int) async

    /// Called when all segments have been played.
    func orchestratorDidComplete() async

    /// Called when a playback error occurs.
    func orchestratorDidEncounterError(_ error: Error) async
}

// MARK: - Default Implementations

extension PlaybackOrchestratorDelegate {
    public func orchestratorWillPlaySegment(at index: Int) async -> Bool { true }
    public func orchestratorDidFinishSegment(at index: Int) async { }
    public func orchestratorDidChangeSegment(index: Int, total: Int) async { }
    public func orchestratorDidComplete() async { }
    public func orchestratorDidEncounterError(_ error: Error) async { }
}
