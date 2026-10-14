import CoreGraphics
import Foundation

extension OCRService {
  typealias Candidate = (rect: CGRect, text: String)

  static func orderedLines(from candidates: [Candidate]) -> [String] {
    let cleaned =
      candidates
      .map { (rect: $0.rect, text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines)) }
      .filter { !$0.text.isEmpty && $0.rect.width > 0 && $0.rect.height > 0 }
    return rows(of: droppingContainers(of: cleaned)).flatMap { fragments(of: $0) }
  }

  private struct Line {
    var frame: CGRect
    var fragments: [Candidate]
  }

  private static func droppingContainers(of candidates: [Candidate]) -> [Candidate] {
    var kept: [Candidate] = []
    for candidate in candidates.sorted(by: byArea) {
      let area = candidate.rect.width * candidate.rect.height
      let inside = kept.filter { covers(candidate.rect, $0.rect) }
      let covered = inside.reduce(CGFloat.zero) { $0 + $1.rect.width * $1.rect.height }
      let largest = inside.reduce(CGFloat.zero) { max($0, $1.rect.width * $1.rect.height) }
      let duplicate = covered >= 0.9 * area
      let container = covered >= 0.6 * area && largest < 0.5 * area
      if duplicate || container { continue }
      kept.append(candidate)
    }
    return kept
  }

  private static func rows(of candidates: [Candidate]) -> [Line] {
    var result: [Line] = []
    for candidate in candidates.sorted(by: topToBottom) {
      if let index = result.indices.last, sharesRow(result[index].frame, candidate.rect) {
        result[index].frame = result[index].frame.union(candidate.rect)
        result[index].fragments.append(candidate)
      } else {
        result.append(Line(frame: candidate.rect, fragments: [candidate]))
      }
    }
    return result
  }

  private static func fragments(of row: Line) -> [String] {
    var lines: [String] = []
    var buffer: [Candidate] = []
    var reach: CGFloat = 0
    for fragment in row.fragments.sorted(by: leftToRight) {
      if let last = buffer.last, fragment.rect.minX < last.rect.maxX {
        if fragment.text.count > last.text.count {
          buffer[buffer.count - 1] = fragment
          reach = max(reach, fragment.rect.maxX)
        }
        continue
      }
      let gapLimit = max(row.frame.height, fragment.rect.height)
      if !buffer.isEmpty, fragment.rect.minX - reach > gapLimit {
        lines.append(buffer.map(\.text).joined(separator: " "))
        buffer = []
        reach = 0
      }
      buffer.append(fragment)
      reach = max(reach, fragment.rect.maxX)
    }
    if !buffer.isEmpty {
      lines.append(buffer.map(\.text).joined(separator: " "))
    }
    return lines
  }

  private static func sharesRow(_ row: CGRect, _ rect: CGRect) -> Bool {
    let overlap = min(row.maxY, rect.maxY) - max(row.minY, rect.minY)
    let shorter = min(row.height, rect.height)
    let taller = max(row.height, rect.height)
    if overlap >= 0.45 * shorter { return true }
    return abs(row.midY - rect.midY) <= 0.5 * taller
  }

  private static func covers(_ outer: CGRect, _ inner: CGRect) -> Bool {
    let slack = 0.15 * min(outer.height, inner.height)
    return outer.insetBy(dx: -slack, dy: -slack).contains(inner)
  }

  private static func byArea(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
    let left = lhs.rect.width * lhs.rect.height
    let right = rhs.rect.width * rhs.rect.height
    return left == right ? topToBottom(lhs, rhs) : left < right
  }

  private static func topToBottom(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
    if lhs.rect.midY != rhs.rect.midY { return lhs.rect.midY > rhs.rect.midY }
    if lhs.rect.minX != rhs.rect.minX { return lhs.rect.minX < rhs.rect.minX }
    return lhs.text < rhs.text
  }

  private static func leftToRight(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
    if lhs.rect.minX != rhs.rect.minX { return lhs.rect.minX < rhs.rect.minX }
    return topToBottom(lhs, rhs)
  }
}
