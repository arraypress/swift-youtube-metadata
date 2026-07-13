//
//  CommentSort.swift
//  YouTubeComments
//
//  Created by David Sherlock on 2025.
//

import Foundation

/// The order in which YouTube returns comments.
///
/// Mirrors the "Sort by" control in the YouTube comment section.
public enum CommentSort: Sendable {

    /// "Top comments" — YouTube's relevance/engagement ranking (the default).
    case top

    /// "Newest first" — reverse-chronological by publish time.
    case newest

    /// Index into YouTube's `sortFilterSubMenuRenderer.subMenuItems`
    /// (`0` = Top, `1` = Newest) used to pick the matching continuation token.
    var menuIndex: Int {
        switch self {
        case .top: return 0
        case .newest: return 1
        }
    }
}
