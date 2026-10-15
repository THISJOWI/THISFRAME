import Foundation
import ThisJellyFixCore

/// One local recommendation with its human-readable justification.
public struct LibraryRecommendation: Sendable, Equatable {
    public let item: JellyfinMediaItem
    public let score: Double
    /// Always grounded in a real signal ("Porque viste «X»") — never a
    /// generic line decorating a random pick.
    public let reason: String

    public init(item: JellyfinMediaItem, score: Double, reason: String) {
        self.item = item
        self.score = score
        self.reason = reason
    }
}

/// Personal recommendations from Jellyfin data ONLY (P10): genres, favorites,
/// watched / in-progress / abandoned-early signals and community rating.
///
/// Strategy (local, deterministic, no network, no paid APIs):
/// - affinity per genre: favorite +3, watched +2, in-progress +2
///   (abandoned-early, <8% with no finish, counts +1: a weak signal);
/// - candidates are FRESH items only (never started): watched already
///   happened, in-progress lives in "Estás viendo", favorites have their
///   own view — recommending those would duplicate existing shelves;
/// - score = genre affinity + rating/10 tiebreak; order is fully
///   deterministic (score → rating → name);
/// - every pick carries the witness item behind its top genre, so the UI
///   can say WHY ("Porque viste «X»") instead of faking intelligence.
///
/// Measurable: unit tests pin ordering, exclusions, limit and witness truth.
public enum LibraryRecommender {
    /// Below this progress an unfinished item counts as abandoned-early.
    public static let abandonedThreshold: Double = 8.0

    public static func recommend(
        from library: [JellyfinMediaItem],
        limit: Int = 10
    ) -> [LibraryRecommendation] {
        guard limit > 0, !library.isEmpty else { return [] }

        var affinity: [String: Double] = [:]
        // Top witness item per genre (favorite > watched > in-progress).
        var witness: [String: (name: String, rank: Int)] = [:]

        func note(_ item: JellyfinMediaItem, weight: Double, rank: Int) {
            for genre in item.genres ?? [] {
                let key = genre.lowercased()
                affinity[key, default: 0] += weight
                if let current = witness[key] {
                    if rank < current.rank { witness[key] = (item.name, rank) }
                } else {
                    witness[key] = (item.name, rank)
                }
            }
        }

        for item in library where item.userData?.isFavorite == true {
            note(item, weight: 3, rank: 0)
        }
        for item in library where item.userData?.played == true {
            note(item, weight: 2, rank: 1)
        }
        for item in library {
            guard let pct = item.userData?.playedPercentage,
                  pct > 0, item.userData?.played != true else { continue }
            note(item, weight: pct < abandonedThreshold ? 1 : 2, rank: 2)
        }

        let hasSignals = !affinity.isEmpty

        let candidates = library.filter { item in
            guard item.userData?.played != true,
                  item.userData?.isFavorite != true
            else { return false }
            let pct = item.userData?.playedPercentage ?? 0
            return pct <= 0
        }
        guard !candidates.isEmpty else { return [] }

        let ranked: [(item: JellyfinMediaItem, score: Double, genre: String?)] = candidates.map { item in
            let genres = item.genres ?? []
            var best = 0.0
            var bestGenre: String?
            for genre in genres {
                let w = affinity[genre.lowercased()] ?? 0
                if w > best { best = w; bestGenre = genre }
            }
            let score = best + (item.communityRating ?? 0) / 10.0
            return (item, score, bestGenre)
        }
        .sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            let r0 = $0.item.communityRating ?? 0
            let r1 = $1.item.communityRating ?? 0
            if r0 != r1 { return r0 > r1 }
            return $0.item.name < $1.item.name
        }

        return ranked.prefix(limit).map { entry in
            let reason: String
            if let genre = entry.genre,
               let w = witness[genre.lowercased()] {
                reason = "Porque viste «\(w.name)»"
            } else if hasSignals, let genre = entry.genre {
                reason = "Del género \(genre)"
            } else {
                reason = "Lo mejor valorado de tu biblioteca"
            }
            return LibraryRecommendation(item: entry.item, score: entry.score, reason: reason)
        }
    }
}
