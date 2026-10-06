import CADCore

/// A directed original edge station certified for an authored lifted fraction.
package struct OriginalSurfaceStationInverseReceipt: Sendable {
    package let curve: Curve3D
    package let startParameter: Double
    package let endParameter: Double
    package let surface: Surface3D
    package let parameterCurve: SurfaceParameterCurve
    package let liftFraction: Double
    package let nativeParameters: ScalarInterval
    package let maximumDeviation: Double
    package let orientation: Int
    package let tolerance: ModelingTolerance

    /// Numerical representative only; the receipt retains the entire interval.
    package var nativeParameter: Double { nativeParameters.midpoint }

    init(curve: Curve3D, startParameter: Double, endParameter: Double,
        surface: Surface3D, parameterCurve: SurfaceParameterCurve, liftFraction: Double,
        nativeParameters: ScalarInterval, maximumDeviation: Double,
        orientation: Int, tolerance: ModelingTolerance) {
        self.curve = curve
        self.startParameter = startParameter
        self.endParameter = endParameter
        self.surface = surface
        self.parameterCurve = parameterCurve
        self.liftFraction = liftFraction
        self.nativeParameters = nativeParameters
        self.maximumDeviation = maximumDeviation
        self.orientation = orientation
        self.tolerance = tolerance
    }
}
