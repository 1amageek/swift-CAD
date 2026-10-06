import CADCore
import CADGeometry

/// The original coedge lift in the unchanged directed model-edge chart.
struct ExchangeHostedCurveConversionSource: GeometryCurveConversionSource {
    let original: NativeCurveConversionSource
    let start: Double
    let end: Double
    let reversed: Bool
    let originalStart: ExactRationalCoefficient
    let originalSpan: ExactRationalCoefficient
    let derivativeGain: OutwardScalarInterval
    let originalAdmission: GeometryConversionAdmission

    init(surface: Surface3D, parameterCurve: SurfaceParameterCurve, start: Double, end: Double,
        reversed: Bool, tolerance: ModelingTolerance, admission: GeometryConversionAdmission) throws {
        guard start.isFinite, end.isFinite, start != end else {
            throw GeometryConversionError.invalidInput("Hosted chart requires distinct finite original edge labels.")
        }
        var usage = ExchangeConversionRationalUsage(admission: admission)
        originalStart = try .originalDouble(start, usage: &usage)
        originalSpan = try ExactRationalCoefficient.originalDouble(end, usage: &usage)
            .subtracting(originalStart, usage: &usage)
        let numerator = try ExactRationalCoefficient.originalDouble(reversed ? -1 : 1, usage: &usage)
        derivativeGain = try numerator.divided(by: originalSpan, usage: &usage).outwardInterval(usage: &usage)
        self.start = start; self.end = end; self.reversed = reversed; originalAdmission = admission
        original = try NativeCurveConversionSource(.surfaceLift(SurfaceLiftCurve3D(surface: surface,
            parameterCurve: parameterCurve)), tolerance: tolerance, admission: admission)
    }

    func validate(over parameters: ScalarInterval, tolerance: ModelingTolerance) throws {
        try validate(over: parameters, tolerance: tolerance, admission: originalAdmission)
    }
    func validate(over parameters: ScalarInterval, tolerance: ModelingTolerance,
        admission: GeometryConversionAdmission) throws {
        let chart = try normalized(parameters, admission: admission)
        try original.validate(over: chart, tolerance: tolerance, admission: admission)
    }
    func pointAndDerivative(at parameter: Double, tolerance: ModelingTolerance) throws -> (point: Point3D, derivative: Vector3D) {
        // Numeric proposals are representatives of the retained bounded source, never acceptance witnesses.
        let value = try enclosure(over: ScalarInterval(lower: parameter, upper: parameter),
            tolerance: tolerance, admission: originalAdmission)
        return (Point3D(x: value.position.x.midpoint, y: value.position.y.midpoint, z: value.position.z.midpoint),
            Vector3D(x: value.firstDerivative.x.midpoint, y: value.firstDerivative.y.midpoint, z: value.firstDerivative.z.midpoint))
    }
    func enclosure(over parameters: ScalarInterval, tolerance: ModelingTolerance) throws -> CurveDifferentialEnclosure {
        try enclosure(over: parameters, tolerance: tolerance, admission: originalAdmission)
    }
    func enclosure(over parameters: ScalarInterval, tolerance: ModelingTolerance,
        admission: GeometryConversionAdmission) throws -> CurveDifferentialEnclosure {
        let chart = try normalized(parameters, admission: admission)
        let value = try original.enclosure(over: chart, tolerance: tolerance, admission: admission)
        try admission.chargeWork(6)
        return .init(position: value.position,
            firstDerivative: try multiply(value.firstDerivative, by: derivativeGain),
            secondDerivative: try multiply(value.secondDerivative, by: derivativeGain * derivativeGain))
    }
    private func normalized(_ parameters: ScalarInterval, admission: GeometryConversionAdmission) throws -> ScalarInterval {
        guard parameters.lower >= min(start, end), parameters.upper <= max(start, end) else {
            throw GeometryConversionError.invalidInput("Hosted query is outside its original directed edge selection.")
        }
        var usage = ExchangeConversionRationalUsage(admission: admission)
        func fraction(_ parameter: Double, usage: inout ExchangeConversionRationalUsage) throws -> ExactRationalCoefficient {
            var q = try ExactRationalCoefficient.originalDouble(parameter, usage: &usage)
                .subtracting(originalStart, usage: &usage).divided(by: originalSpan, usage: &usage)
            if reversed { q = try ExactRationalCoefficient.one.subtracting(q, usage: &usage) }
            guard q.canonicalSign >= 0,
                try q.subtracting(.one, usage: &usage).canonicalSign <= 0 else {
                throw GeometryConversionError.invalidInput("Original hosted station is outside its normalized source chart.")
            }
            return q
        }
        let a = try fraction(parameters.lower, usage: &usage), b = try fraction(parameters.upper, usage: &usage)
        let ascending = try b.subtracting(a, usage: &usage).canonicalSign >= 0
        let lower = try (ascending ? a : b).outwardInterval(usage: &usage)
        let upper = try (ascending ? b : a).outwardInterval(usage: &usage)
        // Exact rational membership above proves that outward overshoot is rounding only.
        return try .init(lower: max(0, lower.lower), upper: min(1, upper.upper))
    }
    private func multiply(_ value: CoordinateEnclosure3D, by scale: OutwardScalarInterval) throws -> CoordinateEnclosure3D {
        func component(_ interval: ScalarInterval) throws -> ScalarInterval {
            let result = OutwardScalarInterval(lower: interval.lower, upper: interval.upper) * scale
            return try .init(lower: result.lower, upper: result.upper)
        }
        return try .init(x: component(value.x), y: component(value.y), z: component(value.z))
    }
}
