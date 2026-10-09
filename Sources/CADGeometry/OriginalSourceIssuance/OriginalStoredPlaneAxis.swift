/// Shared original N reference rule; no normalization or tolerance comparison.
enum OriginalStoredPlaneAxis {
    static func reference(x: Double,y: Double) -> Int { abs(x) <= abs(y) ? 0 : 1 }
}
