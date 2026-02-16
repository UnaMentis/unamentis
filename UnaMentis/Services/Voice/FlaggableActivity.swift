// UnaMentis - FlaggableActivity Protocol
// Interface for activities that support voice-activated bookmark and flag-for-review
//
// Part of Voice Command System

import Foundation

/// Protocol for activities that support voice-activated bookmark and flag-for-review.
///
/// Any ViewModel managing learning content playback can conform to this protocol
/// to enable the `.bookmark` and `.flag` voice commands. The protocol provides
/// access to the current playback state and segment content needed to create
/// bookmarks and review items.
///
/// Conforming types:
/// - `ReadingPlaybackViewModel` (primary, Reading List playback)
/// - `SessionViewModel` (secondary, AI conversation sessions)
@MainActor
public protocol FlaggableActivity: AnyObject {

    /// The current segment index being played
    var currentSegmentIndex: Int32 { get }

    /// Total number of segments in the current content
    var totalSegments: Int32 { get }

    /// Text content of the current segment
    var currentSegmentText: String? { get }

    /// Text content of the previous segment (for context).
    /// Returns nil if at the first segment.
    var previousSegmentText: String? { get }

    /// Human-readable title of the source material
    var sourceTitle: String { get }

    /// Source type for categorization in the review system
    var sourceType: ReinforcementSourceType { get }

    /// Source identifier (reading item ID, curriculum ID, etc.)
    var sourceId: UUID? { get }

    /// Create a bookmark at the current position.
    /// Returns the bookmark ID for linking to the review item,
    /// or nil if bookmarks are not supported for this activity type.
    func createBookmark(note: String?) async -> UUID?

    /// Pause the current playback
    func pausePlayback() async

    /// Resume playback after bookmark/flag is saved
    func resumePlayback() async
}
