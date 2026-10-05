import CADCore
import CADGeometry

/// Original directed section law composed with a closed interval endpoint action.
package struct ClosedSweepSectionSource: GeometryCurveConversionSource {
    private let original: OriginalCurveConstructionSource
    private let action: ClosedSweepIntervalFrameAction
    private let admission: GeometryConversionAdmission

    package init(chart: OriginalCurveSpanParameterChart, domain: ScalarInterval,
        action: ClosedSweepIntervalFrameAction, tolerance: ModelingTolerance,
        admission: GeometryConversionAdmission) throws {
        original = try OriginalCurveConstructionSource(chart: chart, domain: domain,
            tolerance: tolerance, admission: admission)
        self.action = action; self.admission = admission
    }

    package func validate(over parameters: ScalarInterval, tolerance: ModelingTolerance) throws {
        try original.validate(over: parameters, tolerance: tolerance, admission: admission)
    }
    package func validate(over parameters: ScalarInterval, tolerance: ModelingTolerance,
        admission: GeometryConversionAdmission) throws {
        try original.validate(over: parameters, tolerance: tolerance, admission: admission)
    }
    package func enclosure(over parameters: ScalarInterval, tolerance: ModelingTolerance) throws -> CurveDifferentialEnclosure {
        try enclosure(over: parameters, tolerance: tolerance, admission: admission)
    }
    package func enclosure(over parameters: ScalarInterval, tolerance: ModelingTolerance,
        admission: GeometryConversionAdmission) throws -> CurveDifferentialEnclosure {
        let raw = try original.enclosure(over: parameters, tolerance: tolerance, admission: admission)
        return CurveDifferentialEnclosure(
            position: try action.apply(raw.position, isPosition: true, admission: admission),
            firstDerivative: try action.apply(raw.firstDerivative, isPosition: false, admission: admission),
            secondDerivative: try action.apply(raw.secondDerivative, isPosition: false, admission: admission))
    }
    package func pointAndDerivative(at parameter: Double, tolerance: ModelingTolerance) throws -> (point: Point3D, derivative: Vector3D) {
        let raw = try enclosure(over: ScalarInterval(lower: parameter, upper: parameter), tolerance: tolerance)
        guard raw.position.x.width == 0, raw.position.y.width == 0, raw.position.z.width == 0,
              raw.firstDerivative.x.width == 0, raw.firstDerivative.y.width == 0, raw.firstDerivative.z.width == 0 else {
            throw GeometryConversionError.resourceLimitExceeded("An interval endpoint action cannot publish a rounded exact section point.")
        }
        return (Point3D(x: raw.position.x.lower, y: raw.position.y.lower, z: raw.position.z.lower),
            Vector3D(x: raw.firstDerivative.x.lower, y: raw.firstDerivative.y.lower, z: raw.firstDerivative.z.lower))
    }
}
