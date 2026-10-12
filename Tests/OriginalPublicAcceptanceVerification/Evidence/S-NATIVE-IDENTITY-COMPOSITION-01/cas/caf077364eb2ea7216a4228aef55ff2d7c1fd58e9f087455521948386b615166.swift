import CADCore

extension BSplineSurface3D {
    func refiningTensorAxis(
        direction: SurfaceParameterDirection, value: Double,
        options: PeriodicBSplineExpansionOptions, tolerance: ModelingTolerance
    ) throws -> BSplineSurface3D {
        try options.validate(tolerance: tolerance)
        guard value.isFinite else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "Tensor knot insertion requires a finite parameter.")
        }
        let degree = direction == .u ? uDegree : vDegree
        let knots = direction == .u ? uKnots : vKnots
        let count = direction == .u ? uControlPointCount : vControlPointCount
        let perpendicular = direction == .u ? vControlPointCount : uControlPointCount
        let periodic = direction == .u ? isUPeriodic : isVPeriodic
        let parameter = try basisParameter(value, direction: direction, tolerance: tolerance)
        let plan = try PeriodicBSplineEditPlan.refinement(degree: degree, controlPointCount: count,
            periodic: periodic, isSeam: parameter == knots[degree], tolerance: tolerance)
        let output = try PeriodicBSplineEditPlan.product(
            PeriodicBSplineEditPlan.sum(count, 1, tolerance), perpendicular, tolerance)
        let storage = try PeriodicBSplineEditPlan.sum(output,
            PeriodicBSplineEditPlan.product(8, plan.workspaceControlPointCount, tolerance), tolerance)
        let work = try PeriodicBSplineEditPlan.product(plan.knotInsertionWork, perpendicular, tolerance)
        try admitTensorEdit(storage: storage, work: work, options: options, tolerance: tolerance)
        return try applyingTensorLineEdit(direction: direction, tolerance: tolerance) { line in
            try line.insertingKnot(value, expansionOptions: options, tolerance: tolerance)
        }
    }

    func restrictingTensor(
        uFrom: Double, uTo: Double, vFrom: Double, vTo: Double,
        options: PeriodicBSplineExpansionOptions, tolerance: ModelingTolerance
    ) throws -> BSplineSurface3D {
        try options.validate(tolerance: tolerance)
        let uPlan = try PeriodicBSplineEditPlan.restriction(degree: uDegree, knots: uKnots,
            controlPointCount: uControlPointCount, periodic: isUPeriodic,
            lower: uFrom, upper: uTo, tolerance: tolerance)
        let vPlan = try PeriodicBSplineEditPlan.restriction(degree: vDegree, knots: vKnots,
            controlPointCount: vControlPointCount, periodic: isVPeriodic,
            lower: vFrom, upper: vTo, tolerance: tolerance)
        let intermediate = try PeriodicBSplineEditPlan.product(
            uPlan.workspaceControlPointCount, vControlPointCount, tolerance)
        let output = try PeriodicBSplineEditPlan.product(
            uPlan.workspaceControlPointCount, vPlan.workspaceControlPointCount, tolerance)
        let firstPeak = try PeriodicBSplineEditPlan.sum(intermediate,
            PeriodicBSplineEditPlan.product(8, uPlan.workspaceControlPointCount, tolerance), tolerance)
        let secondPeak = try PeriodicBSplineEditPlan.sum(
            PeriodicBSplineEditPlan.sum(intermediate, output, tolerance),
            PeriodicBSplineEditPlan.product(8,
                max(uPlan.workspaceControlPointCount, vPlan.workspaceControlPointCount), tolerance), tolerance)
        let work = try PeriodicBSplineEditPlan.sum(
            PeriodicBSplineEditPlan.product(uPlan.knotInsertionWork, vControlPointCount, tolerance),
            PeriodicBSplineEditPlan.product(vPlan.knotInsertionWork, uPlan.workspaceControlPointCount, tolerance), tolerance)
        try admitTensorEdit(storage: max(firstPeak, secondPeak), work: work,
            options: options, tolerance: tolerance)
        let intermediateSurface = try applyingTensorLineEdit(direction: .u, tolerance: tolerance) { line in
            try Self.restrictControlLine(line, lower: uFrom, upper: uTo,
                options: options, tolerance: tolerance)
        }
        return try intermediateSurface.applyingTensorLineEdit(direction: .v, tolerance: tolerance) { line in
            try Self.restrictControlLine(line, lower: vFrom, upper: vTo,
                options: options, tolerance: tolerance)
        }
    }

    private static func restrictControlLine(
        _ line: BSplineCurve3D, lower: Double, upper: Double,
        options: PeriodicBSplineExpansionOptions, tolerance: ModelingTolerance
    ) throws -> BSplineCurve3D {
        if line.isPeriodic {
            return try line.trimmed(from: lower, to: upper, expansionOptions: options, tolerance: tolerance)
        }
        return try BSplineCurveSegmentExtractor().segment(of: line, from: lower, to: upper, tolerance: tolerance)
    }

    private func admitTensorEdit(
        storage: Int, work: Int, options: PeriodicBSplineExpansionOptions, tolerance: ModelingTolerance
    ) throws {
        guard storage <= options.maximumControlPointCount, work <= options.maximumKnotInsertionWork else {
            throw PeriodicBSplineEditPlan.failure(tolerance)
        }
    }

    /// Edits one control line at a time; no complete expanded tensor is retained.
    private func applyingTensorLineEdit(
        direction: SurfaceParameterDirection, tolerance: ModelingTolerance,
        edit: (BSplineCurve3D) throws -> BSplineCurve3D
    ) throws -> BSplineSurface3D {
        let first = try edit(controlLine(direction: direction, index: 0))
        let lineCount = direction == .u ? vControlPointCount : uControlPointCount
        var points: [[Point3D]]
        var newWeights: [[Double]]
        if direction == .u {
            points = [first.controlPoints]
            newWeights = [first.weights]
            points.reserveCapacity(lineCount)
            newWeights.reserveCapacity(lineCount)
        } else {
            points = Array(repeating: Array(repeating: .origin, count: lineCount), count: first.controlPointCount)
            newWeights = Array(repeating: Array(repeating: 0.0, count: lineCount), count: first.controlPointCount)
            for j in first.controlPoints.indices {
                points[j][0] = first.controlPoints[j]
                newWeights[j][0] = first.weights[j]
            }
        }
        for index in 1..<lineCount {
            let line = try edit(controlLine(direction: direction, index: index))
            guard line.degree == first.degree, line.knots == first.knots,
                  line.controlPointCount == first.controlPointCount,
                  line.isPeriodic == first.isPeriodic, line.periodicOrigin == first.periodicOrigin else {
                throw KernelError(phase: .geometry, code: .classificationFailure, tolerance: tolerance,
                    message: "Homogeneous tensor lines did not retain their shared axis representation.")
            }
            if direction == .u {
                points.append(line.controlPoints)
                newWeights.append(line.weights)
            } else {
                for j in line.controlPoints.indices {
                    points[j][index] = line.controlPoints[j]
                    newWeights[j][index] = line.weights[j]
                }
            }
        }
        let result = BSplineSurface3D(
            uDegree: direction == .u ? first.degree : uDegree,
            vDegree: direction == .v ? first.degree : vDegree,
            uKnots: direction == .u ? first.knots : uKnots,
            vKnots: direction == .v ? first.knots : vKnots,
            controlPoints: points, weights: newWeights,
            isUPeriodic: direction == .u ? first.isPeriodic : isUPeriodic,
            isVPeriodic: direction == .v ? first.isPeriodic : isVPeriodic,
            uPeriodicOrigin: direction == .u ? first.periodicOrigin : uPeriodicOrigin,
            vPeriodicOrigin: direction == .v ? first.periodicOrigin : vPeriodicOrigin)
        try result.validate(tolerance: tolerance)
        return result
    }

    private func controlLine(direction: SurfaceParameterDirection, index: Int) -> BSplineCurve3D {
        if direction == .u {
            return BSplineCurve3D(degree: uDegree, knots: uKnots,
                controlPoints: controlPoints[index], weights: weights[index],
                isPeriodic: isUPeriodic, periodicOrigin: uPeriodicOrigin)
        }
        return BSplineCurve3D(degree: vDegree, knots: vKnots,
            controlPoints: controlPoints.map { $0[index] }, weights: weights.map { $0[index] },
            isPeriodic: isVPeriodic, periodicOrigin: vPeriodicOrigin)
    }
}
