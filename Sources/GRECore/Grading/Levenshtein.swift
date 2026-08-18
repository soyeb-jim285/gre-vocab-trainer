import Foundation

/// Edit distance in Characters, not bytes -- "résume" differs from "resume" by
/// one edit even though it differs by two UTF-8 bytes.
///
/// Two rolling rows rather than a full matrix; the words here are short, but
/// there is no reason to allocate n*m for a value only the last row needs.
func levenshtein(_ a: String, _ b: String) -> Int {
    let a = Array(a), b = Array(b)
    if a.isEmpty { return b.count }
    if b.isEmpty { return a.count }

    var previous = Array(0...b.count)
    var current = [Int](repeating: 0, count: b.count + 1)

    for i in 1...a.count {
        current[0] = i
        for j in 1...b.count {
            let substitution = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)
            current[j] = min(previous[j] + 1, current[j - 1] + 1, substitution)
        }
        swap(&previous, &current)
    }
    return previous[b.count]
}

/// FNV-1a. Swift's `hashValue` is seeded per process, so it cannot be used for
/// anything the user should see the same way on every launch.
func stableHash(_ string: String) -> UInt64 {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in string.utf8 {
        hash ^= UInt64(byte)
        hash &*= 1_099_511_628_211
    }
    return hash
}
