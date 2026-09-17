// Packages/AnteCore/Sources/AnteCore/Search/FuzzyMatcher.swift
import Foundation

/// Subsequence matching with the usual bonuses: prefix, word starts, adjacency. Small, predictable,
/// and good enough for a few hundred palette items.
public enum FuzzyMatcher {
    public static func score(query: String, in text: String) -> Int? {
        let q = Array(query.lowercased())
        if q.isEmpty { return 0 }
        let t = Array(text.lowercased())
        var score = 0
        var qi = 0
        var previousMatch = -2
        for (ti, ch) in t.enumerated() where qi < q.count && ch == q[qi] {
            var gain = 1
            if ti == 0 { gain += 8 }                                   // prefix
            else if !t[ti - 1].isLetter && !t[ti - 1].isNumber { gain += 4 }   // word start
            if ti == previousMatch + 1 { gain += 6 }                   // continuing a run beats a new word
            score += gain
            previousMatch = ti
            qi += 1
        }
        guard qi == q.count else { return nil }
        score -= max(0, t.count - q.count) / 8   // mild preference for shorter candidates
        return score
    }

    public static func rank<T>(_ items: [T], query: String, text: (T) -> String) -> [T] {
        if query.isEmpty { return items }
        let scored: [(offset: Int, score: Int, item: T)] = items.enumerated().compactMap { offset, item in
            guard let s = score(query: query, in: text(item)) else { return nil }
            return (offset, s, item)
        }
        return scored.sorted { $0.score != $1.score ? $0.score > $1.score : $0.offset < $1.offset }.map(\.item)
    }
}
