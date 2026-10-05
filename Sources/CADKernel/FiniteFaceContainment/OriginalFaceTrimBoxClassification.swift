/// A whole authored UV box relative to one original finite trim region.
package enum OriginalFaceTrimBoxClassification: Sendable, Equatable {
    case inside
    case outside
    /// Original trim boundary coverage meets the box; no absence is certified.
    case boundaryOverlap
}
