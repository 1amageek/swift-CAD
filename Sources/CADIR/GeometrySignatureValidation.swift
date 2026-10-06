import CADCore

package enum GeometrySignatureValidation {
    package static let tolerance = ModelingTolerance(
        distance: Double.leastNonzeroMagnitude,
        angle: Double.leastNonzeroMagnitude,
        relative: Double.leastNonzeroMagnitude
    )
}
