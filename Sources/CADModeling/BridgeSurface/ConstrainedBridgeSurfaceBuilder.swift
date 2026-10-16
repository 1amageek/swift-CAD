import CADCore
import CADGeometry
import CADIR

package struct ConstrainedBridgeSurfaceBuilder: Sendable {
    package init() {}

    package func build(start: BSplineCurve3D, end: BSplineCurve3D,
                       startWall: Surface3D, endWall: Surface3D,
                       startContinuity: SurfaceContinuityLevel, endContinuity: SurfaceContinuityLevel,
                       startTension: Double, endTension: Double, width: Double?,
                       startWallBoundary: SurfaceParameterCurve? = nil,
                       endWallBoundary: SurfaceParameterCurve? = nil,
                       tolerance: ModelingTolerance,
                       using execution: inout OriginalQueryExecution) throws -> BSplineSurface3D {
        // FIXME(INCOMPLETE_IMPLEMENTATION): The selected public Bridge route
        // uses the original execution for wall preparation, basis evaluation,
        // QR and final boundary proof. Native common-basis, degree and knot
        // transforms still need direct execution before whole-feature
        // accounting may be reported complete.
        var common = try ExactRuledBSplineSurfaceBuilder().build(startBoundary: start, endBoundary: end, tolerance: tolerance, using: &execution)
        while common.uDegree < 3 { common = try common.elevatingDegree(direction: .u, tolerance: tolerance, using: &execution) }
        guard startTension.isFinite, endTension.isFinite, startTension > 0, endTension > 0,
              width.map({ $0.isFinite && $0 > tolerance.distance }) ?? true else {
            throw failure(.invalidInput, "Bridge tensions and width must be finite and positive.", tolerance)
        }
        func retain(_ count: Int, _ stride: Int) throws {
            let bytes = count.multipliedReportingOverflow(by: stride)
            guard count >= 0, !bytes.overflow else {
                throw failure(.resourceLimitExceeded, "Bridge candidate buffer accounting overflowed.", tolerance)
            }
            try execution.retainStorage(bytes: bytes.partialValue)
        }
        var firstChart = startWallBoundary, lastChart = endWallBoundary
        let firstSamples: OriginalBridgeWallSamples, lastSamples: OriginalBridgeWallSamples
        guard case let .closed(a,b) = start.domain, case let .closed(c,d) = end.domain else {
            throw failure(.invalidInput, "Bridge candidate boundaries require finite original domains.", tolerance)
        }
        if firstChart == nil {
            firstChart = try ExactFacePcurveBuilder().surfaceParameterCurve(for: .bSpline(start),
                startParameter: a, endParameter: b, on: startWall, tolerance: tolerance, using: &execution)
        }
        if lastChart == nil {
            lastChart = try ExactFacePcurveBuilder().surfaceParameterCurve(for: .bSpline(end),
                startParameter: c, endParameter: d, on: endWall, tolerance: tolerance, using: &execution)
        }
        guard let firstChart, let lastChart else {
            throw failure(.classificationFailure, "Bridge wall charts were not retained.", tolerance)
        }
        firstSamples = try OriginalBridgeWallSamples(surface: startWall, boundary: firstChart,
            tolerance: tolerance, using: &execution)
        lastSamples = try OriginalBridgeWallSamples(surface: endWall, boundary: lastChart,
            tolerance: tolerance, using: &execution)
        for attempt in 0..<8 {
            try execution.checkpoint(); try execution.consumeWork(1)
            let count = common.uControlPointCount
            guard count <= 4096, count <= 1_048_576 / count else {
                throw failure(.resourceLimitExceeded, "Bridge derivative fitting exceeded its coefficient budget.", tolerance)
            }
            guard case let .closed(lower, upper) = common.uDomain else {
                throw failure(.invalidInput, "Bridge boundaries require a finite common parameter interval.", tolerance)
            }
            let first = try common.uIsoparametricCurve(atV: 0, tolerance: tolerance, using: &execution)
            let last = try common.uIsoparametricCurve(atV: 1, tolerance: tolerance, using: &execution)
            try retain(count, MemoryLayout<Double>.stride)
            var parameters: [Double] = []; parameters.reserveCapacity(count)
            for index in 0..<count {
                var sum = 0.0
                for knot in (index + 1)...(index + common.uDegree) {
                    try execution.consumeWork(1); sum += common.uKnots[knot]
                }
                parameters.append(sum / Double(common.uDegree))
            }
            try retain(count * count, MemoryLayout<Double>.stride)
            var matrix: [Double] = []
            matrix.reserveCapacity(count * count)
            for parameter in parameters {
                try execution.consumeWork(1)
                let basis = try BSplineBasis.values(parameter: parameter, degree: common.uDegree,
                    knots: common.uKnots, count: count, using: &execution)
                try retain(basis.count, MemoryLayout<Double>.stride)
                var weighted: [Double] = []; weighted.reserveCapacity(basis.count)
                var denominator = 0.0
                for index in basis.indices {
                    try execution.consumeWork(1)
                    let value = basis[index] * first.weights[index]
                    weighted.append(value); denominator += value
                }
                guard denominator.isFinite, denominator > 0 else {
                    throw failure(.singularGeometry, "Bridge rational interpolation has no positive denominator.", tolerance)
                }
                for value in weighted { try execution.consumeWork(1); matrix.append(value / denominator) }
            }
            let solver = try SurfaceFittingQR(coefficients: matrix, rows: count, columns: count,
                relativeRankTolerance: tolerance.relative, maximumElements: 1_048_576, using: &execution)
            func controls(_ values: [Vector3D]) throws -> [Vector3D] {
                func coordinate(_ axis: Int) throws -> [Double] {
                    try retain(values.count, MemoryLayout<Double>.stride)
                    var result: [Double] = []; result.reserveCapacity(values.count)
                    for value in values {
                        try execution.consumeWork(1); result.append(axis == 0 ? value.x : axis == 1 ? value.y : value.z)
                    }
                    return result
                }
                let x = try solver.solveFullRankLeastSquares(coordinate(0), using: &execution)
                let y = try solver.solveFullRankLeastSquares(coordinate(1), using: &execution)
                let z = try solver.solveFullRankLeastSquares(coordinate(2), using: &execution)
                try retain(values.count, MemoryLayout<Vector3D>.stride)
                var result: [Vector3D] = []; result.reserveCapacity(values.count)
                for index in x.indices {
                    try execution.consumeWork(1); result.append(.init(x: x[index], y: y[index], z: z[index]))
                }
                return result
            }
            try retain(4, MemoryLayout<[Vector3D]>.stride)
            var firstDerivatives: [[Vector3D]] = [[], []]
            var secondDerivatives: [[Vector3D]] = [[], []]
            for side in 0..<2 {
                try retain(count, MemoryLayout<Vector3D>.stride)
                firstDerivatives[side].reserveCapacity(count)
                try retain(count, MemoryLayout<Vector3D>.stride)
                secondDerivatives[side].reserveCapacity(count)
            }
            let firstSource = try NativeCurveConversionSource(.bSpline(first), tolerance: tolerance, using: &execution)
            let lastSource = try NativeCurveConversionSource(.bSpline(last), tolerance: tolerance, using: &execution)
            func point(_ spline: BSplineCurve3D, source: NativeCurveConversionSource, at parameter: Double) throws -> Point3D {
                let field = try source.enclosure(over: .init(lower: parameter, upper: parameter),
                    tolerance: tolerance, using: &execution).position
                return Point3D(x: field.x.lower * 0.5 + field.x.upper * 0.5,
                    y: field.y.lower * 0.5 + field.y.upper * 0.5,
                    z: field.z.lower * 0.5 + field.z.upper * 0.5)
            }
            for parameter in parameters {
                try execution.consumeWork(1)
                let a = try point(first, source: firstSource, at: parameter)
                let b = try point(last, source: lastSource, at: parameter)
                let chord = b - a
                guard chord.length > tolerance.distance else {
                    throw failure(.singularGeometry, "Bridge boundaries coincide at a derivative station.", tolerance)
                }
                for side in 0..<2 {
                    let level = side == 0 ? startContinuity : endContinuity
                    if level == .positional {
                        firstDerivatives[side].append(chord * (((width ?? chord.length)
                            * (side == 0 ? startTension : endTension)) / chord.length))
                        secondDerivatives[side].append(.zero)
                        continue
                    }
                    let wall = side == 0 ? startWall : endWall
                    let point = side == 0 ? a : b
                    let jet: OriginalBridgeWallSamples.Candidate
                    let samples = side == 0 ? firstSamples : lastSamples
                    let fraction = (parameter - lower) / (upper - lower)
                    jet = try samples.candidate(atFraction: fraction, using: &execution)
                    guard (jet.position - point).length <= tolerance.distance else {
                        throw failure(.intersectionFailure, "A bridge boundary no longer belongs to its retained wall.", tolerance)
                    }
                    let projected = chord - jet.normal * chord.dot(jet.normal)
                    let magnitude = (width ?? chord.length) * (side == 0 ? startTension : endTension)
                    let derivative = try projected.normalized(tolerance: tolerance.distance) * magnitude
                    firstDerivatives[side].append(derivative)
                    let uu = jet.tangentU.dot(jet.tangentU)
                    let uvMetric = jet.tangentU.dot(jet.tangentV)
                    let vv = jet.tangentV.dot(jet.tangentV)
                    let determinant = uu * vv - uvMetric * uvMetric
                    guard determinant.isFinite, determinant > 0 else {
                        throw failure(.singularGeometry, "A bridge source wall has a singular tangent metric.", tolerance)
                    }
                    let rhsU = derivative.dot(jet.tangentU), rhsV = derivative.dot(jet.tangentV)
                    let du = (rhsU * vv - rhsV * uvMetric) / determinant
                    let dv = (rhsV * uu - rhsU * uvMetric) / determinant
                    let acceleration = jet.secondDerivativeUU * (du * du)
                        + jet.secondDerivativeUV * (2 * du * dv) + jet.secondDerivativeVV * (dv * dv)
                    secondDerivatives[side].append(level == .curvature
                        ? jet.normal * acceleration.dot(jet.normal) : .zero)
                }
            }
            let d0 = try controls(firstDerivatives[0]), d1 = try controls(firstDerivatives[1])
            let a0 = try controls(secondDerivatives[0]), a1 = try controls(secondDerivatives[1])
            try retain(6, MemoryLayout<[Point3D]>.stride)
            var points: [[Point3D]] = []; points.reserveCapacity(6)
            for row in 0..<6 {
                try retain(count, MemoryLayout<Point3D>.stride)
                var rowPoints: [Point3D] = []; rowPoints.reserveCapacity(count)
                for index in 0..<count {
                    try execution.consumeWork(1)
                    let point: Point3D
                    switch row {
                    case 0: point = first.controlPoints[index]
                    case 1: point = first.controlPoints[index] + d0[index] * 0.2
                    case 2: point = first.controlPoints[index] + d0[index] * 0.4 + a0[index] * 0.05
                    case 3: point = last.controlPoints[index] + d1[index] * -0.4 + a1[index] * 0.05
                    case 4: point = last.controlPoints[index] + d1[index] * -0.2
                    default: point = last.controlPoints[index]
                    }
                    rowPoints.append(point)
                }
                points.append(rowPoints)
            }
            try retain(12, MemoryLayout<Double>.stride)
            try retain(6, MemoryLayout<[Double]>.stride)
            let candidate = BSplineSurface3D(uDegree: common.uDegree, vDegree: 5,
                uKnots: common.uKnots, vKnots: [0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1],
                controlPoints: points, weights: Array(repeating: first.weights, count: 6))
            try Surface3D.bSpline(candidate).validateOriginalSource(tolerance: tolerance,
                remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth,
                maximumSubdivisionDepth: min(20, execution.effectiveLimits.maximumSubdivisionDepth),
                maximumAlgebraicDepth: execution.effectiveLimits.maximumValueDepth, using: &execution)
            do {
                for side in 0..<2 {
                    let wall = side == 0 ? startWall : endWall
                    let boundary = side == 0 ? first : last
                    // The public feature supplies its original authored coedge
                    // law. A direct builder caller's input curve is its source.
                    let sourceCurve = side == 0 ? firstChart : lastChart
                    let resultCurve = SurfaceParameterCurve.constantV(v: Double(side), uStart: lower, uEnd: upper)
                    let resultNormal: Vector3D, sourceNormal: Vector3D
                    let samples = side == 0 ? firstSamples : lastSamples
                    resultNormal = try OriginalBridgeWallSamples(surface: .bSpline(candidate), boundary: resultCurve,
                        tolerance: tolerance, using: &execution).candidate(atFraction: 0.5, using: &execution).normal
                    sourceNormal = try samples.candidate(atFraction: 0.5, using: &execution).normal
                    _ = try SurfaceBoundaryContinuityEvaluator(modelingTolerance: tolerance).certify(
                        first: SurfaceContinuitySamplingSide(surface: wall, parameterCurve: sourceCurve,
                            frameOrientation: sourceNormal.dot(resultNormal) >= 0 ? .forward : .reversed),
                        second: SurfaceContinuitySamplingSide(surface: .bSpline(candidate), parameterCurve: resultCurve),
                        requiredLevel: side == 0 ? startContinuity : endContinuity,
                        tolerances: .standard(modelingTolerance: tolerance), maximumIntervals: 65_536, maximumDepth: 20,
                        using: &execution)
                }
                return candidate
            } catch let error as KernelError where error.code == .classificationFailure || error.code == .intersectionFailure {
                guard attempt < 7 else { throw error }
            }
            let breaks = Array(Set(common.uKnots)).sorted()
            for (a, b) in zip(breaks, breaks.dropFirst()) where b > a {
                common = try common.insertingKnot(direction: .u, value: a + (b - a) * 0.5, tolerance: tolerance, using: &execution)
            }
        }
        throw failure(.classificationFailure, "Bridge continuity has no complete boundary certificate.", tolerance)
    }

    private func failure(_ code: KernelErrorCode, _ message: String, _ tolerance: ModelingTolerance) -> KernelError {
        KernelError(phase: .geometry, code: code, tolerance: tolerance, message: message)
    }
}
