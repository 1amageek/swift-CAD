import CADCore

/// Complete four-face signs prove a root for every retained source parameter.
struct OverlapClosedRectangleRootAuthority: Sendable {
    let curve: BSplineCurve3D
    let surface: BSplineSurface3D
    let range: ScalarInterval
    let pair: OverlapRegularGraphCell.Pair
    let box: SurfaceParameterBox
    let start: SurfaceParameter?
    let end: SurfaceParameter?

    private init(curve: BSplineCurve3D, surface: BSplineSurface3D, range: ScalarInterval,
                 pair: OverlapRegularGraphCell.Pair, box: SurfaceParameterBox,
                 start: SurfaceParameter?, end: SurfaceParameter?) {
        self.curve = curve; self.surface = surface; self.range = range
        self.pair = pair; self.box = box; self.start = start; self.end = end
    }

    static func certificate(curve preparedCurve: PreparedCurveDifferentialEncloser,
                            surface preparedSurface: PreparedBSplineSurfaceDifferentialEncloser,
                            range: ScalarInterval, pair: OverlapRegularGraphCell.Pair,
                            box: SurfaceParameterBox, jetWork: Int,
                            policy: OverlapProofPolicy, using execution: inout OriginalQueryExecution) throws -> Self? {
        guard case let .bSpline(source) = preparedCurve.curve, !source.isPeriodic else { return nil }
        let target = preparedSurface.surface
        guard !target.isUPeriodic, !target.isVPeriodic,
              box.u.width > 0, box.v.width > 0 else { return nil }
        let tensor = target.uControlPointCount.multipliedReportingOverflow(by: target.vControlPointCount)
        let controls = tensor.partialValue.addingReportingOverflow(source.controlPointCount)
        let coefficients = controls.partialValue.multipliedReportingOverflow(by: 4)
        let targetKnots = target.uKnots.count.addingReportingOverflow(target.vKnots.count)
        let knots = targetKnots.partialValue.addingReportingOverflow(source.knots.count)
        let scan = coefficients.partialValue.addingReportingOverflow(knots.partialValue)
        let axes = target.uControlPointCount.addingReportingOverflow(target.vControlPointCount)
        let faceComparisons = axes.partialValue.multipliedReportingOverflow(by: 6)
        let totalScan = scan.partialValue.addingReportingOverflow(faceComparisons.partialValue)
        guard !tensor.overflow, !controls.overflow, !coefficients.overflow,
              !targetKnots.overflow, !knots.overflow, !scan.overflow,
              !axes.overflow, !faceComparisons.overflow, !totalScan.overflow else { throw exhausted(policy) }
        try policy.work(totalScan.partialValue, using: &execution)
        guard clamped(target.uKnots, degree: target.uDegree, count: target.uControlPointCount),
              clamped(target.vKnots, degree: target.vDegree, count: target.vControlPointCount),
              range.lower >= source.knots[source.degree], range.upper <= source.knots[source.controlPointCount],
              box.u.lower >= target.uKnots[target.uDegree], box.u.upper <= target.uKnots[target.uControlPointCount],
              box.v.lower >= target.vKnots[target.vDegree], box.v.upper <= target.vKnots[target.vControlPointCount] else { return nil }
        for row in target.weights {
            guard row.allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }
        }
        try OriginalCoefficientAllocation.reserve(count: 3, of: OutwardScalarInterval.self, using: &execution)
        var hulls = [OutwardScalarInterval.exact(source.controlPoints[0].x),
                     .exact(source.controlPoints[0].y), .exact(source.controlPoints[0].z)]
        for index in source.controlPoints.indices {
            guard source.weights[index].isFinite, source.weights[index] > 0 else { return nil }
            for axis in 0..<3 {
                let coordinate = OverlapRegularGraphCell.coordinate(source.controlPoints[index], axis)
                guard coordinate.isFinite else { return nil }
                hulls[axis] = hulls[axis].union(.exact(coordinate))
            }
        }
        try policy.work(jetWork, using: &execution)
        let sourceValues: [OutwardScalarInterval]
        let sourceClamped = clamped(source.knots, degree: source.degree, count: source.controlPointCount)
        if range.lower == range.upper, sourceClamped,
           range.lower == source.knots[source.degree] || range.lower == source.knots[source.controlPointCount] {
            let endpoint = range.lower == source.knots[source.degree] ? source.controlPoints[0] : source.controlPoints[source.controlPointCount - 1]
            try OriginalCoefficientAllocation.reserve(count: 3, of: OutwardScalarInterval.self, using: &execution)
            sourceValues = [OutwardScalarInterval.exact(endpoint.x), .exact(endpoint.y), .exact(endpoint.z)]
        } else {
            let original = try preparedCurve.thirdOrderIntervalJet(over: range, tolerance: policy.tolerance, using: &execution)
            sourceValues = try CertifiedAnalyticCurveEvaluation.map(0..<3, using: &execution) { axis, _ in
                let value = OverlapRegularGraphCell.component(original, axis).value
                guard let intersection = value.intersection(with: hulls[axis]) else { throw inconsistent(policy) }
                return intersection
            }
        }

        // Four closed original faces, including every incident native side.
        try OriginalCoefficientAllocation.reserve(count: 4, of: SurfaceParameterBox.self, using: &execution)
        let faces = [
            SurfaceParameterBox(u: try ScalarInterval(lower: box.u.lower, upper: box.u.lower), v: box.v),
            SurfaceParameterBox(u: try ScalarInterval(lower: box.u.upper, upper: box.u.upper), v: box.v),
            SurfaceParameterBox(u: box.u, v: try ScalarInterval(lower: box.v.lower, upper: box.v.lower)),
            SurfaceParameterBox(u: box.u, v: try ScalarInterval(lower: box.v.upper, upper: box.v.upper))
        ]
        var values: [[OutwardScalarInterval]] = []
        var valuesCapacity = 0
        var identities: [[Double?]] = []
        var identitiesCapacity = 0
        for index in faces.indices {
            try policy.work(jetWork, using: &execution)
            let original = try preparedSurface.intervalJet(overClosedBox: faces[index], tolerance: policy.tolerance, using: &execution)
            let hull = try fixedAxisCoefficientHull(target, box: box, face: index, policy: policy, using: &execution)
            var faceValues: [OutwardScalarInterval] = [], exact: [Double?] = []
            var faceValuesCapacity = 0
            var exactCapacity = 0
            for axis in 0..<3 {
                let identity = constantNativeFace(target, box: box, face: index, coordinate: axis)
                let coefficientHull = axis == 0 ? hull.x : axis == 1 ? hull.y : hull.z
                guard let value = OverlapRegularGraphCell.component(original, axis).value.intersection(with: coefficientHull) else {
                    throw inconsistent(policy)
                }
                if let identity {
                    guard let intersection = value.intersection(with: .exact(identity)) else { throw inconsistent(policy) }
                    try CertifiedAnalyticCurveEvaluation.append(intersection, to: &faceValues, using: &execution, capacity: &faceValuesCapacity)
                } else { try CertifiedAnalyticCurveEvaluation.append(value, to: &faceValues, using: &execution, capacity: &faceValuesCapacity) }
                try CertifiedAnalyticCurveEvaluation.append(identity, to: &exact, using: &execution, capacity: &exactCapacity)
            }
            try CertifiedAnalyticCurveEvaluation.append(faceValues, to: &values, using: &execution, capacity: &valuesCapacity); try CertifiedAnalyticCurveEvaluation.append(exact, to: &identities, using: &execution, capacity: &identitiesCapacity)
        }
        for firstVariesU in [true, false] {
            let firstFaces = firstVariesU ? (0, 1) : (2, 3)
            let secondFaces = firstVariesU ? (2, 3) : (0, 1)
            func signs(_ coordinate: Int, faces: (Int, Int)) -> Bool {
                let source = sourceValues[coordinate]
                let lower = values[faces.0][coordinate], upper = values[faces.1][coordinate]
                return (lower.upper <= source.lower && upper.lower >= source.upper)
                    || (lower.lower >= source.upper && upper.upper <= source.lower)
            }
            guard signs(pair.first, faces: firstFaces), signs(pair.second, faces: secondFaces) else { continue }
            func endpoint(_ point: Point3D) -> SurfaceParameter? {
                func axis(_ coordinate: Int, faces: (Int, Int), parameters: ScalarInterval) -> Double? {
                    let value = OverlapRegularGraphCell.coordinate(point, coordinate)
                    if let exact = identities[faces.0][coordinate], value == exact { return parameters.lower }
                    if let exact = identities[faces.1][coordinate], value == exact { return parameters.upper }
                    return nil
                }
                guard let a = axis(pair.first, faces: firstFaces, parameters: firstVariesU ? box.u : box.v),
                      let b = axis(pair.second, faces: secondFaces, parameters: firstVariesU ? box.v : box.u) else { return nil }
                return SurfaceParameter(u: firstVariesU ? a : b, v: firstVariesU ? b : a)
            }
            return Self(curve: source, surface: target, range: range, pair: pair, box: box,
                start: sourceClamped ? endpoint(source.controlPoints[0]) : nil,
                end: sourceClamped ? endpoint(source.controlPoints[source.controlPointCount - 1]) : nil)
        }
        return nil
    }

    private static func fixedAxisCoefficientHull(_ surface: BSplineSurface3D,
        box: SurfaceParameterBox, face: Int, policy: OverlapProofPolicy, using execution: inout OriginalQueryExecution) throws
        -> (x: OutwardScalarInterval, y: OutwardScalarInterval, z: OutwardScalarInterval) {
        typealias Interval = OutwardScalarInterval
        let fixedU = face < 2, lower = face % 2 == 0
        let knots = fixedU ? surface.uKnots : surface.vKnots
        let degree = fixedU ? surface.uDegree : surface.vDegree
        let count = fixedU ? surface.uControlPointCount : surface.vControlPointCount
        let rows = fixedU ? surface.vControlPointCount : surface.uControlPointCount
        let parameter = fixedU ? (lower ? box.u.lower : box.u.upper) : (lower ? box.v.lower : box.v.upper)
        let columns = degree.addingReportingOverflow(1)
        let square = columns.partialValue.multipliedReportingOverflow(by: columns.partialValue)
        let basisWork = square.partialValue.multipliedReportingOverflow(by: 8)
        let coefficients = columns.partialValue.multipliedReportingOverflow(by: rows)
        let coefficientWork = coefficients.partialValue.multipliedReportingOverflow(by: 12)
        let workspace = columns.partialValue.multipliedReportingOverflow(by: 3)
        let knotWork = knots.count.multipliedReportingOverflow(by: 3)
        let rowWork = rows.multipliedReportingOverflow(by: 6)
        guard !columns.overflow, !square.overflow, !basisWork.overflow, !coefficients.overflow,
              !coefficientWork.overflow, !workspace.overflow, !knotWork.overflow, !rowWork.overflow else {
            throw exhausted(policy)
        }
        var total = 0
        func addFee(_ fee: Int) throws {
            let next = total.addingReportingOverflow(fee)
            guard !next.overflow else { throw exhausted(policy) }
            total = next.partialValue
        }
        try addFee(basisWork.partialValue)
        try addFee(coefficientWork.partialValue)
        try addFee(workspace.partialValue)
        try addFee(knotWork.partialValue)
        try addFee(rowWork.partialValue)
        // Pay selected-basis scratch and every original coefficient operation
        // before invoking the lower basis owner or growing any temporary arrays.
        try policy.work(total, using: &execution)
        guard let span = (degree..<count).first(where: {
            knots[$0] < knots[$0 + 1] && parameter >= knots[$0] && parameter <= knots[$0 + 1]
        }) else { throw inconsistent(policy) }
        let basis = try BSplineBasis.nonzeroIntervalDerivativeValues(parameter: parameter, degree: degree,
            throughDerivativeOrder: 0, knots: knots, count: count, owningSpan: span,
            tolerance: policy.tolerance, using: &execution)[0]
        let nonnegative = Interval(lower: 0, upper: 1)
        let origin = surface.controlPoints[0][0]
        var hullX: Interval?, hullY: Interval?, hullZ: Interval?
        for row in 0..<rows {
            try CurrentTaskCancellationChecker().checkCancellation()
            var x = Interval.exact(0), y = Interval.exact(0), z = Interval.exact(0), weight = Interval.exact(0)
            for index in basis.values.indices {
                guard let value = basis.values[index].intersection(with: nonnegative) else { throw inconsistent(policy) }
                let column = basis.startIndex + index
                let point = fixedU ? surface.controlPoints[row][column] : surface.controlPoints[column][row]
                let originalWeight = fixedU ? surface.weights[row][column] : surface.weights[column][row]
                let coefficient = value * .exact(originalWeight)
                weight = weight + coefficient
                x = x + (.exact(point.x) - .exact(origin.x)) * coefficient
                y = y + (.exact(point.y) - .exact(origin.y)) * coefficient
                z = z + (.exact(point.z) - .exact(origin.z)) * coefficient
            }
            guard weight.isFinite, weight.lower > 0,
                  let qx = x.divided(by: weight), let qy = y.divided(by: weight), let qz = z.divided(by: weight) else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: policy.tolerance,
                    message: "An original fixed-axis coefficient has no finite positive denominator enclosure.")
            }
            let rowX = Interval.exact(origin.x) + qx, rowY = Interval.exact(origin.y) + qy,
                rowZ = Interval.exact(origin.z) + qz
            guard rowX.isFinite, rowY.isFinite, rowZ.isFinite else { throw exhausted(policy) }
            hullX = hullX.map { $0.union(rowX) } ?? rowX
            hullY = hullY.map { $0.union(rowY) } ?? rowY
            hullZ = hullZ.map { $0.union(rowZ) } ?? rowZ
        }
        guard let hullX, let hullY, let hullZ else { throw inconsistent(policy) }
        return (hullX, hullY, hullZ)
    }

    private static func constantNativeFace(_ surface: BSplineSurface3D, box: SurfaceParameterBox,
                                           face: Int, coordinate: Int) -> Double? {
        let uCount = surface.uControlPointCount, vCount = surface.vControlPointCount
        let variesU = face < 2, lower = face % 2 == 0
        let native = variesU ? (lower ? surface.uKnots[surface.uDegree] : surface.uKnots[uCount])
            : (lower ? surface.vKnots[surface.vDegree] : surface.vKnots[vCount])
        let retained = variesU ? (lower ? box.u.lower : box.u.upper) : (lower ? box.v.lower : box.v.upper)
        guard retained == native else { return nil }
        let fixed = lower ? 0 : (variesU ? uCount - 1 : vCount - 1)
        let point = variesU ? surface.controlPoints[0][fixed] : surface.controlPoints[fixed][0]
        let value = OverlapRegularGraphCell.coordinate(point, coordinate)
        guard value.isFinite else { return nil }
        for index in 0..<(variesU ? vCount : uCount) {
            let point = variesU ? surface.controlPoints[index][fixed] : surface.controlPoints[fixed][index]
            if OverlapRegularGraphCell.coordinate(point, coordinate) != value { return nil }
        }
        return value
    }

    private static func clamped(_ knots: [Double], degree: Int, count: Int) -> Bool {
        let lower = knots[degree], upper = knots[count]
        return lower < upper && knots.prefix(degree + 1).allSatisfy({ $0 == lower })
            && knots.suffix(degree + 1).allSatisfy({ $0 == upper })
    }

    private static func exhausted(_ policy: OverlapProofPolicy) -> KernelError {
        KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: policy.tolerance,
            message: "Original closed rectangle coefficient admission overflowed its work count.")
    }

    private static func inconsistent(_ policy: OverlapProofPolicy) -> KernelError {
        KernelError(phase: .geometry, code: .intersectionFailure, tolerance: policy.tolerance,
            message: "An original closed rectangle enclosure excludes its independent coefficient identity.")
    }
}
