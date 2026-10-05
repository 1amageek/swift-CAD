import CADCore

extension BSplineSurface3D {
    /// Periodic axes accept N+1 cycle knots and N independent controls; open axes
    /// accept their complete knot vectors. Rows run along U and are indexed by V.
    public static func periodic(
        uDegree: Int, vDegree: Int, uKnots: [Double], vKnots: [Double],
        controlPoints: [[Point3D]], weights: [[Double]]? = nil,
        isUPeriodic: Bool, isVPeriodic: Bool,
        expansionOptions: PeriodicBSplineExpansionOptions = .init(),
        tolerance: ModelingTolerance
    ) throws -> BSplineSurface3D {
        try expansionOptions.validate(tolerance: tolerance)
        let vCount = controlPoints.count
        let uCount = controlPoints.first?.count ?? 0
        guard isUPeriodic || isVPeriodic, uDegree >= 1, vDegree >= 1,
              uCount > 0, vCount > 0,
              controlPoints.allSatisfy({ $0.count == uCount }),
              isUPeriodic || uDegree < uCount, isVPeriodic || vDegree < vCount else {
            throw invalidPeriodicSurface(tolerance)
        }
        let (extendedU, uOverflow) = uCount.addingReportingOverflow(isUPeriodic ? uDegree : 0)
        let (extendedV, vOverflow) = vCount.addingReportingOverflow(isVPeriodic ? vDegree : 0)
        let (total, totalOverflow) = extendedU.multipliedReportingOverflow(by: extendedV)
        guard !uOverflow, !vOverflow, !totalOverflow,
              total <= expansionOptions.maximumControlPointCount else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                message: "Periodic tensor expansion exceeds its total control-net budget.")
        }
        let cycleWeights = weights ?? controlPoints.map { Array(repeating: 1.0, count: $0.count) }
        guard cycleWeights.count == vCount, cycleWeights.allSatisfy({ $0.count == uCount }) else {
            throw invalidPeriodicSurface(tolerance)
        }
        let uCurve = isUPeriodic ? try BSplineCurve3D.periodic(
            degree: uDegree, cycleKnots: uKnots, controlPoints: controlPoints[0],
            weights: cycleWeights[0], tolerance: tolerance
        ) : nil
        let vCurve = isVPeriodic ? try BSplineCurve3D.periodic(
            degree: vDegree, cycleKnots: vKnots, controlPoints: controlPoints.map { $0[0] },
            weights: cycleWeights.map { $0[0] }, tolerance: tolerance
        ) : nil
        var points: [[Point3D]] = []
        var expandedWeights: [[Double]] = []
        points.reserveCapacity(extendedV)
        expandedWeights.reserveCapacity(extendedV)
        for j in 0..<extendedV {
            var row = controlPoints[j % vCount]
            var weightRow = cycleWeights[j % vCount]
            row.reserveCapacity(extendedU)
            weightRow.reserveCapacity(extendedU)
            for i in uCount..<extendedU {
                row.append(controlPoints[j % vCount][i % uCount])
                weightRow.append(cycleWeights[j % vCount][i % uCount])
            }
            points.append(row)
            expandedWeights.append(weightRow)
        }
        let surface = BSplineSurface3D(
            uDegree: uDegree, vDegree: vDegree,
            uKnots: uCurve?.knots ?? uKnots, vKnots: vCurve?.knots ?? vKnots,
            controlPoints: points, weights: expandedWeights,
            isUPeriodic: isUPeriodic, isVPeriodic: isVPeriodic,
            uPeriodicOrigin: uCurve?.periodicOrigin, vPeriodicOrigin: vCurve?.periodicOrigin
        )
        try surface.validate(tolerance: tolerance)
        return surface
    }

    public var uFundamentalDomain: ParameterDomain { axisDomain(direction: .u, fundamental: true) }
    public var vFundamentalDomain: ParameterDomain { axisDomain(direction: .v, fundamental: true) }

    public func periodicSeamContinuityOrder(direction: SurfaceParameterDirection) -> Int? {
        let degree = direction == .u ? uDegree : vDegree
        let knots = direction == .u ? uKnots : vKnots
        let periodic = direction == .u ? isUPeriodic : isVPeriodic
        guard periodic, degree >= 1, degree < knots.count else { return nil }
        return degree - knots.filter { $0 == knots[degree] }.count
    }

    package func periodicSeamContinuityOrder(direction: SurfaceParameterDirection,
        consumeWork: () throws -> Void) throws -> Int? {
        try Task.checkCancellation()
        try consumeWork()
        let degree = direction == .u ? uDegree : vDegree
        let knots = direction == .u ? uKnots : vKnots
        let periodic = direction == .u ? isUPeriodic : isVPeriodic
        guard periodic, degree >= 1, degree < knots.count else { return nil }
        let seam = knots[degree]
        var multiplicity = 0
        for knot in knots {
            try Task.checkCancellation()
            try consumeWork()
            if knot == seam { multiplicity += 1 }
        }
        return degree - multiplicity
    }

    public func normalizedParameter(
        _ parameter: Double, direction: SurfaceParameterDirection, tolerance: ModelingTolerance
    ) throws -> Double {
        try validate(tolerance: tolerance)
        let periodic = direction == .u ? isUPeriodic : isVPeriodic
        let knots = direction == .u ? uKnots : vKnots
        let degree = direction == .u ? uDegree : vDegree
        let origin = direction == .u ? uPeriodicOrigin : vPeriodicOrigin
        guard periodic else { throw Self.invalidPeriodicSurface(tolerance) }
        let lower = knots[degree]
        return try BSplineCurve3D.representative(parameter, origin: origin ?? lower,
            period: knots[knots.count - degree - 1] - lower, tolerance: tolerance)
    }

    /// Selects another interval of representatives without changing S(u,v).
    public func changingPeriodicOrigin(
        direction: SurfaceParameterDirection, to origin: Double, tolerance: ModelingTolerance
    ) throws -> BSplineSurface3D {
        try validate(tolerance: tolerance)
        guard direction == .u ? isUPeriodic : isVPeriodic else {
            throw Self.invalidPeriodicSurface(tolerance)
        }
        var result = self
        switch direction {
        case .u: result.uPeriodicOrigin = origin
        case .v: result.vPeriodicOrigin = origin
        }
        try result.validate(tolerance: tolerance)
        return result
    }

    func axisDomain(direction: SurfaceParameterDirection, fundamental: Bool) -> ParameterDomain {
        let degree = direction == .u ? uDegree : vDegree
        let knots = direction == .u ? uKnots : vKnots
        guard degree >= 0, degree < knots.count - 1 else { return .closed(0, 0) }
        let lower = knots[degree]
        let upper = knots[knots.count - degree - 1]
        let periodic = direction == .u ? isUPeriodic : isVPeriodic
        guard periodic else { return .closed(lower, upper) }
        let period = upper - lower
        guard fundamental else { return .periodic(period: period) }
        let origin = (direction == .u ? uPeriodicOrigin : vPeriodicOrigin) ?? lower
        return .closed(origin, origin + period)
    }

    func basisParameter(
        _ parameter: Double, direction: SurfaceParameterDirection, tolerance: ModelingTolerance
    ) throws -> Double {
        let degree = direction == .u ? uDegree : vDegree
        let knots = direction == .u ? uKnots : vKnots
        let periodic = direction == .u ? isUPeriodic : isVPeriodic
        guard periodic else {
            return BSplineBasis.clampedParameter(parameter, knots: knots, degree: degree)
        }
        let lower = knots[degree]
        return try BSplineCurve3D.representative(parameter, origin: lower,
            period: knots[knots.count - degree - 1] - lower, tolerance: tolerance)
    }

    func validatePeriodicity(tolerance: ModelingTolerance,
        consumeWork: () throws -> Void = { try Task.checkCancellation() }) throws {
        try consumeWork()
        // Full knot/net validity is proved by the caller before indexing. Both axes
        // and every repeated tail are checked in place without temporary control lines.
        if isUPeriodic {
            try BSplineCurve3D.validatePeriodicAxis(degree: uDegree, knots: uKnots,
                controlPointCount: uControlPointCount, origin: uPeriodicOrigin, tolerance: tolerance, consumeWork: consumeWork)
            let count = uControlPointCount - uDegree
            for j in controlPoints.indices {
                try consumeWork()
                for i in count..<uControlPointCount {
                    try consumeWork(); try consumeWork(); try consumeWork(); try consumeWork()
                    guard controlPoints[j][i] == controlPoints[j][i % count],
                          weights[j][i] == weights[j][i % count] else {
                        throw Self.invalidPeriodicSurface(tolerance)
                    }
                }
            }
        } else if uPeriodicOrigin != nil {
            throw Self.invalidPeriodicSurface(tolerance)
        }
        if isVPeriodic {
            try BSplineCurve3D.validatePeriodicAxis(degree: vDegree, knots: vKnots,
                controlPointCount: vControlPointCount, origin: vPeriodicOrigin, tolerance: tolerance, consumeWork: consumeWork)
            let count = vControlPointCount - vDegree
            for j in count..<vControlPointCount {
                try consumeWork()
                for i in 0..<uControlPointCount {
                    try consumeWork(); try consumeWork(); try consumeWork(); try consumeWork()
                    guard controlPoints[j][i] == controlPoints[j % count][i],
                        weights[j][i] == weights[j % count][i] else {
                        throw Self.invalidPeriodicSurface(tolerance)
                    }
                }
            }
        } else if vPeriodicOrigin != nil {
            throw Self.invalidPeriodicSurface(tolerance)
        }
    }

    func periodicOperationFailure(_ message: String, _ tolerance: ModelingTolerance) -> KernelError {
        KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance, message: message)
    }

    private static func invalidPeriodicSurface(_ tolerance: ModelingTolerance) -> KernelError {
        KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
            message: "A periodic surface requires independent translated knot axes and exactly repeated homogeneous controls.")
    }
}
