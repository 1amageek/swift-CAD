import CADCore

enum GeometrySignatureValidation {
    static let tolerance = ModelingTolerance(
        distance: Double.leastNonzeroMagnitude,
        angle: Double.leastNonzeroMagnitude,
        relative: Double.leastNonzeroMagnitude
    )
}
