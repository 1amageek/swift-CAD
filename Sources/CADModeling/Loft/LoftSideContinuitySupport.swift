import CADGeometry

/// Original support targets retained until the final generated side is admitted.
package struct LoftSideContinuitySupport: Sendable {
    package let start: [ExactEdgeContinuitySupport]?
    package let end: [ExactEdgeContinuitySupport]?
}
