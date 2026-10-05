import CADCore

public struct CertifiedGeometryConverter: CallerAdmittedGeometryConverting {
    public init() {}

    public func approximateCurve(source: any GeometryCurveConversionSource, over parameters: ScalarInterval,
        requirements: GeometryConversionRequirements, tolerance: ModelingTolerance) throws -> GeometryCurveConversionResult {
        try approximateOriginalCurve(source: source, over: parameters, requirements: requirements,
            tolerance: tolerance, admission: nil)
    }

    public func approximateCurve(source: any GeometryCurveConversionSource, over parameters: ScalarInterval,
        requirements: GeometryConversionRequirements, tolerance: ModelingTolerance,
        admission: GeometryConversionAdmission) throws -> GeometryCurveConversionResult {
        try approximateOriginalCurve(source: source, over: parameters, requirements: requirements,
            tolerance: tolerance, admission: admission)
    }

    private func approximateOriginalCurve(source: any GeometryCurveConversionSource, over parameters: ScalarInterval,
        requirements: GeometryConversionRequirements, tolerance: ModelingTolerance,
        admission: GeometryConversionAdmission?) throws -> GeometryCurveConversionResult {
        if let admission {
            try requirements.validate(); try tolerance.validate(); try admission.chargeWork()
            guard parameters.lower < parameters.upper else {
                throw GeometryConversionError.invalidInput("Curve approximation needs a positive original parameter interval.")
            }
            try source.validate(over: parameters, tolerance: tolerance, admission: admission)
        } else {
            try admit(source: source, parameters: parameters, requirements: requirements, tolerance: tolerance)
        }
        var budget = GeometryConversionBudget(requirements, admission: admission)
        var spans = 1
        for _ in 0..<requirements.maximumCandidateCount {
            try Task.checkCancellation()
            let degree = min(3, requirements.maximumDegree)
            try chargeCurve(count: curveCount(degree: degree, spans: spans), requirements: requirements, budget: &budget)
            let capacity = spans.addingReportingOverflow(1)
            guard !capacity.overflow else { throw GeometryConversionError.resourceLimitExceeded("Candidate breakpoint count overflowed.") }
            if let admission {
                try admission.chargeStorage(bytes: GeometryConversionBudget.product(capacity.partialValue, MemoryLayout<Double>.stride))
            }
            var breaks: [Double] = []
            if admission != nil { breaks.reserveCapacity(capacity.partialValue) }
            for i in 0...spans {
                try admission?.chargeWork()
                if i == 0 { breaks.append(parameters.lower) }
                else if i == spans { breaks.append(parameters.upper) }
                else {
                    let fraction = Double(i) / Double(spans)
                    let lower = parameters.lower, upper = parameters.upper
                    let value = lower.sign != upper.sign
                        ? lower * (1 - fraction) + upper * fraction
                        : lower + (upper - lower) * fraction
                    guard value.isFinite else {
                        throw GeometryConversionError.invalidInput("Candidate interpolation produced a nonfinite construction label.")
                    }
                    breaks.append(value)
                }
            }
            let curve = try curveCandidate(source: source, breaks: breaks, degree: degree, tolerance: tolerance,
                admission: admission)
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
        try interpolateOriginalCurve(source: source, at: parameters, requirements: requirements,
            tolerance: tolerance, admission: nil)
    }

    public func interpolateCurve(source: any GeometryCurveConversionSource, at parameters: [Double],
        requirements: GeometryConversionRequirements, tolerance: ModelingTolerance,
        admission: GeometryConversionAdmission) throws -> GeometryCurveConversionResult {
        try interpolateOriginalCurve(source: source, at: parameters, requirements: requirements,
            tolerance: tolerance, admission: admission)
    }

    private func interpolateOriginalCurve(source: any GeometryCurveConversionSource, at parameters: [Double],
        requirements: GeometryConversionRequirements, tolerance: ModelingTolerance,
        admission: GeometryConversionAdmission?) throws -> GeometryCurveConversionResult {
        guard parameters.count >= 2, let lower = parameters.first, let upper = parameters.last else {
            throw GeometryConversionError.invalidInput("Curve interpolation requires at least two increasing parameters.")
        }
        for i in parameters.indices {
            try Task.checkCancellation(); try admission?.chargeWork()
            guard parameters[i].isFinite, i == 0 || parameters[i] > parameters[i - 1] else {
                throw GeometryConversionError.invalidInput("Interpolation parameters must be finite and strictly increasing.")
            }
        }
        let interval = try ScalarInterval(lower: lower, upper: upper)
        if let admission {
            try requirements.validate(); try tolerance.validate(); try admission.chargeWork()
            guard interval.width.isFinite else {
                throw GeometryConversionError.invalidInput("Original interpolation span must be finite.")
            }
            try source.validate(over: interval, tolerance: tolerance, admission: admission)
        } else {
            try admit(source: source, parameters: interval, requirements: requirements, tolerance: tolerance)
        }
        var budget = GeometryConversionBudget(requirements, admission: admission)
        let degree = min(3, requirements.maximumDegree)
        try chargeCurve(count: curveCount(degree: degree, spans: parameters.count - 1), requirements: requirements, budget: &budget)
        let curve = try curveCandidate(source: source, breaks: parameters, degree: degree, tolerance: tolerance,
            admission: admission)
        let guarantee = try publishedGuarantee {
            try certify(source: source, candidate: curve, parameters: interval,
                requirements: requirements, tolerance: tolerance, budget: &budget)
        }
        return GeometryCurveConversionResult(curve: curve, parameters: interval, guarantee: guarantee)
    }

    public func approximateSurface(source: any GeometrySurfaceConversionSource, over parameters: SurfaceParameterBox,
        requirements: GeometryConversionRequirements, tolerance: ModelingTolerance) throws -> GeometrySurfaceConversionResult {
        try approximateOriginalSurface(source: source, over: parameters, requirements: requirements,
            tolerance: tolerance, admission: nil)
    }

    public func approximateSurface(source: any GeometrySurfaceConversionSource, over parameters: SurfaceParameterBox,
        requirements: GeometryConversionRequirements, tolerance: ModelingTolerance,
        admission: GeometryConversionAdmission) throws -> GeometrySurfaceConversionResult {
        try approximateOriginalSurface(source: source, over: parameters, requirements: requirements,
            tolerance: tolerance, admission: admission)
    }

    private func approximateOriginalSurface(source: any GeometrySurfaceConversionSource, over parameters: SurfaceParameterBox,
        requirements: GeometryConversionRequirements, tolerance: ModelingTolerance,
        admission: GeometryConversionAdmission?) throws -> GeometrySurfaceConversionResult {
        if let admission {
            try requirements.validate(); try tolerance.validate(); try admission.chargeWork()
            try source.validate(over: parameters, tolerance: tolerance, admission: admission)
        } else {
            try admit(source: source, parameters: parameters, requirements: requirements, tolerance: tolerance)
        }
        var budget = GeometryConversionBudget(requirements, admission: admission)
        var spans = 1
        let degree = min(3, requirements.maximumDegree)
        for _ in 0..<requirements.maximumCandidateCount {
            try Task.checkCancellation()
            let sum = spans.addingReportingOverflow(degree)
            guard !sum.overflow else { throw GeometryConversionError.resourceLimitExceeded("Surface dimension overflowed.") }
            try chargeSurface(u: sum.partialValue, v: sum.partialValue, requirements: requirements, budget: &budget)
            let candidate = try MappedBSplineSurfaceFitter.fit(
                layout: .init(uDegree: degree, vDegree: degree, uSpans: spans, vSpans: spans),
                u: parameters.u, v: parameters.v, tolerance: tolerance, admission: admission
            ) { u, v in
                try Task.checkCancellation()
                if let admission { return try source.point(u: u, v: v, tolerance: tolerance, admission: admission) }
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

    public func certifyCurve(source: any GeometryCurveConversionSource, candidate: BSplineCurve3D,
        over parameters: ScalarInterval, requirements: GeometryConversionRequirements,
        tolerance: ModelingTolerance, admission: GeometryConversionAdmission) throws -> GeometryConversionGuarantee {
        try requirements.validate(); try tolerance.validate(); try admission.chargeWork()
        guard parameters.lower.isFinite, parameters.upper.isFinite,
            parameters.lower < parameters.upper, parameters.width.isFinite else {
            throw GeometryConversionError.invalidInput("Curve certification requires a finite positive original parameter interval.")
        }
        try source.validate(over: parameters, tolerance: tolerance, admission: admission)
        var budget = GeometryConversionBudget(requirements, admission: admission)
        try chargeCurve(count: candidate.controlPointCount, requirements: requirements, budget: &budget)
        return try publishedGuarantee {
            try certify(source: source, candidate: candidate, parameters: parameters,
                requirements: requirements, tolerance: tolerance, budget: &budget)
        }
    }

    public func certifyCurveCorrespondence(source: any GeometryCurveConversionSource,
        target: any GeometryCurveConversionSource, over parameters: ScalarInterval,
        requirements: GeometryConversionRequirements, tolerance: ModelingTolerance,
        admission: GeometryConversionAdmission) throws -> GeometryConversionGuarantee {
        try requirements.validate(); try tolerance.validate(); try admission.chargeWork()
        guard parameters.lower.isFinite, parameters.upper.isFinite,
            parameters.lower < parameters.upper, parameters.width.isFinite else {
            throw GeometryConversionError.invalidInput("Original curve correspondence requires a finite positive declared chart.")
        }
        try source.validate(over: parameters, tolerance: tolerance, admission: admission)
        try target.validate(over: parameters, tolerance: tolerance, admission: admission)
        var budget = GeometryConversionBudget(requirements, admission: admission)
        return try publishedGuarantee {
            try GeometryConversionCertification().curve(source: source, target: target,
                parameters: parameters, requirements: requirements, tolerance: tolerance,
                targetCost: nil, budget: &budget)
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

    public func certifySurface(source: any GeometrySurfaceConversionSource, candidate: BSplineSurface3D,
        over parameters: SurfaceParameterBox, requirements: GeometryConversionRequirements,
        tolerance: ModelingTolerance, admission: GeometryConversionAdmission) throws -> GeometryConversionGuarantee {
        try requirements.validate(); try tolerance.validate(); try admission.chargeWork()
        guard parameters.u.lower < parameters.u.upper, parameters.v.lower < parameters.v.upper,
            parameters.u.width.isFinite, parameters.v.width.isFinite else {
            throw GeometryConversionError.invalidInput("Surface certification requires finite positive original parameter spans.")
        }
        try source.validate(over: parameters, tolerance: tolerance, admission: admission)
        var budget = GeometryConversionBudget(requirements, admission: admission)
        try chargeSurface(u: candidate.uControlPointCount, v: candidate.vControlPointCount,
            requirements: requirements, budget: &budget)
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
        let target: any GeometryCurveConversionSource
        let targetCost: GeometryConversionTargetCost
        if let admission = budget.admission {
            // The bounded native owner admits actual source coefficients and
            // query scratch. Legacy polynomial target estimates cannot do so.
            targetCost = .curve(candidate)
            target = try NativeCurveConversionSource(.bSpline(candidate), tolerance: tolerance, admission: admission)
            try targetCost.chargePreparation(budget: &budget)
            try target.validate(over: parameters, tolerance: tolerance, admission: admission)
        } else {
            let polynomial = PolynomialCurveConversionTarget.accepts(candidate)
            targetCost = polynomial ? .polynomialCurve(candidate) : .curve(candidate)
            try targetCost.chargePreparation(budget: &budget)
            target = polynomial ? try PolynomialCurveConversionTarget(candidate, tolerance: tolerance)
                : try NativeCurveConversionSource(.bSpline(candidate), tolerance: tolerance)
            try target.validate(over: parameters, tolerance: tolerance)
        }
        return try GeometryConversionCertification().curve(source: source, target: target, parameters: parameters,
            requirements: requirements, tolerance: tolerance, targetCost: targetCost, budget: &budget)
    }
    private func certify(source: any GeometrySurfaceConversionSource, candidate: BSplineSurface3D, parameters: SurfaceParameterBox,
        requirements: GeometryConversionRequirements, tolerance: ModelingTolerance,
        budget: inout GeometryConversionBudget) throws -> GeometryConversionGuarantee {
        try validate(candidate: candidate, parameters: parameters, requirements: requirements,
            tolerance: tolerance, admission: budget.admission)
        let target: any GeometrySurfaceConversionSource
        let targetCost: GeometryConversionTargetCost
        if let admission = budget.admission {
            targetCost = .surface(candidate)
            target = try NativeSurfaceConversionSource(.bSpline(candidate), tolerance: tolerance, admission: admission)
            try targetCost.chargePreparation(budget: &budget)
            try target.validate(over: parameters, tolerance: tolerance, admission: admission)
        } else {
            let polynomial = PolynomialSurfaceConversionTarget.accepts(candidate)
            targetCost = polynomial ? .polynomialSurface(candidate) : .surface(candidate)
            try targetCost.chargePreparation(budget: &budget)
            target = polynomial ? try PolynomialSurfaceConversionTarget(candidate, tolerance: tolerance)
                : try NativeSurfaceConversionSource(.bSpline(candidate), tolerance: tolerance)
        }
        return try GeometryConversionCertification().surface(source: source, target: target, parameters: parameters,
            requirements: requirements, tolerance: tolerance, targetCost: targetCost, budget: &budget)
    }
    private func validate(candidate: BSplineSurface3D, parameters: SurfaceParameterBox,
        requirements: GeometryConversionRequirements, tolerance: ModelingTolerance,
        admission: GeometryConversionAdmission? = nil) throws {
        let count = try GeometryConversionBudget.product(candidate.uControlPointCount, candidate.vControlPointCount)
        guard max(candidate.uDegree, candidate.vDegree) <= requirements.maximumDegree, count <= requirements.maximumControlPointCount else {
            throw GeometryConversionError.resourceLimitExceeded("The surface exceeds the requested degree or control-point count.")
        }
        if admission == nil {
            try parameters.validate(for: .bSpline(candidate), tolerance: tolerance)
        }
        // Bounded Native preparation owns original candidate validation before
        // domain admission; an opaque legacy validation cannot run beforehand.
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
        tolerance: ModelingTolerance, admission: GeometryConversionAdmission? = nil) throws -> BSplineCurve3D {
        guard breaks.count >= 2, degree >= 1, degree <= 3 else {
            throw GeometryConversionError.invalidInput("Candidate construction needs increasing breaks and its configured linear through cubic policy.")
        }
        let controlCount = try curveCount(degree: degree, spans: breaks.count - 1)
        let knotCount = controlCount.addingReportingOverflow(degree + 1)
        guard !knotCount.overflow else { throw GeometryConversionError.resourceLimitExceeded("Candidate knot count overflowed.") }
        if let admission {
            try admission.chargeStorage(bytes: GeometryConversionBudget.product(controlCount, MemoryLayout<Point3D>.stride))
            try admission.chargeStorage(bytes: GeometryConversionBudget.product(knotCount.partialValue, MemoryLayout<Double>.stride))
            try admission.chargeStorage(bytes: GeometryConversionBudget.product(controlCount, MemoryLayout<Double>.stride))
        }
        func station(_ parameter: Double) throws -> (point: Point3D, derivative: Vector3D) {
            guard let admission else { return try source.pointAndDerivative(at: parameter, tolerance: tolerance) }
            let value = try source.enclosure(over: .init(lower: parameter, upper: parameter),
                tolerance: tolerance, admission: admission)
            return (.init(x: value.position.x.midpoint, y: value.position.y.midpoint, z: value.position.z.midpoint),
                .init(x: value.firstDerivative.x.midpoint, y: value.firstDerivative.y.midpoint, z: value.firstDerivative.z.midpoint))
        }
        var controls: [Point3D] = []
        var knots: [Double] = []
        if admission != nil { controls.reserveCapacity(controlCount); knots.reserveCapacity(knotCount.partialValue) }
        knots.append(contentsOf: repeatElement(breaks[0], count: degree + 1))
        var start = try station(breaks[0])
        try start.point.validate(); try start.derivative.validate()
        controls.append(start.point)
        for i in 0..<(breaks.count - 1) {
            try Task.checkCancellation(); try admission?.chargeWork()
            let a = breaks[i], b = breaks[i + 1]
            guard b > a else { throw GeometryConversionError.invalidInput("Candidate breaks must be strictly increasing.") }
            let end = try station(b)
            try end.point.validate(); try end.derivative.validate()
            if degree == 3 {
                let factor = a.sign != b.sign ? b / 3 - a / 3 : (b - a) / 3
                controls.append(start.point + start.derivative * factor)
                controls.append(end.point + end.derivative * (-factor))
            } else if degree == 2 {
                let mid = try station(ScalarInterval(lower: a, upper: b).midpoint).point
                try mid.validate()
                controls.append(mid + (mid - start.point) * 0.5 + (mid - end.point) * 0.5)
            }
            controls.append(end.point)
            if i + 1 < breaks.count - 1 { knots.append(contentsOf: repeatElement(b, count: degree)) }
            start = end
        }
        knots.append(contentsOf: repeatElement(breaks[breaks.count - 1], count: degree + 1))
        let result: BSplineCurve3D
        if let admission {
            result = .init(degree: degree, knots: knots, controlPoints: controls,
                weights: Array(repeating: 1, count: controlCount))
            try result.validate(tolerance: tolerance, consumeWork: { try admission.chargeWork() })
        } else {
            result = .init(degree: degree, knots: knots, controlPoints: controls)
            try result.validate(tolerance: tolerance)
        }
        return result
    }
}
