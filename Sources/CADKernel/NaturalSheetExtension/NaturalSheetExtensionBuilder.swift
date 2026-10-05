import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

struct NaturalSheetExtensionBuilder {
    let invocation: NaturalSheetExtensionInvocation?

    init(invocation: NaturalSheetExtensionInvocation? = nil) {
        self.invocation = invocation
    }
    func strip(on surface: Surface3D, face: Face, boundary: SurfaceParameterCurve, distance: Double,
               stableID: String, parents: [SubshapeID], tolerance: ModelingTolerance) throws -> BRepSewingFacePatch? {
        // Native B-spline continuation owns a different original endpoint-span
        // law producer; the retained-support strip cannot extend its closed domain.
        if case .bSpline = surface { return nil }
        let axis: Bool
        let fixed: Double
        let from: Double
        let to: Double
        guard let original = try isoBoundary(boundary, on: surface, tolerance: tolerance) else { return nil }
        axis = original.variesU; fixed = original.fixed
        from = original.start; to = original.end
        let middle = (from + to) / 2
        let geometry = try surface.differentialGeometry(u: axis ? fixed : middle, v: axis ? middle : fixed,
                                                       tolerance: tolerance)
        let tangent = (axis ? geometry.tangentV : geometry.tangentU) * (to >= from ? 1 : -1)
        let normal = geometry.normal * (face.orientation == .forward ? 1 : -1)
        let away = tangent.cross(normal)
        let varying = axis ? geometry.tangentU : geometry.tangentV
        let sign = varying.dot(away) >= 0 ? 1.0 : -1.0
        let reach = try parameterReach(on: surface, variesU: axis, fixedAcross: middle,
                                      from: fixed, sign: sign, distance: distance, tolerance: tolerance)
        let u = axis ? min(fixed, reach)...max(fixed, reach) : min(from, to)...max(from, to)
        let v = axis ? min(from, to)...max(from, to) : min(fixed, reach)...max(fixed, reach)
        let sides: [SurfaceParameterCurve] = [
            .constantV(v: v.lowerBound, uStart: u.lowerBound, uEnd: u.upperBound),
            .constantU(u: u.upperBound, vStart: v.lowerBound, vEnd: v.upperBound),
            .constantV(v: v.upperBound, uStart: u.upperBound, uEnd: u.lowerBound),
            .constantU(u: u.lowerBound, vStart: v.upperBound, vEnd: v.lowerBound),
        ]
        let edges = try sides.enumerated().map { ordinal, side in
            try BRepFaceCurveClipper.edge(side, on: surface, stableID: "\(stableID):edge:\(ordinal)",
                                         parentSubshapeIDs: parents, tolerance: tolerance)
        }
        let forward = BRepSewingFacePatch(stableID: stableID, surface: surface, orientation: .forward,
            loops: [BRepSewingLoop(stableID: "\(stableID):loop", role: .outer, edges: edges)], parentSubshapeIDs: parents)
        return try BRepSewingPatchOrientationAdapter().reorient(forward, to: face.orientation, tolerance: tolerance)
    }

    private func isoBoundary(_ curve: SurfaceParameterCurve, on surface: Surface3D,
        tolerance: ModelingTolerance) throws -> (variesU: Bool, fixed: Double, start: Double, end: Double)? {
        guard let endpoints = try ExactRectangularPcurveDomainResolver().axisAlignedEndpoints(
            of: curve, on: surface,
            consumeWork: invocation.map { invocation in
                { @Sendable depth in try invocation.consume(depth) }
            }, tolerance: tolerance) else { return nil }
        let start = endpoints.start
        let end = endpoints.end
        if start.u == end.u, start.v != end.v {
            return (true, start.u, start.v, end.v)
        }
        if start.v == end.v, start.u != end.u {
            return (false, start.v, start.u, end.u)
        }
        return nil
    }

    func parameterReach(on surface: Surface3D, variesU: Bool, fixedAcross: Double,
                                from origin: Double, sign: Double, distance: Double,
                                tolerance: ModelingTolerance) throws -> Double {
        let domain = variesU ? surface.uDomain : surface.vDomain
        func speed(_ parameter: Double) throws -> Double {
            try invocation?.consume()
            let g = try surface.parameterDerivatives(u: variesU ? parameter : fixedAcross,
                v: variesU ? fixedAcross : parameter, tolerance: tolerance)
            let value = (variesU ? g.tangentU : g.tangentV).length
            guard value.isFinite, value > Double.leastNormalMagnitude else {
                throw KernelError(phase: .geometry, code: .topologyFailure, tolerance: tolerance,
                    message: "Natural sheet continuation meets a collapsed parameter direction.")
            }
            return value
        }
        func length(_ span: Double) throws -> Double {
            let nodes = [-0.8611363115940526, -0.3399810435848563, 0.3399810435848563, 0.8611363115940526]
            let weights = [0.3478548451374538, 0.6521451548625461, 0.6521451548625461, 0.3478548451374538]
            var total = 0.0
            for interval in 0..<16 {
                let a = span * Double(interval) / 16, b = span * Double(interval + 1) / 16
                for (node, weight) in zip(nodes, weights) {
                    total += weight * (b - a) / 2 * (try speed(origin + sign * ((a + b) / 2 + (b - a) * node / 2)))
                }
            }
            return total
        }
        let limit: Double
        switch domain {
        case .unbounded: limit = Double.greatestFiniteMagnitude
        case let .periodic(period): limit = period
        case let .closed(lower, upper): limit = sign > 0 ? upper - origin : origin - lower
        }
        var span = min(distance / (try speed(origin)), limit)
        guard span > 0 else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "Natural sheet extension reaches the support's finite domain boundary.")
        }
        for _ in 0..<32 {
            try invocation?.consume()
            try CurrentTaskCancellationChecker().checkCancellation()
            let error = distance - (try length(span))
            if abs(error) <= tolerance.distance {
                let endpoint = origin + sign * span
                try certifyPhysicalReach(on: surface, variesU: variesU, fixedAcross: fixedAcross,
                    from: origin, to: endpoint, distance: distance, tolerance: tolerance)
                return endpoint
            }
            let next = max(Double.leastNormalMagnitude, span + error / (try speed(origin + sign * span)))
            guard next <= limit, next.isFinite else {
                throw KernelError(phase: .geometry, code: .topologyFailure, tolerance: tolerance,
                    message: "Natural extension distance exceeds the original surface support domain.")
            }
            span = next
        }
        throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
            message: "Natural sheet extension distance solve did not converge.")
    }

    func certifyPhysicalReach(on surface: Surface3D, variesU: Bool, fixedAcross: Double,
        from origin: Double, to endpoint: Double, distance: Double,
        tolerance: ModelingTolerance) throws {
        let pcurve: SurfaceParameterCurve = variesU
            ? .constantV(v: fixedAcross, uStart: origin, uEnd: endpoint)
            : .constantU(u: fixedAcross, vStart: origin, vEnd: endpoint)
        let original = Curve3D.surfaceLift(SurfaceLiftCurve3D(surface: surface, parameterCurve: pcurve))
        let bound: CurveArcLengthEnclosure
        if let invocation {
            let limits = invocation.limits
            let options = CurveArcLengthOptions(absoluteAccuracy: tolerance.distance * 0.25,
                relativeAccuracy: 0, maximumSubdivisionDepth: limits.maximumSubdivisionDepth,
                maximumIntervalCount: limits.maximumIntervalCount)
            if let sourceDepth = limits.remainingSourceDepth {
                bound = try DefaultCurveArcLengthResolver().enclosure(of: original,
                    over: ScalarInterval(lower: 0, upper: 1), options: options, tolerance: tolerance,
                    maximumSubdivisionDepth: limits.maximumSubdivisionDepth,
                    remainingSourceDepth: sourceDepth,
                    maximumAlgebraicDepth: limits.maximumAlgebraicDepth,
                    consumeWork: { try invocation.consume($0) }, consumeStorage: nil)
            } else {
                bound = try DefaultCurveArcLengthResolver().enclosure(of: original,
                    over: ScalarInterval(lower: 0, upper: 1), options: options, tolerance: tolerance,
                    maximumSubdivisionDepth: limits.maximumSubdivisionDepth,
                    consumeWork: { try invocation.consume($0) })
            }
        } else {
            bound = try DefaultCurveArcLengthResolver().enclosure(of: original,
                over: ScalarInterval(lower: 0, upper: 1),
                options: CurveArcLengthOptions(absoluteAccuracy: tolerance.distance * 0.25,
                    relativeAccuracy: 0), tolerance: tolerance)
        }
        guard abs(bound.lowerBound - distance) <= tolerance.distance,
              abs(bound.upperBound - distance) <= tolerance.distance else {
            throw KernelError(phase: .geometry, code: .topologyFailure,
                residual: max(abs(bound.lowerBound - distance), abs(bound.upperBound - distance)),
                tolerance: tolerance,
                message: "The sheet reach candidate failed whole original arclength certification.")
        }
    }
}
