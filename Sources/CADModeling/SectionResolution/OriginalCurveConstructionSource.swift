import CADCore
import CADGeometry

/// Original curve composed with its retained construction chart, for certification.
package struct OriginalCurveConstructionSource: GeometryCurveConversionSource {
    private let chart: OriginalCurveSpanParameterChart
    private let domain: ScalarInterval
    private let original: PreparedCurveDifferentialEncloser
    private let admission: GeometryConversionAdmission
    private let tolerance: ModelingTolerance

    package init(chart: OriginalCurveSpanParameterChart, domain: ScalarInterval,
        tolerance: ModelingTolerance, admission: GeometryConversionAdmission) throws {
        self.chart = chart; self.domain = domain
        self.tolerance = tolerance; self.admission = admission
        if let prepared = chart.source.prepared, chart.source.preparationTolerance == tolerance {
            original = prepared
        } else {
            original = try PreparedCurveDifferentialEncloser(curve: chart.curve,
                tolerance: tolerance, remainingSourceDepth: admission.remainingSourceDepth,
                maximumSubdivisionDepth: admission.maximumSubdivisionDepth,
                consumeWork: { try admission.chargeWork() },
                consumeStorage: { try admission.chargeStorage(bytes: $0) },
                maximumAlgebraicDepth: admission.maximumAlgebraicDepth)
        }
    }

    package func validate(over parameters: ScalarInterval, tolerance: ModelingTolerance) throws {
        try admission.chargeWork()
        guard tolerance == self.tolerance, domain.width > 0,
              parameters.lower >= domain.lower, parameters.upper <= domain.upper else {
            throw GeometryConversionError.invalidInput("Original construction certification requires its retained candidate domain and tolerance.")
        }
    }

    package func pointAndDerivative(at parameter: Double, tolerance: ModelingTolerance) throws -> (point: Point3D, derivative: Vector3D) {
        try validate(over: ScalarInterval(lower: parameter, upper: parameter), tolerance: tolerance)
        let fraction = (.exact(parameter) - OutwardScalarInterval.exact(domain.lower))
            .divided(by: .exact(domain.upper) - .exact(domain.lower))
        guard let fraction, fraction.lower == fraction.upper else {
            throw GeometryConversionError.resourceLimitExceeded("Original construction point needs an exact scalar station.")
        }
        let jet = try chart.parameterJet(overNormalizedFraction: ScalarInterval(lower: fraction.lower, upper: fraction.upper),
            throughOrder: 1, tolerance: tolerance,
            consumeWork: { try admission.chargeWork() }, consumeStorage: { try admission.chargeStorage(bytes: $0) })
        guard jet.value.lower == jet.value.upper,
              let gain = jet.derivatives[1].divided(by: .exact(domain.upper) - .exact(domain.lower)),
              gain.lower == gain.upper else {
            throw GeometryConversionError.resourceLimitExceeded("Original construction point has no exact native scalar chart value.")
        }
        let source = try chart.curve.differentialGeometry(at: jet.value.lower, tolerance: tolerance)
        return (source.position, source.firstDerivative * gain.lower)
    }

    package func validate(over parameters: ScalarInterval, tolerance: ModelingTolerance,
        admission: GeometryConversionAdmission) throws {
        try admission.chargeWork()
        try validate(over: parameters, tolerance: tolerance)
    }

    package func enclosure(over parameters: ScalarInterval, tolerance: ModelingTolerance) throws -> CurveDifferentialEnclosure {
        try enclosure(over: parameters, tolerance: tolerance, admission: admission)
    }

    package func enclosure(over parameters: ScalarInterval, tolerance: ModelingTolerance,
        admission: GeometryConversionAdmission) throws -> CurveDifferentialEnclosure {
        try validate(over: parameters, tolerance: tolerance)
        let native: ScalarInterval
        let gain: OutwardScalarInterval
        let secondGain: OutwardScalarInterval
        if chart.isNativeIdentity(in: domain) {
            native = parameters; gain = .exact(1); secondGain = .exact(0)
        } else {
        let width = OutwardScalarInterval.exact(domain.upper) - .exact(domain.lower)
        guard let fraction = (OutwardScalarInterval(lower: parameters.lower, upper: parameters.upper)
            - .exact(domain.lower)).divided(by: width),
              let clipped = fraction.intersection(with: .init(lower: 0, upper: 1)) else {
            throw GeometryConversionError.invalidInput("Original construction interval lost its fraction chart.")
        }
        let label = try chart.parameterJet(overNormalizedFraction: ScalarInterval(lower: clipped.lower, upper: clipped.upper),
            throughOrder: 2, tolerance: tolerance,
            consumeWork: { try admission.chargeWork() }, consumeStorage: { try admission.chargeStorage(bytes: $0) })
        guard let first = label.derivatives[1].divided(by: width),
              let second = label.derivatives[2].divided(by: width * width) else {
            throw GeometryConversionError.resourceLimitExceeded("Original construction derivative gain is unresolved.")
        }
        native = try ScalarInterval(lower: max(min(chart.startParameter, chart.endParameter), label.value.lower),
            upper: min(max(chart.startParameter, chart.endParameter), label.value.upper))
        gain = first; secondGain = second
        }
        let receipt = try original.closedNativeJets(over: native, tolerance: tolerance,
            maximumSpanCount: admission.maximumSpanCount, maximumSubdivisionDepth: admission.maximumSubdivisionDepth,
            remainingSourceDepth: admission.remainingSourceDepth,
            consumeWork: { try admission.chargeWork() }, consumeStorage: { try admission.chargeStorage(bytes: $0) })
        var px: OutwardScalarInterval?, py: OutwardScalarInterval?, pz: OutwardScalarInterval?
        var dx: OutwardScalarInterval?, dy: OutwardScalarInterval?, dz: OutwardScalarInterval?
        var ax: OutwardScalarInterval?, ay: OutwardScalarInterval?, az: OutwardScalarInterval?
        func merge(_ current: inout OutwardScalarInterval?, _ value: OutwardScalarInterval) {
            current = current.map { .init(lower: min($0.lower, value.lower), upper: max($0.upper, value.upper)) } ?? value
        }
        for span in receipt.spans {
            try admission.chargeWork()
            let jet = span.jet
            merge(&px, jet.x.value); merge(&py, jet.y.value); merge(&pz, jet.z.value)
            merge(&dx, jet.x.derivativeU * gain); merge(&dy, jet.y.derivativeU * gain); merge(&dz, jet.z.derivativeU * gain)
            merge(&ax, jet.x.secondDerivativeUU * gain * gain + jet.x.derivativeU * secondGain)
            merge(&ay, jet.y.secondDerivativeUU * gain * gain + jet.y.derivativeU * secondGain)
            merge(&az, jet.z.secondDerivativeUU * gain * gain + jet.z.derivativeU * secondGain)
        }
        func coordinates(_ x: OutwardScalarInterval?, _ y: OutwardScalarInterval?, _ z: OutwardScalarInterval?) throws -> CoordinateEnclosure3D {
            guard let x, let y, let z, x.isFinite, y.isFinite, z.isFinite else {
                throw GeometryConversionError.resourceLimitExceeded("Original construction lacks a complete finite derivative cover.")
            }
            return try CoordinateEnclosure3D(x: ScalarInterval(lower: x.lower, upper: x.upper),
                y: ScalarInterval(lower: y.lower, upper: y.upper), z: ScalarInterval(lower: z.lower, upper: z.upper))
        }
        return try CurveDifferentialEnclosure(position: coordinates(px, py, pz),
            firstDerivative: coordinates(dx, dy, dz), secondDerivative: coordinates(ax, ay, az))
    }
}
