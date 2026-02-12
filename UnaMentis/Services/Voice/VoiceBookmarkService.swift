// UnaMentis - Voice Bookmark Service
// Orchestrates voice-activated bookmark and flag-for-review flows
//
// Part of Voice Command System

import Foundation
import OSLog

/// Orchestrates the voice-activated bookmark and flag-for-review flows.
///
/// Two operations:
/// - `.bookmark`: pause -> create bookmark -> feedback -> resume
/// - `.flag`: pause -> create bookmark (noted "Flagged for review") + review item -> feedback -> resume
///
/// Both flows are designed to be fast and non-disruptive, completing in ~100-150ms.
@MainActor
public final class VoiceBookmarkService {

    private let logger = Logger(subsystem: "com.unamentis", category: "VoiceBookmarkService")

    public init() {}

    /// Handle `.bookmark` command: creates a positional bookmark at the current position.
    ///
    /// Flow: pause -> create bookmark -> audio/haptic feedback -> resume
    public func performBookmark(
        activity: FlaggableActivity,
        feedback: VoiceActivityFeedback
    ) async {
        logger.info("Performing voice bookmark at segment \(activity.currentSegmentIndex)")

        await activity.pausePlayback()

        let bookmarkId = await activity.createBookmark(note: nil)

        feedback.announceBookmarkSaved()

        if let bookmarkId {
            logger.debug("Bookmark created: \(bookmarkId)")
        }

        await activity.resumePlayback()
    }

    /// Handle `.flag` command: creates a bookmark AND a review item for later study.
    ///
    /// Flow: pause -> create bookmark (noted) -> create review item -> audio/haptic feedback -> resume
    public func performFlag(
        activity: FlaggableActivity,
        feedback: VoiceActivityFeedback
    ) async {
        logger.info("Performing flag-for-review at segment \(activity.currentSegmentIndex)")

        await activity.pausePlayback()

        // 1. Create bookmark with "Flagged for review" note
        let bookmarkId = await activity.createBookmark(note: "Flagged for review")

        // 2. Create ReinforcementItem linked to bookmark
        if let manager = ReinforcementManager.shared {
            do {
                let item = try manager.createItem(
                    currentSegmentText: activity.currentSegmentText ?? "",
                    previousSegmentText: activity.previousSegmentText,
                    segmentIndex: activity.currentSegmentIndex,
                    totalSegments: activity.totalSegments,
                    sourceType: activity.sourceType,
                    sourceId: activity.sourceId,
                    sourceTitle: activity.sourceTitle,
                    bookmarkId: bookmarkId
                )
                logger.debug("Review item created: \(item.displayText)")
            } catch {
                logger.error("Failed to create review item: \(error.localizedDescription)")
            }
        } else {
            logger.warning("ReinforcementManager not initialized, review item not created")
        }

        feedback.announceFlaggedForReview()

        await activity.resumePlayback()
    }
}
