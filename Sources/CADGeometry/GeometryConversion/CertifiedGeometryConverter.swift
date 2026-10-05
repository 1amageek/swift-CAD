import CADCore

public struct CertifiedGeometryConverter: GeometryConverting {
    public init() {}

    public func approximateCurve(source: any GeometryCurveConversionSource, over parameters: ScalarInterval,
        requirements: GeometryConversionRequirements, tolerance: ModelingTolerance) throws -> GeometryCurveConversionResult {
        try admit(source: source, parameters: parameters, requirements: requirements, tolerance: tolerance)
        var budget = GeometryConversionBudget(requirements)
        var spans = 1
        for _ in 0..<requirements.maximumCandidateCount {
            try Task.checkCancellation()
            let degree = min(3, requirements.maximumDegree)
            try chargeCurve(count: curveCount(degree: degree, spans: spans), requirements: requirements, budget: &budget)
            var breaks: [Double] = []
            for i in 0...spans {
                breaks.append(i == spans ? parameters.upper : parameters.lower + parameters.width * Double(i) / Double(spans))
            }
            let curve = try curveCandidate(source: source, breaks: breaks, degree: degree, tolerance: tolerance)
            do {
                let guarantee = try certify(source: source, candidate: curve, parameters: parameters,
                    requirements: requirements, tolerance: tolerance, budget: &budget)
                return GeometryCurveConversionResult(curve: curve, parameters: parameters, guarantee: guarantee)
            } catch GeometryConversionAdmissionRejection.candidate { }
            spans = try GeometryConversionBudget.product(spans, 2)
        }
        throw GeometryConversionError.toleranceRejected
    }

    public func interpolateCurve(source: any GeometryCurveConversionSource, at parameters: [Double],
        requirements: GeometryConversionRequirements, tolerance: ModelingTolerance) throws -> GeometryCurveConversionResult {
        guard parameters.count >= 2, let lower = parameters.first, let upper = parameters.last else {
            throw GeometryConversionError.invalidInput("Curve interpolation requires at least two increasing parameters.")
        }
        for i in parameters.indices {
            try Task.checkCancellation()
            guard parameters[i].isFinite, i == 0 || parameters[i] > parameters[i - 1] else {
                throw GeometryConversionError.invalidInput("Interpolation parameters must be finite and strictly increasing.")
            }
        }
        let interval = try ScalarInterval(lower: lower, upper: upper)
        try admit(source: source, parameters: interval, requirements: requirements, tolerance: tolerance)
        var budget = GeometryConversionBudget(requirements)
        let degree = min(3, requirements.maximumDegree)
        try chargeCurve(count: curveCount(degree: degree, spans: parameters.count - 1), requirements: requirements, budget: &budget)
        let curve = try curveCandidate(source: source, breaks: parameters, degree: degree, tolerance: tolerance)
        let guarantee = try publishedGuarantee {
            try certify(source: source, candidate: curve, parameters: interval,
                requirements: requirements, tolerance: tolerance, budget: &budget)
        }
        return GeometryCurveConversionResult(curve: curve, parameters: interval, guarantee: guarantee)
    }

    public func approximateSurface(source: any GeometrySurfaceConversionSource, over parameters: SurfaceParameterBox,
        requirements: GeometryConversionRequirements, tolerance: ModelingTolerance) throws -> GeometrySurfaceConversionResult {
        try admit(source: source, parameters: parameters, requirements: requirements, tolerance: tolerance)
        var budget = GeometryConversionBudget(requirements)
        var spans = 1
        let degree = min(3, requirements.maximumDegree)
        for _ in 0..<requirements.maximumCandidateCount {
            try Task.checkCancellation()
            let sum = spans.addingReportingOverflow(degree)
            guard !sum.overflow else { throw GeometryConversionError.resourceLimitExceeded("Surface dimension overflowed.") }
            try chargeSurface(u: sum.partialValue, v: sum.partialValue, requirements: requirements, budget: &budget)
            let candidate = try MappedBSplineSurfaceFitter.fit(
                layout: .init(uDegree: degree, vDegree: degree, uSpans: spans, vSpans: spans),
                u: parameters.u, v: parameters.v, tolerance: tolerance
            ) { u, v in
                try Task.checkCancellation()
                return try source.point(u: u, v: v, tolerance: tolerance)
            }.surface
            do {
                let guarantee = try certify(source: source, candidate: candidate, parameters: parameters,
                    requirements: requirements, tolerance: tolerance, budget: &budget)
                return GeometrySurfaceConversionResult(surface: candidate, parameters: parameters, guarantee: guarantee)
            } catch GeometryConversionAdmissionRejection.candidate { }
            spans = try GeometryConversionBudget.product(spans, 2)
        }
        throw GeometryConversionError.toleranceRejected
    }

    public func interpolateSurface(source: any GeometrySurfaceConversionSource, template: BSplineSurface3D,
        points: [GeometrySurfaceInterpolationPoint], over parameters: SurfaceParameterBox,
        requirements: GeometryConversionRequirements, tolerance: ModelingTolerance) throws -> GeometrySurfaceConversionResult {
        try admit(source: source, parameters: parameters, requirements: requirements, tolerance: tolerance)
        try validate(candidate: template, parameters: parameters, requirements: requirements, tolerance: tolerance)
        guard !points.isEmpty else { throw GeometryConversionError.invalidInput("Surface interpolation requires point constraints.") }
        var budget = GeometryConversionBudget(requirements)
        try chargeSurface(u: template.uControlPointCount, v: template.vControlPointCount, requirements: requirements, budget: &budget)
        let net = try GeometryConversionBudget.product(template.uControlPointCount, template.vControlPointCount)
        try budget.charge(scalars: GeometryConversionBudget.product(net, net, 32),
            work: GeometryConversionBudget.product(net, net, net, 64))
        try budget.charge(scalars: GeometryConversionBudget.product(points.count, net, 32),
            work: GeometryConversionBudget.product(points.count, net, net, 64))
        try budget.charge(scalars: GeometryConversionBudget.product(points.count, points.count, 16))
        let constraints = try points.map { value in
            try Task.checkCancellation()
            guard value.u.isFinite, value.v.isFinite, parameters.u.contains(value.u), parameters.v.contains(value.v), value.point.isFinite else {
                throw GeometryConversionError.invalidInput("Every interpolation point must be finite and inside the certified rectangle.")
            }
            return SurfaceFittingPointInterpolator.Constraint(u: value.u, v: value.v, point: value.point)
        }
        let candidate = try SurfaceFittingPointInterpolator.interpolate(template: template, constraints: constraints,
            referenceWeight: 1, controlNetFairnessWeight: 0,
            positionTolerance: requirements.maximumPositionError, relativeRankTolerance: tolerance.relative,
            maximumElements: requirements.maximumScalarCount, tolerance: tolerance)
        let guarantee = try publishedGuarantee {
            try certify(source: source, candidate: candidate, parameters: parameters,
                requirements: requirements, tolerance: tolerance, budget: &budget)
        }
        return GeometrySurfaceConversionResult(surface: candidate, parameters: parameters, guarantee: guarantee)
    }

    public func certifyCurve(source: any GeometryCurveConversionSource, candidate: BSplineCurve3D, over parameters: ScalarInterval,
        requirements: GeometryConversionRequirements, tolerance: ModelingTolerance) throws -> GeometryConversionGuarantee {
        try admit(source: source, parameters: parameters, requirements: requirements, tolerance: tolerance)
        var budget = GeometryConversionBudget(requirements)
        try chargeCurve(count: candidate.controlPointCount, requirements: requirements, budget: &budget)
        return try publishedGuarantee {
            try certify(source: source, candidate: candidate, parameters: parameters,
                requirements: requirements, tolerance: tolerance, budget: &budget)
        }
    }

    public func certifySurface(source: any GeometrySurfaceConversionSource, candidate: BSplineSurface3D, over parameters: SurfaceParameterBox,
        requirements: GeometryConversionRequirements, tolerance: ModelingTolerance) throws -> GeometryConversionGuarantee {
        try admit(source: source, parameters: parameters, requirements: requirements, tolerance: tolerance)
        var budget = GeometryConversionBudget(requirements)
        try chargeSurface(u: candidate.uControlPointCount, v: candidate.vControlPointCount, requirements: requirements, budget: &budget)
        return try publishedGuarantee {
            try certify(source: source, candidate: candidate, parameters: parameters,
                requirements: requirements, tolerance: tolerance, budget: &budget)
        }
    }

    private func publishedGuarantee(_ body: () throws -> GeometryConversionGuarantee) throws -> GeometryConversionGuarantee {
        do { return try body() }
        catch GeometryConversionAdmissionRejection.candidate { throw GeometryConversionError.toleranceRejected }
    }

    private func admit(source: any GeometryCurveConversionSource, parameters: ScalarInterval,
        requirements: GeometryConversionRequirements, tolerance: ModelingTolerance) throws {
        try Task.checkCancellation(); try requirements.validate(); try tolerance.validate()
        try source.validate(over: parameters, tolerance: tolerance)
    }
    private func admit(source: any GeometrySurfaceConversionSource, parameters: SurfaceParameterBox,
        requirements: GeometryConversionRequirements, tolerance: ModelingTolerance) throws {
        try Task.checkCancellation(); try requirements.validate(); try tolerance.validate()
        try source.validate(over: parameters, tolerance: tolerance)
    }
    private func certify(source: any GeometryCurveConversionSource, candidate: BSplineCurve3D, parameters: ScalarInterval,
        requirements: GeometryConversionRequirements, tolerance: ModelingTolerance,
        budget: inout GeometryConversionBudget) throws -> GeometryConversionGuarantee {
        guard candidate.degree <= requirements.maximumDegree, candidate.controlPointCount <= requirements.maximumControlPointCount else {
            throw GeometryConversionError.resourceLimitExceeded("The curve exceeds the requested degree or control-point count.")
        }
        let polynomial = PolynomialCurveConversionTarget.accepts(candidate)
        let targetCost = polynomial ? GeometryConversionTargetCost.polynomialCurve(candidate) : .curve(candidate)
        try targetCost.chargePreparation(budget: &budget)
        let target: any GeometryCurveConversionSource = polynomial
            ? try PolynomialCurveConversionTarget(candidate, tolerance: tolerance)
            : try NativeCurveConversionSource(.bSpline(candidate), tolerance: tolerance)
        try target.validate(over: parameters, tolerance: tolerance)
        return try GeometryConversionCertification().curve(source: source, target: target, parameters: parameters,
            requirements: requirements, tolerance: tolerance, targetCost: targetCost, budget: &budget)
    }
    private func certify(source: any GeometrySurfaceConversionSource, candidate: BSplineSurface3D, parameters: SurfaceParameterBox,
        requirements: GeometryConversionRequirements, tolerance: ModelingTolerance,
        budget: inout GeometryConversionBudget) throws -> GeometryConversionGuarantee {
        let polynomial = PolynomialSurfaceConversionTarget.accepts(candidate)
        let targetCost = polynomial ? GeometryConversionTargetCost.polynomialSurface(candidate) : .surface(candidate)
        try targetCost.chargePreparation(budget: &budget)
        try validate(candidate: candidate, parameters: parameters, requirements: requirements, tolerance: tolerance)
        let target: any GeometrySurfaceConversionSource = polynomial
            ? try PolynomialSurfaceConversionTarget(candidate, tolerance: tolerance)
            : try NativeSurfaceConversionSource(.bSpline(candidate), tolerance: tolerance)
        return try GeometryConversionCertification().surface(source: source, target: target, parameters: parameters,
            requirements: requirements, tolerance: tolerance, targetCost: targetCost, budget: &budget)
    }
    private func validate(candidate: BSplineSurface3D, parameters: SurfaceParameterBox,
        requirements: GeometryConversionRequirements, tolerance: ModelingTolerance) throws {
        let count = try GeometryConversionBudget.product(candidate.uControlPointCount, candidate.vControlPointCount)
        guard max(candidate.uDegree, candidate.vDegree) <= requirements.maximumDegree, count <= requirements.maximumControlPointCount else {
            throw GeometryConversionError.resourceLimitExceeded("The surface exceeds the requested degree or control-point count.")
        }
        try parameters.validate(for: .bSpline(candidate), tolerance: tolerance)
    }
    private func curveCount(degree: Int, spans: Int) throws -> Int {
        let product = try GeometryConversionBudget.product(degree, spans)
        let result = product.addingReportingOverflow(1)
        guard !result.overflow else { throw GeometryConversionError.resourceLimitExceeded("Curve dimension overflowed.") }
        return result.partialValue
    }
    private func chargeCurve(count: Int, requirements: GeometryConversionRequirements, budget: inout GeometryConversionBudget) throws {
        guard count <= requirements.maximumControlPointCount else { throw GeometryConversionError.resourceLimitExceeded("Curve control-point budget exhausted.") }
        try budget.charge(scalars: GeometryConversionBudget.product(count, 16), work: GeometryConversionBudget.product(count, count, 32))
    }
    private func chargeSurface(u: Int, v: Int, requirements: GeometryConversionRequirements, budget: inout GeometryConversionBudget) throws {
        let count = try GeometryConversionBudget.product(u, v)
        guard count <= requirements.maximumControlPointCount else { throw GeometryConversionError.resourceLimitExceeded("Surface control-point budget exhausted.") }
        let squareU = try GeometryConversionBudget.product(u, u), squareV = try GeometryConversionBudget.product(v, v)
        let matrix = squareU.addingReportingOverflow(squareV)
        guard !matrix.overflow else { throw GeometryConversionError.resourceLimitExceeded("Surface matrix dimension overflowed.") }
        let storage = try GeometryConversionBudget.product(count, 96)
        let extra = try GeometryConversionBudget.product(matrix.partialValue, 12)
        let total = storage.addingReportingOverflow(extra)
        guard !total.overflow else { throw GeometryConversionError.resourceLimitExceeded("Surface storage dimension overflowed.") }
        try budget.charge(scalars: total.partialValue, work: GeometryConversionBudget.product(count, count, 32))
        try budget.charge(work: GeometryConversionBudget.product(u, u, u, 32))
        try budget.charge(work: GeometryConversionBudget.product(v, v, v, 32))
    }

    private func curveCandidate(source: any GeometryCurveConversionSource, breaks: [Double], degree: Int,
                                tolerance: ModelingTolerance) throws -> BSplineCurve3D {
        var controls: [Point3D] = []
        var knots = Array(repeating: breaks[0], count: degree + 1)
        var start = try source.pointAndDerivative(at: breaks[0], tolerance: tolerance)
        try start.point.validate(); try start.derivative.validate()
        controls.append(start.point)
        for i in 0..<(breaks.count - 1) {
            try Task.checkCancellation()
            let a = breaks[i], b = breaks[i + 1]
            guard b > a else { throw GeometryConversionError.invalidInput("Candidate breaks must be strictly increasing.") }
            let end = try source.pointAndDerivative(at: b, tolerance: tolerance)
            try end.point.validate(); try end.derivative.validate()
            if degree == 3 {
                let factor = (b - a) / 3
                controls.append(start.point + start.derivative * factor)
                controls.append(end.point + end.derivative * (-factor))
            } else if degree == 2 {
                let mid = try source.pointAndDerivative(at: a + (b - a) * 0.5, tolerance: tolerance).point
                try mid.validate()
                controls.append(mid + (mid - start.point) * 0.5 + (mid - end.point) * 0.5)
            }
            controls.append(end.point)
            if i + 1 < breaks.count - 1 { knots.append(contentsOf: repeatElement(b, count: degree)) }
            start = end
        }
        knots.append(contentsOf: repeatElement(breaks[breaks.count - 1], count: degree + 1))
        let result = BSplineCurve3D(degree: degree, knots: knots, controlPoints: controls)
        try result.validate(tolerance: tolerance)
        return result
    }
}
