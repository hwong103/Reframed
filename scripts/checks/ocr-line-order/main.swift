import CoreGraphics
import Foundation

var failures = 0

func check(_ passed: Bool, _ label: String, _ detail: String) {
  if !passed { failures += 1 }
  print("\(passed ? "PASS" : "FAIL") \(label) -- \(detail)")
}

func candidate(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ text: String)
  -> OCRService.Candidate
{
  (rect: CGRect(x: x, y: y, width: w, height: h), text: text)
}

func expect(_ label: String, _ input: [OCRService.Candidate], _ wanted: [String]) {
  let got = OCRService.orderedLines(from: input)
  check(got == wanted, label, "got \(got) wanted \(wanted)")
}

// A block observation plus the three line observations that tile it. Vision emits this
// shape, and the fixed 0.02 comparator printed the block and the lines both.
let blockWithLines: [OCRService.Candidate] = [
  candidate(0.10, 0.50, 0.80, 0.05, "Alpha Beta Gamma"),
  candidate(0.10, 0.50, 0.28, 0.05, "Alpha"),
  candidate(0.42, 0.50, 0.24, 0.05, "Beta"),
  candidate(0.70, 0.50, 0.20, 0.05, "Gamma"),
]
expect("a block plus its lines yields each text once", blockWithLines, ["Alpha Beta Gamma"])

expect(
  "same-line fragments join into a single line",
  [
    candidate(0.10, 0.60, 0.30, 0.05, "Hello"),
    candidate(0.45, 0.60, 0.25, 0.05, "world"),
  ],
  ["Hello world"]
)

expect(
  "a two-column layout orders by row then by x",
  [
    candidate(0.10, 0.80, 0.20, 0.05, "R1C1"),
    candidate(0.60, 0.80, 0.20, 0.05, "R1C2"),
    candidate(0.10, 0.60, 0.20, 0.05, "R2C1"),
    candidate(0.60, 0.60, 0.20, 0.05, "R2C2"),
  ],
  ["R1C1", "R1C2", "R2C1", "R2C2"]
)

// Tightly spaced distinct lines straddle the old fixed 0.02 midY band. The old
// comparator was not transitive, so sorted(by:) could return any order at all.
let straddle: [OCRService.Candidate] = [
  candidate(0.10, 0.500, 0.60, 0.020, "row-ish A"),
  candidate(0.10, 0.485, 0.60, 0.020, "row-ish B"),
  candidate(0.10, 0.470, 0.60, 0.020, "row-ish C"),
  candidate(0.10, 0.455, 0.60, 0.020, "row-ish D"),
]
check(
  OCRService.orderedLines(from: straddle) == ["row-ish A", "row-ish B", "row-ish C", "row-ish D"],
  "straddling rows stay four ordered lines",
  "\(OCRService.orderedLines(from: straddle))"
)

// The same words returned twice with slightly different boxes are one line, not two. A
// wider row band joined them into a space-separated duplicate instead.
let repeated: [OCRService.Candidate] = [
  candidate(0.10, 0.600, 0.60, 0.020, "Total $18,404.22"),
  candidate(0.10, 0.594, 0.60, 0.020, "Total $18,404.22"),
]
check(
  OCRService.orderedLines(from: repeated) == ["Total $18,404.22"],
  "the same line observed twice yields one line",
  "\(OCRService.orderedLines(from: repeated))"
)

// A containment rule that is too eager silently deletes a real line. Wider readings win.
let overlapping: [OCRService.Candidate] = [
  candidate(0.10, 0.320, 0.30, 0.030, "Balance"),
  candidate(0.10, 0.320, 0.60, 0.030, "Balance due 18,404.22"),
]
check(
  OCRService.orderedLines(from: overlapping) == ["Balance due 18,404.22"],
  "overlapping readings keep the longer text",
  "\(OCRService.orderedLines(from: overlapping))"
)

check(
  OCRService.orderedLines(from: [
    candidate(0.10, 0.700, 0.50, 0.030, "duplicated"),
    candidate(0.10, 0.700, 0.50, 0.030, "duplicated"),
  ]) == ["duplicated"],
  "an identical repeated observation collapses",
  "\(OCRService.orderedLines(from: [candidate(0.10, 0.700, 0.50, 0.030, "duplicated"), candidate(0.10, 0.700, 0.50, 0.030, "duplicated")]))"
)

var permutationsAgree = true
var reference: [String]?
for rotation in 0..<straddle.count {
  let rotated = Array(straddle[rotation...] + straddle[..<rotation])
  let result = OCRService.orderedLines(from: rotated)
  if let reference {
    if result != reference { permutationsAgree = false }
  } else {
    reference = result
  }
}
check(
  permutationsAgree,
  "input order does not change the result",
  "reference \(reference ?? [])"
)

let repeats = (0..<50).map { _ in OCRService.orderedLines(from: blockWithLines) }
check(
  Set(repeats.map { $0.joined(separator: "\u{1f}") }).count == 1,
  "repeated runs are byte-stable",
  "\(Set(repeats.map { $0.joined(separator: "\u{1f}") }).count) distinct result(s)"
)

let many: [OCRService.Candidate] = (0..<30).map { index in
  candidate(0.05, 0.95 - CGFloat(index) * 0.03, 0.30, 0.02, "line \(index)")
}
let manyResult = OCRService.orderedLines(from: many)
check(
  manyResult == (0..<30).map { "line \($0)" },
  "thirty stacked lines survive in order",
  "\(manyResult.count) line(s)"
)

print(failures == 0 ? "ALL CHECKS PASS" : "\(failures) CHECK(S) FAILED")
exit(failures == 0 ? 0 : 1)
