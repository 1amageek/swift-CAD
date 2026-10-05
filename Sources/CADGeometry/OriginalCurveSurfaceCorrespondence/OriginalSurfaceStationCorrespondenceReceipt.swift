import CADCore

/// A source-bound physical station enclosure; only the original resolver mints it.
package struct OriginalSurfaceStationCorrespondenceReceipt: Sendable {
    package let curve: Curve3D
    package let startParameter: Double
    package let endParameter: Double
    package let surface: Surface3D
    package let parameterCurve: SurfaceParameterCurve
    package let stationParameter: Double
    package let fractions: ScalarInterval
    package let maximumDeviation: Double
    /// Sign of normalized pcurve advance relative to directed original edge advance.
    package let orientation: Int
    package let tolerance: ModelingTolerance

    package var normalizedFraction: Double { fractions.midpoint }

    init(curve: Curve3D, startParameter: Double, endParameter: Double,
        surface: Surface3D, parameterCurve: SurfaceParameterCurve,
        stationParameter: Double, fractions: ScalarInterval, maximumDeviation: Double,
        orientation: Int, tolerance: ModelingTolerance) {
        self.curve = curve
        self.startParameter = startParameter
        self.endParameter = endParameter
        self.surface = surface
        self.parameterCurve = parameterCurve
        self.stationParameter = stationParameter
        self.fractions = fractions
        self.maximumDeviation = maximumDeviation
        self.orientation = orientation
        self.tolerance = tolerance
    }
}
