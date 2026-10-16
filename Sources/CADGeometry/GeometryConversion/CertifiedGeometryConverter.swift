import CADCore

public struct CertifiedGeometryConverter: CallerAdmittedGeometryConverting {
    public init() {}

    public func approximateCurve(source: any GeometryCurveConversionSource, over parameters: ScalarInterval,
        requirements: GeometryConversionRequirements, tolerance: ModelingTolerance) throws -> GeometryCurveConversionResult {
        var execution = try independentExecution(requirements)
        return try approximateCurve(source: source, over: parameters, requirements: requirements,
            tolerance: tolerance, using: &execution)
    }

    public func approximateCurve(source: any GeometryCurveConversionSource, over parameters: ScalarInterval,
        requirements: GeometryConversionRequirements, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> GeometryCurveConversionResult {
        try requirements.validate(); try tolerance.validate(); try execution.checkpoint()
        return try execution.withConversionScope(maximumWorkUnits: requirements.maximumWorkUnits,
            maximumScalarCount: requirements.maximumScalarCount, maximumCertificationBoxes: requirements.maximumCertificationBoxes) { execution in
        guard parameters.lower < parameters.upper else {
            throw GeometryConversionError.invalidInput("Curve approximation needs a positive original parameter interval.")
        }
        try source.validate(over: parameters, tolerance: tolerance, using: &execution)
        var spans = 1
        for _ in 0..<requirements.maximumCandidateCount {
            try CurrentTaskCancellationChecker().checkCancellation()
            let degree = min(3, requirements.maximumDegree)
            try chargeCurve(count: curveCount(degree: degree, spans: spans), requirements: requirements, using: &execution)
            let capacity = spans.addingReportingOverflow(1)
            guard !capacity.overflow else { throw GeometryConversionError.resourceLimitExceeded("Candidate breakpoint count overflowed.") }
            try execution.retainStorage(bytes: GeometryConversionDimensions.product(capacity.partialValue, MemoryLayout<Double>.stride))
            var breaks: [Double] = []
            breaks.reserveCapacity(capacity.partialValue)
            for i in 0...spans {
                try execution.consumeWork(1)
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
                using: &execution)
            do {
                let guarantee = try certify(source: source, candidate: curve, parameters: parameters,
                    requirements: requirements, tolerance: tolerance, using: &execution)
                return GeometryCurveConversionResult(curve: curve, parameters: parameters, guarantee: guarantee)
            } catch GeometryConversionAdmissionRejection.candidate { }
            spans = try GeometryConversionDimensions.product(spans, 2)
        }
        throw GeometryConversionError.toleranceRejected
            }
    }

    public func interpolateCurve(source: any GeometryCurveConversionSource, at parameters: [Double],
        requirements: GeometryConversionRequirements, tolerance: ModelingTolerance) throws -> GeometryCurveConversionResult {
        var execution = try independentExecution(requirements)
        return try interpolateCurve(source: source, at: parameters, requirements: requirements,
            tolerance: tolerance, using: &execution)
    }

    public func interpolateCurve(source: any GeometryCurveConversionSource, at parameters: [Double],
        requirements: GeometryConversionRequirements, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> GeometryCurveConversionResult {
        try requirements.validate(); try tolerance.validate(); try execution.checkpoint()
        return try execution.withConversionScope(maximumWorkUnits: requirements.maximumWorkUnits,
            maximumScalarCount: requirements.maximumScalarCount, maximumCertificationBoxes: requirements.maximumCertificationBoxes) { execution in
        guard parameters.count >= 2, let lower = parameters.first, let upper = parameters.last else {
            throw GeometryConversionError.invalidInput("Curve interpolation requires at least two increasing parameters.")
        }
        for i in parameters.indices {
            try CurrentTaskCancellationChecker().checkCancellation(); try execution.consumeWork(1)
            guard parameters[i].isFinite, i == 0 || parameters[i] > parameters[i - 1] else {
                throw GeometryConversionError.invalidInput("Interpolation parameters must be finite and strictly increasing.")
            }
        }
        let interval = try ScalarInterval(lower: lower, upper: upper)
        guard interval.width.isFinite else {
            throw GeometryConversionError.invalidInput("Original interpolation span must be finite.")
        }
        try source.validate(over: interval, tolerance: tolerance, using: &execution)
        let degree = min(3, requirements.maximumDegree)
        try chargeCurve(count: curveCount(degree: degree, spans: parameters.count - 1), requirements: requirements, using: &execution)
        let curve = try curveCandidate(source: source, breaks: parameters, degree: degree, tolerance: tolerance,
            using: &execution)
        let guarantee = try publishedGuarantee {
            try certify(source: source, candidate: curve, parameters: interval,
                requirements: requirements, tolerance: tolerance, using: &execution)
        }
        return GeometryCurveConversionResult(curve: curve, parameters: interval, guarantee: guarantee)
            }
    }

    public func approximateSurface(source: any GeometrySurfaceConversionSource, over parameters: SurfaceParameterBox,
        requirements: GeometryConversionRequirements, tolerance: ModelingTolerance) throws -> GeometrySurfaceConversionResult {
        var execution = try independentExecution(requirements)
        return try approximateSurface(source: source, over: parameters, requirements: requirements,
            tolerance: tolerance, using: &execution)
    }

    public func approximateSurface(source: any GeometrySurfaceConversionSource, over parameters: SurfaceParameterBox,
        requirements: GeometryConversionRequirements, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> GeometrySurfaceConversionResult {
        try requirements.validate(); try tolerance.validate(); try execution.checkpoint()
        return try execution.withConversionScope(maximumWorkUnits: requirements.maximumWorkUnits,
            maximumScalarCount: requirements.maximumScalarCount, maximumCertificationBoxes: requirements.maximumCertificationBoxes) { execution in
        try source.validate(over: parameters, tolerance: tolerance, using: &execution)
        var spans = 1
        let degree = min(3, requirements.maximumDegree)
        for _ in 0..<requirements.maximumCandidateCount {
            try CurrentTaskCancellationChecker().checkCancellation()
            let sum = spans.addingReportingOverflow(degree)
            guard !sum.overflow else { throw GeometryConversionError.resourceLimitExceeded("Surface dimension overflowed.") }
            try chargeSurface(u: sum.partialValue, v: sum.partialValue, requirements: requirements, using: &execution)
            let candidate = try MappedBSplineSurfaceFitter.fit(
                layout: .init(uDegree: degree, vDegree: degree, uSpans: spans, vSpans: spans),
                u: parameters.u, v: parameters.v, tolerance: tolerance, using: &execution
            ) { u, v, execution in
                try CurrentTaskCancellationChecker().checkCancellation()
                return try source.point(u: u, v: v, tolerance: tolerance, using: &execution)
            }.surface
            do {
                let guarantee = try certify(source: source, candidate: candidate, parameters: parameters,
                    requirements: requirements, tolerance: tolerance, using: &execution)
                return GeometrySurfaceConversionResult(surface: candidate, parameters: parameters, guarantee: guarantee)
            } catch GeometryConversionAdmissionRejection.candidate { }
            spans = try GeometryConversionDimensions.product(spans, 2)
        }
        throw GeometryConversionError.toleranceRejected
            }
    }

    public func interpolateSurface(source: any GeometrySurfaceConversionSource, template: BSplineSurface3D,
        points: [GeometrySurfaceInterpolationPoint], over parameters: SurfaceParameterBox,
        requirements: GeometryConversionRequirements, tolerance: ModelingTolerance) throws -> GeometrySurfaceConversionResult {
        var execution = try independentExecution(requirements)
        return try interpolateSurface(source: source, template: template, points: points, over: parameters,
            requirements: requirements, tolerance: tolerance, using: &execution)
    }

    public func interpolateSurface(source: any GeometrySurfaceConversionSource, template: BSplineSurface3D,
        points: [GeometrySurfaceInterpolationPoint], over parameters: SurfaceParameterBox,
        requirements: GeometryConversionRequirements, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> GeometrySurfaceConversionResult {
        try requirements.validate(); try tolerance.validate(); try execution.checkpoint()
        return try execution.withConversionScope(maximumWorkUnits: requirements.maximumWorkUnits,
            maximumScalarCount: requirements.maximumScalarCount, maximumCertificationBoxes: requirements.maximumCertificationBoxes) { execution in
        try source.validate(over: parameters, tolerance: tolerance, using: &execution)
        try validate(candidate: template, parameters: parameters, requirements: requirements, tolerance: tolerance)
        guard !points.isEmpty else { throw GeometryConversionError.invalidInput("Surface interpolation requires point constraints.") }
        try chargeSurface(u: template.uControlPointCount, v: template.vControlPointCount, requirements: requirements, using: &execution)
        let net = try GeometryConversionDimensions.product(template.uControlPointCount, template.vControlPointCount)
        try execution.charge(scalars: GeometryConversionDimensions.product(net, net, 32))
        try execution.charge(scalars: GeometryConversionDimensions.product(points.count, net, 32))
        try execution.charge(scalars: GeometryConversionDimensions.product(points.count, points.count, 16))
        try OriginalCoefficientAllocation.reserve(count: points.count, of: SurfaceFittingPointInterpolator.Constraint.self, using: &execution)
        let constraints = try points.map { value in
            try execution.consumeWork(1)
            try CurrentTaskCancellationChecker().checkCancellation()
            guard value.u.isFinite, value.v.isFinite, parameters.u.contains(value.u), parameters.v.contains(value.v), value.point.isFinite else {
                throw GeometryConversionError.invalidInput("Every interpolation point must be finite and inside the certified rectangle.")
            }
            return SurfaceFittingPointInterpolator.Constraint(u: value.u, v: value.v, point: value.point)
        }
        let candidate = try SurfaceFittingPointInterpolator.interpolate(template: template, constraints: constraints,
            referenceWeight: 1, controlNetFairnessWeight: 0,
            positionTolerance: requirements.maximumPositionError, relativeRankTolerance: tolerance.relative,
            maximumElements: requirements.maximumScalarCount, tolerance: tolerance, using: &execution)
        let guarantee = try publishedGuarantee {
            try certify(source: source, candidate: candidate, parameters: parameters,
                requirements: requirements, tolerance: tolerance, using: &execution)
        }
        return GeometrySurfaceConversionResult(surface: candidate, parameters: parameters, guarantee: guarantee)
            }
    }

    public func certifyCurve(source: any GeometryCurveConversionSource, candidate: BSplineCurve3D, over parameters: ScalarInterval,
        requirements: GeometryConversionRequirements, tolerance: ModelingTolerance) throws -> GeometryConversionGuarantee {
        var execution = try independentExecution(requirements)
        return try certifyCurve(source: source, candidate: candidate, over: parameters,
            requirements: requirements, tolerance: tolerance, using: &execution)
    }

    public func certifyCurve(source: any GeometryCurveConversionSource, candidate: BSplineCurve3D,
        over parameters: ScalarInterval, requirements: GeometryConversionRequirements,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> GeometryConversionGuarantee {
        try requirements.validate(); try tolerance.validate(); try execution.checkpoint()
        return try execution.withConversionScope(maximumWorkUnits: requirements.maximumWorkUnits,
            maximumScalarCount: requirements.maximumScalarCount, maximumCertificationBoxes: requirements.maximumCertificationBoxes) { execution in
        guard parameters.lower.isFinite, parameters.upper.isFinite,
            parameters.lower < parameters.upper, parameters.width.isFinite else {
            throw GeometryConversionError.invalidInput("Curve certification requires a finite positive original parameter interval.")
        }
        try source.validate(over: parameters, tolerance: tolerance, using: &execution)
        try chargeCurve(count: candidate.controlPointCount, requirements: requirements, using: &execution)
        return try publishedGuarantee {
            try certify(source: source, candidate: candidate, parameters: parameters,
                requirements: requirements, tolerance: tolerance, using: &execution)
        }
            }
    }

    public func certifyCurveCorrespondence(source: any GeometryCurveConversionSource,
        target: any GeometryCurveConversionSource, over parameters: ScalarInterval,
        requirements: GeometryConversionRequirements, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> GeometryConversionGuarantee {
        try requirements.validate(); try tolerance.validate(); try execution.checkpoint()
        return try execution.withConversionScope(maximumWorkUnits: requirements.maximumWorkUnits,
            maximumScalarCount: requirements.maximumScalarCount, maximumCertificationBoxes: requirements.maximumCertificationBoxes) { execution in
        guard parameters.lower.isFinite, parameters.upper.isFinite,
            parameters.lower < parameters.upper, parameters.width.isFinite else {
            throw GeometryConversionError.invalidInput("Original curve correspondence requires a finite positive declared chart.")
        }
        try source.validate(over: parameters, tolerance: tolerance, using: &execution)
        try target.validate(over: parameters, tolerance: tolerance, using: &execution)
        return try publishedGuarantee {
            try GeometryConversionCertification().curve(source: source, target: target,
                parameters: parameters, requirements: requirements, tolerance: tolerance,
                targetCost: nil, using: &execution)
        }
            }
    }

    public func certifySurface(source: any GeometrySurfaceConversionSource, candidate: BSplineSurface3D, over parameters: SurfaceParameterBox,
        requirements: GeometryConversionRequirements, tolerance: ModelingTolerance) throws -> GeometryConversionGuarantee {
        var execution = try independentExecution(requirements)
        return try certifySurface(source: source, candidate: candidate, over: parameters,
            requirements: requirements, tolerance: tolerance, using: &execution)
    }

    public func certifySurface(source: any GeometrySurfaceConversionSource, candidate: BSplineSurface3D,
        over parameters: SurfaceParameterBox, requirements: GeometryConversionRequirements,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> GeometryConversionGuarantee {
        try requirements.validate(); try tolerance.validate(); try execution.checkpoint()
        return try execution.withConversionScope(maximumWorkUnits: requirements.maximumWorkUnits,
            maximumScalarCount: requirements.maximumScalarCount, maximumCertificationBoxes: requirements.maximumCertificationBoxes) { execution in
        guard parameters.u.lower < parameters.u.upper, parameters.v.lower < parameters.v.upper,
            parameters.u.width.isFinite, parameters.v.width.isFinite else {
            throw GeometryConversionError.invalidInput("Surface certification requires finite positive original parameter spans.")
        }
        try source.validate(over: parameters, tolerance: tolerance, using: &execution)
        try chargeSurface(u: candidate.uControlPointCount, v: candidate.vControlPointCount,
            requirements: requirements, using: &execution)
        return try publishedGuarantee {
            try certify(source: source, candidate: candidate, parameters: parameters,
                requirements: requirements, tolerance: tolerance, using: &execution)
        }
            }
    }

    private func independentExecution(_ requirements: GeometryConversionRequirements) throws -> OriginalQueryExecution {
        try requirements.validate()
        let budget = try OriginalQueryBudget(workLimit: requirements.maximumWorkUnits)
        let limits = try OriginalQueryExecutionLimits(maximumValueDepth: 32, maximumCoefficientDepth: 32,
            maximumResults: requirements.maximumControlPointCount,
            remainingSourceDepth: Int.max, maximumSubdivisionDepth: requirements.maximumCertificationBoxes,
            maximumSpans: requirements.maximumControlPointCount, maximumPolynomialDegree: requirements.maximumDegree,
            maximumScalarSlots: requirements.maximumScalarCount)
        return OriginalQueryExecution(budget: budget, limits: limits)
    }

    private func publishedGuarantee(_ body: () throws -> GeometryConversionGuarantee) throws -> GeometryConversionGuarantee {
        do { return try body() }
        catch GeometryConversionAdmissionRejection.candidate { throw GeometryConversionError.toleranceRejected }
    }

    private func certify(source: any GeometryCurveConversionSource, candidate: BSplineCurve3D, parameters: ScalarInterval,
        requirements: GeometryConversionRequirements, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> GeometryConversionGuarantee {
        guard candidate.degree <= requirements.maximumDegree, candidate.controlPointCount <= requirements.maximumControlPointCount else {
            throw GeometryConversionError.resourceLimitExceeded("The curve exceeds the requested degree or control-point count.")
        }
        let target: any GeometryCurveConversionSource
        let targetCost: GeometryConversionTargetCost
        let polynomial = PolynomialCurveConversionTarget.accepts(candidate)
        targetCost = polynomial ? .polynomialCurve(candidate) : .curve(candidate)
        try targetCost.chargePreparation(using: &execution)
        target = polynomial ? try PolynomialCurveConversionTarget(candidate, tolerance: tolerance, using: &execution)
            : try NativeCurveConversionSource(.bSpline(candidate), tolerance: tolerance, using: &execution)
        try target.validate(over: parameters, tolerance: tolerance, using: &execution)
        return try GeometryConversionCertification().curve(source: source, target: target, parameters: parameters,
            requirements: requirements, tolerance: tolerance, targetCost: targetCost, using: &execution)
    }
    private func certify(source: any GeometrySurfaceConversionSource, candidate: BSplineSurface3D, parameters: SurfaceParameterBox,
        requirements: GeometryConversionRequirements, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> GeometryConversionGuarantee {
        try validate(candidate: candidate, parameters: parameters, requirements: requirements,
            tolerance: tolerance)
        let target: any GeometrySurfaceConversionSource
        let targetCost: GeometryConversionTargetCost
        let polynomial = PolynomialSurfaceConversionTarget.accepts(candidate)
        targetCost = polynomial ? .polynomialSurface(candidate) : .surface(candidate)
        try targetCost.chargePreparation(using: &execution)
        target = polynomial ? try PolynomialSurfaceConversionTarget(candidate, tolerance: tolerance, using: &execution)
            : try NativeSurfaceConversionSource(.bSpline(candidate), tolerance: tolerance, using: &execution)
        try target.validate(over: parameters, tolerance: tolerance, using: &execution)
        return try GeometryConversionCertification().surface(source: source, target: target, parameters: parameters,
            requirements: requirements, tolerance: tolerance, targetCost: targetCost, using: &execution)
    }
    private func validate(candidate: BSplineSurface3D, parameters: SurfaceParameterBox,
        requirements: GeometryConversionRequirements, tolerance: ModelingTolerance) throws {
        let count = try GeometryConversionDimensions.product(candidate.uControlPointCount, candidate.vControlPointCount)
        guard max(candidate.uDegree, candidate.vDegree) <= requirements.maximumDegree, count <= requirements.maximumControlPointCount else {
            throw GeometryConversionError.resourceLimitExceeded("The surface exceeds the requested degree or control-point count.")
        }
    }
    private func curveCount(degree: Int, spans: Int) throws -> Int {
        let product = try GeometryConversionDimensions.product(degree, spans)
        let result = product.addingReportingOverflow(1)
        guard !result.overflow else { throw GeometryConversionError.resourceLimitExceeded("Curve dimension overflowed.") }
        return result.partialValue
    }
    private func chargeCurve(count: Int, requirements: GeometryConversionRequirements, using execution: inout OriginalQueryExecution) throws {
        guard count <= requirements.maximumControlPointCount else { throw GeometryConversionError.resourceLimitExceeded("Curve control-point budget exhausted.") }
        try execution.charge(scalars: GeometryConversionDimensions.product(count, 16))
    }
    private func chargeSurface(u: Int, v: Int, requirements: GeometryConversionRequirements, using execution: inout OriginalQueryExecution) throws {
        let count = try GeometryConversionDimensions.product(u, v)
        guard count <= requirements.maximumControlPointCount else { throw GeometryConversionError.resourceLimitExceeded("Surface control-point budget exhausted.") }
        let squareU = try GeometryConversionDimensions.product(u, u), squareV = try GeometryConversionDimensions.product(v, v)
        let matrix = squareU.addingReportingOverflow(squareV)
        guard !matrix.overflow else { throw GeometryConversionError.resourceLimitExceeded("Surface matrix dimension overflowed.") }
        let storage = try GeometryConversionDimensions.product(count, 96)
        let extra = try GeometryConversionDimensions.product(matrix.partialValue, 12)
        let total = storage.addingReportingOverflow(extra)
        guard !total.overflow else { throw GeometryConversionError.resourceLimitExceeded("Surface storage dimension overflowed.") }
        try execution.charge(scalars: total.partialValue)
    }

    private func curveCandidate(source: any GeometryCurveConversionSource, breaks: [Double], degree: Int,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> BSplineCurve3D {
        guard breaks.count >= 2, degree >= 1, degree <= 3 else {
            throw GeometryConversionError.invalidInput("Candidate construction needs increasing breaks and its configured linear through cubic policy.")
        }
        let controlCount = try curveCount(degree: degree, spans: breaks.count - 1)
        let knotCount = controlCount.addingReportingOverflow(degree + 1)
        guard !knotCount.overflow else { throw GeometryConversionError.resourceLimitExceeded("Candidate knot count overflowed.") }
        try execution.retainStorage(bytes: GeometryConversionDimensions.product(controlCount, MemoryLayout<Point3D>.stride))
        try execution.retainStorage(bytes: GeometryConversionDimensions.product(knotCount.partialValue, MemoryLayout<Double>.stride))
        try execution.retainStorage(bytes: GeometryConversionDimensions.product(controlCount, MemoryLayout<Double>.stride))
        func station(_ parameter: Double, using execution: inout OriginalQueryExecution) throws -> (point: Point3D, derivative: Vector3D) {
            try source.pointAndDerivative(at: parameter, tolerance: tolerance, using: &execution)
        }
        var controls: [Point3D] = []
        var knots: [Double] = []
        controls.reserveCapacity(controlCount); knots.reserveCapacity(knotCount.partialValue)
        knots.append(contentsOf: repeatElement(breaks[0], count: degree + 1))
        var start = try station(breaks[0], using: &execution)
        try start.point.validate(); try start.derivative.validate()
        controls.append(start.point)
        for i in 0..<(breaks.count - 1) {
            try CurrentTaskCancellationChecker().checkCancellation(); try execution.consumeWork(1)
            let a = breaks[i], b = breaks[i + 1]
            guard b > a else { throw GeometryConversionError.invalidInput("Candidate breaks must be strictly increasing.") }
            let end = try station(b, using: &execution)
            try end.point.validate(); try end.derivative.validate()
            if degree == 3 {
                let factor = a.sign != b.sign ? b / 3 - a / 3 : (b - a) / 3
                controls.append(start.point + start.derivative * factor)
                controls.append(end.point + end.derivative * (-factor))
            } else if degree == 2 {
                let mid = try station(ScalarInterval(lower: a, upper: b).midpoint, using: &execution).point
                try mid.validate()
                controls.append(mid + (mid - start.point) * 0.5 + (mid - end.point) * 0.5)
            }
            controls.append(end.point)
            if i + 1 < breaks.count - 1 { knots.append(contentsOf: repeatElement(b, count: degree)) }
            start = end
        }
        knots.append(contentsOf: repeatElement(breaks[breaks.count - 1], count: degree + 1))
        let result = BSplineCurve3D(degree: degree, knots: knots, controlPoints: controls,
            weights: Array(repeating: 1, count: controlCount))
        try result.validate(tolerance: tolerance, using: &execution)
        try execution.checkpoint()
        return result
    }
}
