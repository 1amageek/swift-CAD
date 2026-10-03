import CADCore
import CADGeometry
import Foundation

/// Certified exact-surface integration, independent of tessellation.
struct CertifiedSurfaceFaceAreaIntegrator {
    private struct Cell {
        let t: ScalarInterval
        let r: ScalarInterval
        let depth: Int
    }

    func measurement(of face: Face, on surface: Surface3D, in model: BRepModel,
                     tolerance: ModelingTolerance, options: FaceAreaIntegrationOptions) throws -> FaceAreaMeasurement {
        try options.validate(tolerance: tolerance)
        try checkCancellation(tolerance)
        guard face.loops.count <= options.maximumBoundaryCurveCount else {
            throw failure(.resourceLimitExceeded, tolerance, "Face area loop admission limit exceeded.")
        }
        try admit(surface, options: options, tolerance: tolerance)
        var loops: [(role: LoopRole, curves: [SurfaceParameterCurve])] = []
        var count = 0
        for id in face.loops {
            guard let loop = model.loops[id], !loop.coedges.isEmpty else {
                throw failure(.missingReference, tolerance, "Face area references a missing or empty loop.")
            }
            guard loop.coedges.count <= options.maximumBoundaryCurveCount - count else {
                throw failure(.resourceLimitExceeded, tolerance, "Face area coedge admission limit exceeded.")
            }
            var curves: [SurfaceParameterCurve] = []
            for coedge in loop.coedges {
                guard let curve = coedge.surfaceParameterCurve else { throw TopologyError.invalidTrim(coedge.edgeID) }
                try admit(curve, options: options, tolerance: tolerance)
                let parts = try segments(curve, tolerance: tolerance)
                count += parts.count
                guard count <= options.maximumBoundaryCurveCount else {
                    throw failure(.resourceLimitExceeded, tolerance, "Face area boundary admission limit exceeded.")
                }
                curves.append(contentsOf: parts)
            }
            let lifted = try SurfaceParameterLoopUnwrapper().unwrap(curves, on: surface,
                tolerance: tolerance, context: "Certified face area")
            for index in lifted.indices {
                let start = lifted[index].chartStart
                let end = lifted[(index + lifted.count - 1) % lifted.count].chartEnd
                let scale = max(1, abs(start.u), abs(start.v), abs(end.u), abs(end.v))
                let rounding = Double.ulpOfOne * scale * 64
                guard abs(start.u - end.u) <= rounding, abs(start.v - end.v) <= rounding else {
                    throw failure(.topologyFailure, tolerance,
                        "Certified free-surface integration requires connected trims to parameter rounding precision.")
                }
            }
            loops.append((loop.role, lifted.map(\.translatedCurve)))
        }
        guard let firstCurve = loops.first?.curves.first else {
            throw failure(.topologyFailure, tolerance, "Face area has no trimming boundary.")
        }
        let anchor = try firstCurve.startParameter(tolerance: tolerance)
        let reference = try surface.point(u: anchor.u, v: anchor.v, tolerance: tolerance)
        let prepared = try PreparedSurfaceAreaIntegrand(surface: surface, tolerance: tolerance,
                                                        maximumControlPointCount: options.maximumControlPointCount)
        // The estimate allocates effort only. Certified final intervals own acceptance.
        var estimatedArea = 0.0
        for loop in loops {
            var signed = SurfaceParameterAreaBounds.zero
            for curve in loop.curves {
                signed = signed.adding(try SurfaceParameterCurveAreaIntegrator().bounds(
                    for: curve, uShift: 0, requestedWidth: tolerance.relative, tolerance: tolerance))
            }
            let chartArea = abs((signed.lower + signed.upper) * 0.5)
            let p = try loop.curves[0].parameter(atNormalizedFraction: 0.5, tolerance: tolerance)
            let geometry = try surface.parameterDerivatives(u: p.u, v: p.v, tolerance: tolerance)
            estimatedArea += chartArea * geometry.tangentU.cross(geometry.tangentV).length
        }
        guard estimatedArea.isFinite, estimatedArea > 0 else {
            throw failure(.singularGeometry, tolerance, "Face area effort scale is degenerate.")
        }
        let areaGoal = (tolerance.distance * tolerance.distance + tolerance.relative * estimatedArea) * 0.125
        let momentGoal = tolerance.distance * estimatedArea / sqrt(3) * 0.0625
        let goals = [areaGoal, momentGoal, momentGoal, momentGoal].map { $0 / Double(count) }
        var work = 0
        var total = Array(repeating: OutwardScalarInterval.exact(0), count: 4)
        for loop in loops {
            var accumulated = Array(repeating: OutwardScalarInterval.exact(0), count: 4)
            if prepared.translationDirection != nil, let box = try rectangularDomain(loop.curves) {
                accumulated = try integrate(curve: loop.curves[0], rectangle: box,
                    anchor: anchor, reference: reference, prepared: prepared, goals: goals,
                    options: options, work: &work, tolerance: tolerance)
            } else {
                for curve in loop.curves {
                    let contribution = try integrate(curve: curve, anchor: anchor, reference: reference,
                        prepared: prepared, goals: goals, options: options, work: &work, tolerance: tolerance)
                    for i in 0..<4 { accumulated[i] = accumulated[i] + contribution[i] }
                }
            }
            guard accumulated[0].lower > 0 || accumulated[0].upper < 0 else {
                throw failure(.classificationFailure, tolerance, "Face loop signed area is unresolved.")
            }
            let traversal = accumulated[0].lower > 0 ? 1.0 : -1.0
            let sign = loop.role == .outer ? traversal : -traversal
            for i in 0..<4 { total[i] = total[i] + accumulated[i] * .exact(sign) }
        }
        let area = total[0]
        guard area.lower > tolerance.distance * tolerance.distance, area.upper.isFinite else {
            throw failure(.singularGeometry, tolerance, "Face area is not certified strictly positive.")
        }
        let areaValue = area.lower + (area.upper - area.lower) * 0.5
        let areaError = max(areaValue - area.lower, area.upper - areaValue).nextUp
        let areaLimit = (OutwardScalarInterval.exact(tolerance.distance) * .exact(tolerance.distance)
            + OutwardScalarInterval.exact(tolerance.relative) * .exact(area.lower)).lower
        guard areaError <= areaLimit else {
            throw failure(.classificationFailure, tolerance, "Area enclosure did not meet absolute and relative error limits.")
        }
        var centers: [Double] = []
        var squaredError = 0.0
        for (index, moment) in total.dropFirst().enumerated() {
            guard let center = moment.divided(by: area), center.lower.isFinite, center.upper.isFinite else {
                throw failure(.classificationFailure, tolerance, "Face centroid denominator or moments are unresolved.")
            }
            let origin = [reference.x, reference.y, reference.z][index]
            let physical = center + .exact(origin)
            let value = physical.lower + (physical.upper - physical.lower) * 0.5
            centers.append(value)
            let error = max(value - physical.lower, physical.upper - value).nextUp
            squaredError = (squaredError + (error * error).nextUp).nextUp
        }
        guard squaredError.squareRoot().nextUp <= tolerance.distance else {
            throw failure(.classificationFailure, tolerance, "Centroid enclosure exceeds the requested distance error.")
        }
        return FaceAreaMeasurement(area: areaValue,
            centroid: Point3D(x: centers[0], y: centers[1], z: centers[2]))
    }

    private func integrate(curve: SurfaceParameterCurve, rectangle: SurfaceParameterBox? = nil,
                           anchor: SurfaceParameter, reference: Point3D,
                           prepared: PreparedSurfaceAreaIntegrand, goals: [Double],
                           options: FaceAreaIntegrationOptions, work: inout Int,
                           tolerance: ModelingTolerance) throws -> [OutwardScalarInterval] {
        var stack = [Cell(t: try ScalarInterval(lower: 0, upper: 1),
                          r: try ScalarInterval(lower: 0, upper: 1), depth: 0)]
        var total = Array(repeating: OutwardScalarInterval.exact(0), count: 4)
        while let cell = stack.popLast() {
            try checkCancellation(tolerance)
            work += 1
            guard work <= options.maximumCellCount else {
                throw KernelError(phase: .topology, code: .resourceLimitExceeded, residual: Double(work),
                    tolerance: tolerance, message: "Certified face area exceeded its cell budget.")
            }
            var values: [OutwardScalarInterval]?
            var splitT = cell.t.width >= cell.r.width
            do {
                let bounds: [SurfaceAreaIntegrandBounds]
                let midpoint: [SurfaceAreaIntegrandBounds]
                if let rectangle {
                    bounds = try prepared.rectangularTranslationBounds(rectangle: rectangle,
                        fraction: cell.t, reference: reference, tolerance: tolerance)
                    midpoint = try prepared.rectangularTranslationBounds(rectangle: rectangle,
                        fraction: ScalarInterval(lower: cell.t.midpoint, upper: cell.t.midpoint),
                        reference: reference, tolerance: tolerance)
                } else if prepared.radialIntegrationIsExact {
                    bounds = try prepared.boundaryBounds(curve: curve, anchor: anchor, reference: reference,
                        boundaryFraction: cell.t, tolerance: tolerance)
                    midpoint = try prepared.boundaryBounds(curve: curve, anchor: anchor, reference: reference,
                        boundaryFraction: ScalarInterval(lower: cell.t.midpoint, upper: cell.t.midpoint), tolerance: tolerance)
                } else {
                    bounds = try prepared.bounds(curve: curve, anchor: anchor, reference: reference,
                        boundaryFraction: cell.t, radialFraction: cell.r, tolerance: tolerance)
                    midpoint = try prepared.bounds(curve: curve, anchor: anchor, reference: reference,
                        boundaryFraction: ScalarInterval(lower: cell.t.midpoint, upper: cell.t.midpoint),
                        radialFraction: ScalarInterval(lower: cell.r.midpoint, upper: cell.r.midpoint), tolerance: tolerance)
                }
                let size = OutwardScalarInterval.exact(cell.t.upper) - .exact(cell.t.lower)
                let height = OutwardScalarInterval.exact(cell.r.upper) - .exact(cell.r.lower)
                let measure = size * height
                var contributions: [OutwardScalarInterval] = []
                var accepted = true
                var tPressure = 0.0, rPressure = 0.0
                for i in 0..<4 {
                    let f = bounds[i]
                    var local = midpoint[i].value
                    let tVariation = (f.derivativeU.upper - f.derivativeU.lower).nextUp
                    let rVariation = (f.derivativeV.upper - f.derivativeV.lower).nextUp
                    var error = ((OutwardScalarInterval.exact(tVariation) * size
                        + OutwardScalarInterval.exact(rVariation) * height) * .exact(0.125)).upper
                    if let uu = f.secondUU, let uv = f.secondUV, let vv = f.secondVV {
                        local = local + uu * size * size * OutwardScalarInterval(1.0 / 24)
                            + vv * height * height * OutwardScalarInterval(1.0 / 24)
                        error = (OutwardScalarInterval.exact((uv.upper - uv.lower).nextUp)
                            * size * height * .exact(0.0625)).upper
                        tPressure += (uu.upper - uu.lower) * cell.t.width * cell.t.width / goals[i]
                        rPressure += (vv.upper - vv.lower) * cell.r.width * cell.r.width / goals[i]
                    } else {
                        tPressure += tVariation * cell.t.width / goals[i]
                        rPressure += rVariation * cell.r.width / goals[i]
                    }
                    let bounded = (local + OutwardScalarInterval(lower: -error, upper: error)) * measure
                    guard bounded.lower.isFinite, bounded.upper.isFinite else {
                        throw failure(.classificationFailure, tolerance, "Face integral overflowed finite interval arithmetic.")
                    }
                    accepted = accepted && ((bounded.upper - bounded.lower).nextUp * 0.5).nextUp
                        <= (OutwardScalarInterval.exact(goals[i]) * measure).lower
                    contributions.append(bounded)
                }
                splitT = tPressure >= rPressure
                if accepted { values = contributions }
            } catch is SurfaceAreaEnclosureRefinementRequired {
                // A conservative UV box can overhang a valid support; only subdivision
                // may tighten it. No part of the candidate parameter box is discarded.
                splitT = true
            } catch let error as KernelError where error.code == .singularSystem || error.code == .singularGeometry {
                // A wide regular surface box can have an inconclusive normal; subdivision owns recovery.
                // Rectangular translation integration eliminated R exactly.
                // Only its varying T coordinate can resolve a singular enclosure.
                splitT = rectangle != nil || cell.t.width >= cell.r.width
            }
            if let values {
                for i in 0..<4 { total[i] = total[i] + values[i] }
                continue
            }
            guard cell.depth < options.maximumSubdivisionDepth else {
                throw failure(.resourceLimitExceeded, tolerance, "Face area reached its certified subdivision depth limit.")
            }
            let selected = splitT ? cell.t : cell.r
            let middle = selected.midpoint
            guard middle > selected.lower, middle < selected.upper else {
                throw failure(.classificationFailure, tolerance, "Face area subdivision reached floating point resolution.")
            }
            let lower = try ScalarInterval(lower: selected.lower, upper: middle)
            let upper = try ScalarInterval(lower: middle, upper: selected.upper)
            stack.append(Cell(t: splitT ? upper : cell.t, r: splitT ? cell.r : upper, depth: cell.depth + 1))
            stack.append(Cell(t: splitT ? lower : cell.t, r: splitT ? cell.r : lower, depth: cell.depth + 1))
        }
        return total
    }

    /// Exact iso-parametric rectangle authority, independent of tolerance and winding.
    private func rectangularDomain(_ curves: [SurfaceParameterCurve]) throws -> SurfaceParameterBox? {
        guard curves.count == 4 else { return nil }
        var starts: [SurfaceParameter] = [], ends: [SurfaceParameter] = []
        for curve in curves {
            switch curve {
            case .constantU(let u, let first, let last):
                guard first != last else { return nil }
                starts.append(SurfaceParameter(u: u, v: first)); ends.append(SurfaceParameter(u: u, v: last))
            case .constantV(let v, let first, let last):
                guard first != last else { return nil }
                starts.append(SurfaceParameter(u: first, v: v)); ends.append(SurfaceParameter(u: last, v: v))
            default: return nil
            }
        }
        guard Set(starts).count == 4,
              starts.indices.allSatisfy({ ends[$0] == starts[($0 + 1) % 4] }),
              let uLow = starts.map(\.u).min(), let uHigh = starts.map(\.u).max(),
              let vLow = starts.map(\.v).min(), let vHigh = starts.map(\.v).max(),
              uHigh > uLow, vHigh > vLow,
              starts.allSatisfy({ ($0.u == uLow || $0.u == uHigh) && ($0.v == vLow || $0.v == vHigh) }) else { return nil }
        return SurfaceParameterBox(u: try ScalarInterval(lower: uLow, upper: uHigh),
                                   v: try ScalarInterval(lower: vLow, upper: vHigh))
    }

    private func segments(_ curve: SurfaceParameterCurve, tolerance: ModelingTolerance) throws -> [SurfaceParameterCurve] {
        switch curve {
        case .polyline(let points):
            guard points.count >= 2 else { throw failure(.invalidInput, tolerance, "Area trim polyline is empty.") }
            return points.indices.dropFirst().map { index in
                let a = points[index - 1], b = points[index]
                return .affine(origin: Point2D(x: a.u, y: a.v), direction: Point2D(x: b.u-a.u, y: b.v-a.v),
                               startParameter: 0, endParameter: 1)
            }
        case .periodicTranslation(let base, let u, let v):
            return try segments(base, tolerance: tolerance).map { .periodicTranslation(base: $0, uShift: u, vShift: v) }
        default: return [curve]
        }
    }

    private func admit(_ surface: Surface3D, options: FaceAreaIntegrationOptions,
                       tolerance: ModelingTolerance, depth: Int = 0) throws {
        guard depth <= 16 else { throw failure(.resourceLimitExceeded, tolerance, "Area procedural nesting limit exceeded.") }
        switch surface {
        case .bSpline(let spline):
            let uControlCount = spline.controlPoints.first?.count ?? 0
            let vControlCount = spline.controlPoints.count
            guard spline.uKnots.count <= options.maximumControlPointCount * 2 + 1,
                  spline.vKnots.count <= options.maximumControlPointCount * 2 + 1,
                  spline.weights.count <= options.maximumControlPointCount,
                  spline.weights.allSatisfy({ $0.count <= options.maximumControlPointCount }) else {
                throw failure(.resourceLimitExceeded, tolerance, "Area support dimension admission limit exceeded.")
            }
            guard uControlCount > 0, vControlCount > 0,
                  spline.uDegree >= 1, spline.uDegree < uControlCount,
                  spline.vDegree >= 1, spline.vDegree < vControlCount,
                  spline.uKnots.count == uControlCount + spline.uDegree + 1,
                  spline.vKnots.count == vControlCount + spline.vDegree + 1,
                  spline.weights.count == vControlCount,
                  spline.controlPoints.allSatisfy({ $0.count == uControlCount }),
                  spline.weights.allSatisfy({ $0.count == uControlCount }) else {
                throw failure(.invalidInput, tolerance, "Area support spline dimensions are inconsistent.")
            }
            var count = 0
            for row in spline.controlPoints {
                guard row.count <= options.maximumControlPointCount - count else {
                    throw failure(.resourceLimitExceeded, tolerance, "Area spline control-point admission limit exceeded.")
                }
                count += row.count
            }
            let uCount = spline.controlPoints.first?.count ?? 0
            let vCount = spline.controlPoints.count
            let factors = [max(1, uCount - spline.uDegree), max(1, vCount - spline.vDegree),
                           spline.uDegree + 1, spline.vDegree + 1]
            var expanded = 1
            for factor in factors {
                guard factor > 0, factor <= options.maximumControlPointCount / expanded else {
                    throw failure(.resourceLimitExceeded, tolerance, "Area Bezier preparation admission limit exceeded.")
                }
                expanded *= factor
            }
        case .procedural(.ruled(let ruled)):
            try admit(ruled.startBoundary, options: options, tolerance: tolerance, depth: depth + 1)
            try admit(ruled.endBoundary, options: options, tolerance: tolerance, depth: depth + 1)
        case .procedural(.rollingBall(let blend)):
            try admit(blend.firstContact, options: options, tolerance: tolerance, depth: depth + 1)
            try admit(blend.secondContact, options: options, tolerance: tolerance, depth: depth + 1)
        case .procedural(.offset(let offset)):
            try admit(offset.source, options: options, tolerance: tolerance, depth: depth + 1)
        default: break
        }
    }

    private func admit(_ curve: SurfaceParameterCurve, options: FaceAreaIntegrationOptions,
                       tolerance: ModelingTolerance, depth: Int = 0) throws {
        guard depth <= 16 else { throw failure(.resourceLimitExceeded, tolerance, "Area trim nesting limit exceeded.") }
        switch curve {
        case .polyline(let points):
            guard points.count <= options.maximumBoundaryCurveCount else {
                throw failure(.resourceLimitExceeded, tolerance, "Area polyline admission limit exceeded.")
            }
        case .bSpline(let spline):
            try admitSplineDimensions(controlCount: spline.controlPoints.count, degree: spline.degree,
                knotCount: spline.knots.count, weightCount: spline.weights.count,
                options: options, tolerance: tolerance)
            let internalKnots = Array(Set(spline.knots)).sorted().dropFirst().dropLast()
            guard internalKnots.allSatisfy({ knot in
                spline.degree - spline.knots.filter { $0 == knot }.count >= 2
            }) else {
                throw failure(.unsupportedCapability, tolerance, "Area fan trim derivatives require C2 across interior knots.")
            }
        case .periodicTranslation(let base, _, _):
            try admit(base, options: options, tolerance: tolerance, depth: depth + 1)
        case .affine, .constantU, .constantV, .harmonic: break
        default:
            // FIXME(INCOMPLETE_IMPLEMENTATION): Non-numeric certified and mapped charts need
            // integral-specific derivative admission on the production face-area path.
            // Complete only when exact jets and successful/error integral fixtures are verified.
            throw failure(.unsupportedCapability, tolerance, "Area integration has no certified derivative admission for this trim chart.")
        }
    }

    private func admit(_ curve: Curve3D, options: FaceAreaIntegrationOptions,
                       tolerance: ModelingTolerance, depth: Int) throws {
        guard depth <= 16 else { throw failure(.resourceLimitExceeded, tolerance, "Area curve nesting limit exceeded.") }
        switch curve {
        case .bSpline(let spline):
            try admitSplineDimensions(controlCount: spline.controlPoints.count, degree: spline.degree,
                knotCount: spline.knots.count, weightCount: spline.weights.count,
                options: options, tolerance: tolerance)
        case .surfaceLift(let lift):
            try admit(lift.surface, options: options, tolerance: tolerance, depth: depth + 1)
            try admit(lift.parameterCurve, options: options, tolerance: tolerance, depth: depth + 1)
        default: break
        }
    }

    private func admitSplineDimensions(controlCount: Int, degree: Int, knotCount: Int, weightCount: Int,
                                       options: FaceAreaIntegrationOptions, tolerance: ModelingTolerance) throws {
        guard controlCount <= options.maximumControlPointCount,
              weightCount <= options.maximumControlPointCount,
              knotCount <= options.maximumControlPointCount * 2 + 1 else {
            throw failure(.resourceLimitExceeded, tolerance, "Area spline input dimension admission limit exceeded.")
        }
        guard controlCount > 1, degree >= 1, degree < controlCount,
              knotCount == controlCount + degree + 1, weightCount == controlCount else {
            throw failure(.invalidInput, tolerance, "Area spline input dimensions are inconsistent.")
        }
    }

    private func checkCancellation(_ tolerance: ModelingTolerance) throws {
        if Task.isCancelled { throw failure(.cancelled, tolerance, "Face area integration was cancelled.") }
    }

    private func failure(_ code: KernelErrorCode, _ tolerance: ModelingTolerance, _ message: String) -> KernelError {
        KernelError(phase: .topology, code: code, tolerance: tolerance, message: message)
    }
}
