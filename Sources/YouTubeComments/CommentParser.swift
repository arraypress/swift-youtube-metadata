//
//  CommentParser.swift
//  YouTubeComments
//
//  Created by David Sherlock on 2025.
//

import Foundation

/// Parses a single `youtubei/v1/next` response into comments plus the
/// continuation tokens needed to fetch more.
///
/// YouTube's current comment format is entity-based: the renderer tree
/// (`commentThreadRenderer` / `commentViewModel`) only holds *keys*, while the
/// actual content lives in `frameworkUpdates.entityBatchUpdate.mutations`:
///
/// - `commentEntityPayload` — text, author, publish time, like/reply counts
/// - `engagementToolbarStateEntityPayload` — the creator-heart state
/// - `commentSurfaceEntityPayload` — the paid "Super Thanks" chip
///
/// The `commentViewModel` is the join table (`commentKey`, `toolbarStateKey`,
/// `commentSurfaceKey`, `pinnedText`) that stitches those together in display
/// order.
enum CommentParser {

    /// The outcome of parsing one page.
    struct Page {
        var comments: [Comment] = []
        /// Token for the next page of top-level comments, if any.
        var nextPageToken: String?
        /// `(token, parentId)` pairs for reply threads that can be expanded.
        var replyRequests: [(token: String, parentId: String)] = []
    }

    static func parse(_ response: [String: Any], videoId: String) -> Page {
        var page = Page()

        // 1. Build entity lookup tables from the mutation batch.
        var entityByKey: [String: [String: Any]] = [:]
        var heartByToolbarKey: [String: Bool] = [:]
        var surfaceByKey: [String: [String: Any]] = [:]

        let mutations = (JSONNav.first("mutations", in: response) as? [Any]) ?? []
        for case let mutation as [String: Any] in mutations {
            guard let payload = mutation["payload"] as? [String: Any] else { continue }
            if let entity = payload["commentEntityPayload"] as? [String: Any],
               let key = entity["key"] as? String {
                entityByKey[key] = entity
            } else if let toolbar = payload["engagementToolbarStateEntityPayload"] as? [String: Any],
                      let key = toolbar["key"] as? String {
                heartByToolbarKey[key] = (toolbar["heartState"] as? String) == "TOOLBAR_HEART_STATE_HEARTED"
            } else if let surface = payload["commentSurfaceEntityPayload"] as? [String: Any],
                      let key = surface["key"] as? String {
                surfaceByKey[key] = surface
            }
        }

        // 2. Walk the continuation actions in order, preserving display order
        //    and distinguishing top-level pagination from reply expansion.
        let actions = JSONNav.all("reloadContinuationItemsCommand", in: response)
            + JSONNav.all("appendContinuationItemsAction", in: response)

        for case let action as [String: Any] in actions {
            let targetId = (action["targetId"] as? String) ?? ""
            let items = (action["continuationItems"] as? [Any]) ?? []

            for case let item as [String: Any] in items {
                if let thread = item["commentThreadRenderer"] as? [String: Any] {
                    // Top-level comment.
                    if let vm = viewModel(in: thread),
                       let comment = buildComment(
                            viewModel: vm,
                            renderingPriority: thread["renderingPriority"] as? String,
                            entityByKey: entityByKey,
                            heartByToolbarKey: heartByToolbarKey,
                            surfaceByKey: surfaceByKey,
                            videoId: videoId) {
                        page.comments.append(comment)
                        // "View N replies" token for this thread.
                        if let token = replyToken(in: thread["replies"]) {
                            page.replyRequests.append((token, comment.id))
                        }
                    }
                } else if let vmWrapper = item["commentViewModel"] as? [String: Any] {
                    // A reply comment (arrives in reply-continuation responses).
                    if let vm = viewModel(in: vmWrapper),
                       let comment = buildComment(
                            viewModel: vm,
                            renderingPriority: nil,
                            entityByKey: entityByKey,
                            heartByToolbarKey: heartByToolbarKey,
                            surfaceByKey: surfaceByKey,
                            videoId: videoId) {
                        page.comments.append(comment)
                    }
                } else if let cir = item["continuationItemRenderer"] as? [String: Any] {
                    // Either the next top-level page, or "show more replies".
                    guard let token = JSONNav.string("token", in: cir) else { continue }
                    if targetId.contains("comment-replies-item") {
                        let parent = parentId(fromRepliesTarget: targetId)
                        page.replyRequests.append((token, parent))
                    } else if targetId.hasSuffix("comments-section") || targetId.isEmpty {
                        page.nextPageToken = token
                    }
                }
            }
        }

        return page
    }

    // MARK: - Building a Comment

    private static func buildComment(
        viewModel vm: [String: Any],
        renderingPriority: String?,
        entityByKey: [String: [String: Any]],
        heartByToolbarKey: [String: Bool],
        surfaceByKey: [String: [String: Any]],
        videoId: String
    ) -> Comment? {
        guard let commentKey = vm["commentKey"] as? String,
              let entity = entityByKey[commentKey] else { return nil }

        let properties = entity["properties"] as? [String: Any] ?? [:]
        let author = entity["author"] as? [String: Any] ?? [:]
        let toolbar = entity["toolbar"] as? [String: Any] ?? [:]

        let commentId = (properties["commentId"] as? String)
            ?? (vm["commentId"] as? String) ?? commentKey

        let content = (properties["content"] as? [String: Any])?["content"] as? String ?? ""
        let publishedTime = properties["publishedTime"] as? String ?? ""
        let replyLevel = properties["replyLevel"] as? Int ?? 0
        let isReply = replyLevel > 0

        let likeText = normalizedCount(toolbar["likeCountNotliked"])
        let replyCount = Int(digitsOnly(toolbar["replyCount"] as? String)) ?? 0

        // Heart: authoritative from the toolbar-state entity.
        let toolbarStateKey = (vm["toolbarStateKey"] as? String)
            ?? (properties["toolbarStateKey"] as? String) ?? ""
        let isHearted = heartByToolbarKey[toolbarStateKey] ?? false

        // Pinned: from the view model's pinnedText or the thread priority.
        let pinnedByText = vm["pinnedText"] as? String
        let isPinned = pinnedByText != nil
            || renderingPriority == "RENDERING_PRIORITY_PINNED_COMMENT"

        // Membership badge.
        let sponsorBadgeText = author["sponsorBadgeA11y"] as? String
        let isSponsor = author["sponsorBadgeUrl"] != nil || sponsorBadgeText != nil
        let months = isSponsor ? parseMonths(sponsorBadgeText) : 0

        // Paid "Super Thanks" chip (via the comment surface entity).
        var isPaid = false
        var paidAmount: String?
        if let surfaceKey = vm["commentSurfaceKey"] as? String,
           let surface = surfaceByKey[surfaceKey],
           let chip = surface["pdgCommentChip"] {
            isPaid = true
            paidAmount = parsePaidAmount(chip)
        }

        return Comment(
            id: commentId,
            text: unescape(content),
            author: author["displayName"] as? String ?? "",
            authorChannelId: author["channelId"] as? String ?? "",
            authorAvatarUrl: author["avatarThumbnailUrl"] as? String,
            publishedTimeText: publishedTime,
            isEdited: publishedTime.contains("(edited)"),
            likeCountText: likeText,
            likeCount: parseCount(likeText),
            replyCount: replyCount,
            isReply: isReply,
            parentId: isReply ? parentId(ofCommentId: commentId) : nil,
            isHearted: isHearted,
            isPinned: isPinned,
            pinnedByText: pinnedByText,
            isVerified: author["isVerified"] as? Bool ?? false,
            isChannelOwner: author["isCreator"] as? Bool ?? false,
            isPaid: isPaid,
            paidAmount: paidAmount,
            isSponsor: isSponsor,
            sponsorshipMonths: months,
            sponsorBadgeText: sponsorBadgeText,
            videoId: videoId
        )
    }

    // MARK: - View-model / token helpers

    /// Finds the inner view-model dict (the one carrying `commentKey`) inside a
    /// `commentThreadRenderer` or `commentViewModel` wrapper.
    private static func viewModel(in obj: Any?) -> [String: Any]? {
        JSONNav.firstDict(in: obj) { $0["commentKey"] is String && $0["commentId"] is String }
    }

    /// The "view replies" token for a thread's replies subtree.
    private static func replyToken(in repliesObj: Any?) -> String? {
        guard let repliesObj else { return nil }
        let cir = JSONNav.first("continuationItemRenderer", in: repliesObj)
        return JSONNav.string("token", in: cir)
    }

    private static func parentId(ofCommentId id: String) -> String? {
        guard let dot = id.firstIndex(of: ".") else { return nil }
        return String(id[..<dot])
    }

    private static func parentId(fromRepliesTarget targetId: String) -> String {
        // e.g. "comment-replies-item-<parentId>"
        targetId.replacingOccurrences(of: "comment-replies-item-", with: "")
    }

    // MARK: - Value parsing

    /// Normalises a like count that may arrive as `""` (meaning zero).
    private static func normalizedCount(_ value: Any?) -> String {
        let text = (value as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        return text.isEmpty ? "0" : text
    }

    private static func digitsOnly(_ value: String?) -> String {
        (value ?? "").filter(\.isNumber)
    }

    /// Parses an abbreviated count like `"85K"`, `"1.2M"`, `"1,024"` into an Int.
    static func parseCount(_ text: String) -> Int {
        let cleaned = text.replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let last = cleaned.last else { return 0 }
        let multipliers: [Character: Double] = ["K": 1_000, "M": 1_000_000, "B": 1_000_000_000]
        if let mult = multipliers[Character(last.uppercased())] {
            let number = Double(cleaned.dropLast()) ?? 0
            return Int(number * mult)
        }
        return Int(cleaned) ?? 0
    }

    /// Parses total months from a membership badge label such as
    /// `"Member (3 years, 4 months)"` → `40`, `"Member (5 months)"` → `5`.
    static func parseMonths(_ badge: String?) -> Int {
        guard let badge else { return 0 }
        func value(_ unit: String) -> Int {
            guard let regex = try? NSRegularExpression(pattern: "(\\d+)\\s*\(unit)") else { return 0 }
            let range = NSRange(badge.startIndex..., in: badge)
            guard let match = regex.firstMatch(in: badge, range: range),
                  let r = Range(match.range(at: 1), in: badge) else { return 0 }
            return Int(badge[r]) ?? 0
        }
        return value("year") * 12 + value("month")
    }

    /// Best-effort extraction of the displayed paid amount from a paid chip.
    private static func parsePaidAmount(_ chip: Any?) -> String? {
        for key in ["simpleText", "content"] {
            if let text = JSONNav.string(key, in: chip), !text.isEmpty {
                return text
            }
        }
        // Fall back to the first "text" run string.
        if let runs = JSONNav.first("runs", in: chip) as? [Any] {
            let joined = runs.compactMap { ($0 as? [String: Any])?["text"] as? String }.joined()
            if !joined.isEmpty { return joined }
        }
        return nil
    }

    /// Minimal HTML-entity decode. Comment content usually arrives already
    /// decoded, but a few entities can slip through.
    private static func unescape(_ text: String) -> String {
        var out = text
        for (entity, char) in [
            "&amp;": "&", "&lt;": "<", "&gt;": ">",
            "&quot;": "\"", "&#39;": "'", "&apos;": "'"
        ] {
            out = out.replacingOccurrences(of: entity, with: char)
        }
        return out
    }
}
