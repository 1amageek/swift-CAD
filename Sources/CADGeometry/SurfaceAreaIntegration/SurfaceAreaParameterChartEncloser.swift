import CADCore

/// Invocation-owned authority for numeric trims in their exact destination chart.
package struct SurfaceAreaParameterChartEncloser: Sendable {
    /// A join range owns values and one-sided tangents, never higher derivatives.
    enum IntervalProof {
        case smooth(u: SurfaceIntervalJet, v: SurfaceIntervalJet)
        case valueOnly(u: OutwardScalarInterval, v: OutwardScalarInterval,
                       tangentU: OutwardScalarInterval, tangentV: OutwardScalarInterval)

        var values: (u: OutwardScalarInterval, v: OutwardScalarInterval,
                     tangentU: OutwardScalarInterval, tangentV: OutwardScalarInterval) {
            switch self {
            case .smooth(let u,let v): return (u.value,v.value,u.derivativeU,v.derivativeU)
            case .valueOnly(let u,let v,let du,let dv): return (u,v,du,dv)
            }
        }

        func unionValues(_ other: IntervalProof) -> IntervalProof {
            let a = values, b = other.values
            return .valueOnly(u:a.u.union(b.u),v:a.v.union(b.v),
                tangentU:a.tangentU.union(b.tangentU),tangentV:a.tangentV.union(b.tangentV))
        }
    }

    private indirect enum Storage: Sendable {
        case numeric(SurfaceParameterCurve)
        case affineImplicit(SurfaceAreaAffineImplicitChartEncloser)
        case nonlinearImplicit(SurfaceAreaImplicitParameterChartEncloser)
        case rigid(Storage, SurfaceParameterAffineTransform, Double, Double)
        case translated(Storage, Double, Double)
    }

    package let curve: SurfaceParameterCurve
    package let support: Surface3D
    private let storage: Storage
    /// Structural identity only; partial fractions are evaluated by the original chain rule.
    package let exactIsoBoundary: SurfaceParameterCurve?

    /// Routes native chart joins to the query's existing aggregate uncertainty owner.
    package var hasNativeJoins: Bool { Self.hasNativeJoins(storage) }

    package var requiresCallerWork: Bool { Self.requiresCallerWork(storage) }

    private static func requiresCallerWork(_ storage: Storage) -> Bool {
        switch storage {
        case .nonlinearImplicit: return true
        case .rigid(let child,_,_,_), .translated(let child,_,_): return requiresCallerWork(child)
        case .numeric, .affineImplicit: return false
        }
    }

    /// Legacy numeric callers require no localization work; nonlinear callers must bind an owner.
    package static func requireCallerWork() throws {
        throw KernelError(phase: .geometry, code: .invalidInput, tolerance: nil,
            message: "Nonlinear implicit area charts require a caller-owned work budget.")
    }

    private static func hasNativeJoins(_ storage: Storage) -> Bool {
        switch storage {
        case .affineImplicit(let prepared): return prepared.hasNativeJoins
        case .rigid(let child,_,_,_), .translated(let child,_,_): return hasNativeJoins(child)
        case .numeric, .nonlinearImplicit: return false
        }
    }

    package init(curve: SurfaceParameterCurve, on surface: Surface3D,
                 maximumControlPointCount: Int = 65_536, maximumBoundaryCurveCount: Int = 4_096,
                 tolerance: ModelingTolerance,
                 consumeWork: () throws -> Void = SurfaceAreaParameterChartEncloser.requireCallerWork) throws {
        try Self.validateAdmission(curve: curve, on: surface,
            maximumControlPointCount: maximumControlPointCount,
            maximumBoundaryCurveCount: maximumBoundaryCurveCount, tolerance: tolerance)
        self.curve = curve
        support = surface
        let prepared = try Self.prepare(curve, tolerance: tolerance, consumeWork: consumeWork)
        storage = prepared.storage
        exactIsoBoundary = prepared.iso
    }

    /// All nested dimensions are checked before recursive validation or transform allocation.
    package static func validateAdmission(curve: SurfaceParameterCurve, on surface: Surface3D,
                                          maximumControlPointCount: Int, maximumBoundaryCurveCount: Int,
                                          sourceDepth: Int = 0,
                                          tolerance: ModelingTolerance) throws {
        guard maximumControlPointCount > 0, maximumControlPointCount <= 1_048_576,
              maximumBoundaryCurveCount > 0, maximumBoundaryCurveCount <= 65_536, sourceDepth >= 0 else {
            throw failure(.invalidInput, tolerance, "Area chart admission limits are invalid.")
        }
        try preflight(surface, controls: maximumControlPointCount,
            boundaries: maximumBoundaryCurveCount, depth: sourceDepth, tolerance: tolerance)
        try preflight(curve, controls: maximumControlPointCount,
            boundaries: maximumBoundaryCurveCount, depth: sourceDepth, tolerance: tolerance)
        try validateImplicitIdentity(curve,on:surface,tolerance:tolerance)
        try curve.validate(on: surface, tolerance: tolerance)
    }

    private static func validateImplicitIdentity(_ curve: SurfaceParameterCurve, on surface: Surface3D,
                                                tolerance: ModelingTolerance) throws {
        switch curve {
        case .certifiedImplicit(let implicit):
            let expected = implicit.role == .first ? implicit.intersection.firstSurface : implicit.intersection.secondSurface
            guard surface == expected else {
                throw failure(.invalidInput,tolerance,"Area implicit chart must retain its exact selected source support.")
            }
        case .rigidImage(let image):
            try validateImplicitIdentity(image.source.parameterCurve,on:image.source.surface,tolerance:tolerance)
        case .offsetSurfaceImage(let image):
            try validateImplicitIdentity(image.source,on:image.offset.source,tolerance:tolerance)
        case .periodicTranslation(let base,_,_):
            try validateImplicitIdentity(base,on:surface,tolerance:tolerance)
        default: break
        }
    }

    func intervalJet(over fraction: ScalarInterval, tolerance: ModelingTolerance,
                     consumeWork: () throws -> Void = SurfaceAreaParameterChartEncloser.requireCallerWork)
        throws -> (u: SurfaceIntervalJet, v: SurfaceIntervalJet) {
        switch try intervalProof(over:fraction,tolerance:tolerance,consumeWork:consumeWork) {
        case .smooth(let u,let v): return (u,v)
        case .valueOnly:
            throw Self.failure(.unsupportedCapability,tolerance,"A native chart join has no smooth interval jet authority.")
        }
    }

    func intervalProof(over fraction: ScalarInterval, tolerance: ModelingTolerance,
                       consumeWork: () throws -> Void = SurfaceAreaParameterChartEncloser.requireCallerWork) throws -> IntervalProof {
        guard fraction.lower >= 0, fraction.upper <= 1 else {
            throw Self.failure(.invalidInput, tolerance, "Area chart enclosure requires its original normalized interval.")
        }
        return try Self.enclose(storage, over: fraction, tolerance: tolerance, consumeWork: consumeWork)
    }

    /// Reuses the same owner's certified midpoint to restrict its whole smooth range.
    func centeredIntervalJets(over fraction: ScalarInterval, tolerance: ModelingTolerance,
        consumeWork: () throws -> Void = SurfaceAreaParameterChartEncloser.requireCallerWork)
        throws -> (range: (u: SurfaceIntervalJet, v: SurfaceIntervalJet),
                   midpoint: (u: SurfaceIntervalJet, v: SurfaceIntervalJet)) {
        let range = try intervalJet(over: fraction, tolerance: tolerance, consumeWork: consumeWork)
        let center = fraction.midpoint
        let midpoint = try intervalJet(over: ScalarInterval(lower: center, upper: center),
            tolerance: tolerance, consumeWork: consumeWork)
        let delta = OutwardScalarInterval(lower: fraction.lower, upper: fraction.upper) - .exact(center)
        let square = delta * delta
        let cube = square * delta
        func intersect(_ original: OutwardScalarInterval, _ restriction: OutwardScalarInterval)
            throws -> OutwardScalarInterval {
            guard restriction.isFinite, let result = original.intersection(with: restriction) else {
                throw Self.failure(.classificationFailure, tolerance,
                    "A centered chart derivative contradicts its original smooth range proof.")
            }
            return result
        }
        func tighten(_ whole: SurfaceIntervalJet, _ point: SurfaceIntervalJet) throws -> SurfaceIntervalJet {
            let third = whole.thirdDerivativeUUU
            let second = try intersect(whole.secondDerivativeUU,
                point.secondDerivativeUU + third * delta)
            let first = try intersect(whole.derivativeU,
                point.derivativeU + point.secondDerivativeUU * delta + third * square * .exact(0.5))
            let value = try intersect(whole.value, point.value + point.derivativeU * delta
                + point.secondDerivativeUU * square * .exact(0.5) + third * cube * OutwardScalarInterval(1.0 / 6))
            return SurfaceIntervalJet(value: value, derivativeU: first, derivativeV: whole.derivativeV,
                secondDerivativeUU: second, secondDerivativeUV: whole.secondDerivativeUV,
                secondDerivativeVV: whole.secondDerivativeVV,
                thirdDerivativeUUU: third, thirdDerivativeUUV: whole.thirdDerivativeUUV,
                thirdDerivativeUVV: whole.thirdDerivativeUVV, thirdDerivativeVVV: whole.thirdDerivativeVVV)
        }
        return try ((tighten(range.u, midpoint.u), tighten(range.v, midpoint.v)), midpoint)
    }

    /// Coarse signed flux allocates effort only; final moment intervals own acceptance.
    package func signedFluxBounds(over fraction: ScalarInterval, tolerance: ModelingTolerance,
                                  consumeWork: () throws -> Void) throws -> OutwardScalarInterval {
        let proof = try intervalProof(over: fraction, tolerance: tolerance, consumeWork: consumeWork).values
        let flux = proof.u * proof.tangentV
        guard flux.isFinite else {
            throw Self.failure(.classificationFailure, tolerance, "Area effort flux exceeded finite chart arithmetic.")
        }
        return flux
    }

    /// Closed original endpoints are root proofs, not numerical parameter solves.
    package func endpointBounds(atEnd: Bool, tolerance: ModelingTolerance,
                                consumeWork: () throws -> Void) throws -> (u: ScalarInterval, v: ScalarInterval) {
        let fraction = atEnd ? 1.0 : 0.0
        let values: (u: OutwardScalarInterval, v: OutwardScalarInterval,
                     tangentU: OutwardScalarInterval, tangentV: OutwardScalarInterval)
        do {
            values = try intervalProof(over:ScalarInterval(lower:fraction,upper:fraction),
                tolerance:tolerance,consumeWork:consumeWork).values
        } catch is SurfaceAreaEnclosureRefinementRequired {
            throw Self.failure(.classificationFailure,tolerance,"An original closed trim endpoint has no resolved root enclosure.")
        }
        guard values.u.isFinite,values.v.isFinite else {
            throw Self.failure(.classificationFailure,tolerance,"An original closed trim endpoint has nonfinite chart bounds.")
        }
        return try (ScalarInterval(lower:values.u.lower,upper:values.u.upper),
                    ScalarInterval(lower:values.v.lower,upper:values.v.upper))
    }

    private static func prepare(_ curve: SurfaceParameterCurve, tolerance: ModelingTolerance,
                                consumeWork: () throws -> Void)
        throws -> (storage: Storage, iso: SurfaceParameterCurve?) {
        switch curve {
        case .affine, .harmonic, .bSpline:
            return (.numeric(curve), nil)
        case .constantU, .constantV:
            return (.numeric(curve), curve)
        case .certifiedImplicit(let implicit):
            if case .bSpline(let first) = implicit.intersection.firstSurface,
               case .bSpline(let second) = implicit.intersection.secondSurface,
               ExactAffineBSplineSurfacePatch(first) != nil, ExactAffineBSplineSurfacePatch(second) != nil {
                return (.affineImplicit(try SurfaceAreaAffineImplicitChartEncloser(curve:implicit,tolerance:tolerance)),nil)
            }
            return (.nonlinearImplicit(try SurfaceAreaImplicitParameterChartEncloser(curve:implicit,
                tolerance:tolerance,consumeWork:consumeWork)),nil)
        case .offsetSurfaceImage(let image):
            return try prepare(image.source, tolerance: tolerance, consumeWork: consumeWork)
        case .periodicTranslation(let base, let u, let v):
            let child = try prepare(base, tolerance: tolerance, consumeWork: consumeWork)
            return (.translated(child.storage, u, v), nil)
        case .rigidImage(let image):
            // FIXME(INCOMPLETE_IMPLEMENTATION): Non-affine spherical rigid-image charts lack
            // whole-interval jets on the production face-area path. Complete only after
            // the original spherical chart and integral/error fixtures are certified.
            guard let mapping = try image.affineParameterTransform(tolerance: tolerance) else {
                throw failure(.unsupportedCapability, tolerance, "Area chart requires an affine rigid parameter map.")
            }
            let child = try prepare(image.source.parameterCurve, tolerance: tolerance, consumeWork: consumeWork)
            let iso: SurfaceParameterCurve?
            if mapping == .identity, image.startFraction == 0, image.endFraction == 1 {
                iso = child.iso
            } else if mapping == .identity, image.startFraction == 1, image.endFraction == 0,
                      let boundary = child.iso {
                switch boundary {
                case .constantU(let u,let start,let end): iso = .constantU(u:u,vStart:end,vEnd:start)
                case .constantV(let v,let start,let end): iso = .constantV(v:v,uStart:end,uEnd:start)
                default: iso = nil
                }
            } else { iso = nil }
            return (.rigid(child.storage, mapping, image.startFraction, image.endFraction), iso)
        default:
            // FIXME(INCOMPLETE_IMPLEMENTATION): Projected and unsplit piecewise source charts lack
            // integral-specific jets on production face-area/centroid queries. Complete only
            // after their full original chart derivatives and integral/error fixtures certify.
            throw failure(.unsupportedCapability, tolerance, "Area chart has no certified numeric source derivatives.")
        }
    }

    private static func enclose(_ storage: Storage, over fraction: ScalarInterval,
                                tolerance: ModelingTolerance, consumeWork: () throws -> Void) throws -> IntervalProof {
        switch storage {
        case .affineImplicit(let prepared):
            return try prepared.intervalProof(over:fraction,tolerance:tolerance)
        case .nonlinearImplicit(let prepared):
            return try prepared.intervalProof(over:fraction,tolerance:tolerance,consumeWork:consumeWork)
        case .numeric(let curve):
            guard let jet = try SurfaceParameterIntervalJet.enclose(curve, over: fraction, tolerance: tolerance) else {
                throw failure(.unsupportedCapability, tolerance, "Admitted area chart lost its numeric interval derivatives.")
            }
            return .smooth(u:jet.u,v:jet.v)
        case .translated(let child, let u, let v):
            switch try enclose(child, over:fraction,tolerance:tolerance,consumeWork:consumeWork) {
            case .smooth(let x,let y): return .smooth(u:x + .constant(u),v:y + .constant(v))
            case .valueOnly(let x,let y,let dx,let dy):
                return .valueOnly(u:x + .exact(u),v:y + .exact(v),tangentU:dx,tangentV:dy)
            }
        case .rigid(let child, let map, let start, let end):
            if map == .identity, start == 0, end == 1 {
                // Exact identity composition preserves every original interval
                // and derivative order without another arithmetic enclosure.
                return try enclose(child,over:fraction,tolerance:tolerance,consumeWork:consumeWork)
            }
            let parameter = SurfaceIntervalJet.constant(start)
                + (.constant(end) - .constant(start)) * .parameterU(fraction)
            // Admission proves the exact affine fraction lies in [0,1]. Intersecting
            // outward rounding with that proven range does not clamp an invalid source.
            let range: ScalarInterval
            if fraction.lower == fraction.upper, fraction.lower == 0 || fraction.lower == 1 {
                let endpoint = fraction.lower == 0 ? start : end
                range = try ScalarInterval(lower:endpoint,upper:endpoint)
            } else {
                range = try ScalarInterval(lower: max(0, parameter.value.lower), upper: min(1, parameter.value.upper))
            }
            let source = try enclose(child, over: range, tolerance: tolerance, consumeWork: consumeWork)
            if case .valueOnly(let u,let v,let du,let dv) = source {
                let slope = OutwardScalarInterval.exact(end) - .exact(start)
                return .valueOnly(u:u * .exact(map.uu) + v * .exact(map.uv) + .exact(map.uOffset),
                    v:u * .exact(map.vu) + v * .exact(map.vv) + .exact(map.vOffset),
                    tangentU:(du * .exact(map.uu) + dv * .exact(map.uv))*slope,
                    tangentV:(du * .exact(map.vu) + dv * .exact(map.vv))*slope)
            }
            guard case .smooth(let sourceU,let sourceV) = source else {
                throw failure(.classificationFailure,tolerance,"An area chart lost its interval proof kind.")
            }
            let composed = SurfaceParameterThirdOrderChainRule.intervalJet(
                surface: SurfaceIntervalVectorJet(x: sourceU, y: sourceV, z: .constant(0)),
                u: parameter, v: .constant(0))
            return .smooth(u:composed.x * .constant(map.uu) + composed.y * .constant(map.uv) + .constant(map.uOffset),
                           v:composed.x * .constant(map.vu) + composed.y * .constant(map.vv) + .constant(map.vOffset))
        }
    }

    private static func checkDepth(_ depth: Int, _ tolerance: ModelingTolerance) throws {
        guard depth <= 16 else { throw failure(.resourceLimitExceeded, tolerance, "Area chart source nesting limit exceeded.") }
        if Task.isCancelled { throw failure(.cancelled, tolerance, "Area chart preparation was cancelled.") }
    }

    private static func splineDimensions(controls: Int, degree: Int, knots: Int, weights: Int,
                                         limit: Int, tolerance: ModelingTolerance) throws {
        guard controls <= limit, weights <= limit, knots <= 2 * limit + 1 else {
            throw failure(.resourceLimitExceeded, tolerance, "Area chart spline dimension limit exceeded.")
        }
        guard degree >= 1, degree < controls, knots == controls + degree + 1, weights == controls else {
            throw failure(.invalidInput, tolerance, "Area chart spline dimensions are inconsistent.")
        }
    }

    private static func preflight(_ curve: SurfaceParameterCurve, controls: Int, boundaries: Int,
                                   depth: Int, tolerance: ModelingTolerance) throws {
        try checkDepth(depth, tolerance)
        switch curve {
        case .affine, .constantU, .constantV, .harmonic: break
        case .polyline(let points):
            guard points.count <= boundaries else { throw failure(.resourceLimitExceeded, tolerance, "Area chart polyline limit exceeded.") }
        case .bSpline(let spline):
            try splineDimensions(controls: spline.controlPoints.count, degree: spline.degree,
                knots: spline.knots.count, weights: spline.weights.count, limit: controls, tolerance: tolerance)
            let lower = spline.knots[spline.degree], upper = spline.knots[spline.controlPoints.count]
            guard spline.knots.allSatisfy(\.isFinite), lower < upper,
                  spline.knots.indices.dropFirst().allSatisfy({ spline.knots[$0 - 1] <= spline.knots[$0] }) else {
                throw failure(.invalidInput,tolerance,"Area chart spline knots require a finite ordered native domain.")
            }
            var index = 0
            while index < spline.knots.count {
                let knot = spline.knots[index]
                var end = index + 1
                while end < spline.knots.count && spline.knots[end] == knot { end += 1 }
                // FIXME(INCOMPLETE_IMPLEMENTATION): Non-C2 numeric trim knots need piecewise
                // original-chart derivative authority on production face-area queries. Complete
                // only after trim-span partitioning preserves every fan and certified moment.
                guard knot <= lower || knot >= upper || spline.degree - (end - index) >= 2 else {
                    throw failure(.unsupportedCapability, tolerance, "Area fan trim derivatives require C2 across interior knots.")
                }
                index = end
            }
        case .periodicTranslation(let base, _, _):
            try preflight(base, controls: controls, boundaries: boundaries, depth: depth + 1, tolerance: tolerance)
        case .offsetSurfaceImage(let image):
            try preflight(.procedural(.offset(image.offset)), controls: controls, boundaries: boundaries,
                depth: depth + 1, tolerance: tolerance)
            try preflight(image.source, controls: controls, boundaries: boundaries, depth: depth + 1, tolerance: tolerance)
        case .rigidImage(let image):
            guard image.startFraction.isFinite, image.endFraction.isFinite,
                  image.startFraction >= 0, image.startFraction <= 1,
                  image.endFraction >= 0, image.endFraction <= 1, image.startFraction != image.endFraction else {
                throw failure(.invalidInput, tolerance, "Area rigid chart fractions must stay inside the original source interval.")
            }
            try preflight(image.source.surface, controls: controls, boundaries: boundaries, depth: depth + 1, tolerance: tolerance)
            try preflight(image.targetSurface, controls: controls, boundaries: boundaries, depth: depth + 1, tolerance: tolerance)
            try preflight(image.source.parameterCurve, controls: controls, boundaries: boundaries, depth: depth + 1, tolerance: tolerance)
        case .certifiedImplicit(let implicit):
            guard implicit.startFraction.isFinite, implicit.endFraction.isFinite,
                  implicit.startFraction >= 0, implicit.startFraction <= 1,
                  implicit.endFraction >= 0, implicit.endFraction <= 1,
                  implicit.startFraction != implicit.endFraction else {
                throw failure(.invalidInput,tolerance,"Area affine implicit fractions must retain their original [0,1] chart.")
            }
            guard implicit.intersection.cells.count <= boundaries else {
                throw failure(.resourceLimitExceeded,tolerance,"Area implicit graph cell admission limit exceeded.")
            }
            try preflight(implicit.intersection.firstSurface,controls:controls,boundaries:boundaries,
                depth:depth+1,tolerance:tolerance)
            try preflight(implicit.intersection.secondSurface,controls:controls,boundaries:boundaries,
                depth:depth+1,tolerance:tolerance)
        default:
            // FIXME(INCOMPLETE_IMPLEMENTATION): Remaining non-numeric source charts have no bounded
            // derivative admission for production face-area queries. Complete only after
            // whole-chart integral authority and success/failure fixtures are implemented.
            throw failure(.unsupportedCapability, tolerance, "Area chart source is not an admitted numeric chart.")
        }
    }

    private static func preflight(_ surface: Surface3D, controls: Int, boundaries: Int,
                                   depth: Int, tolerance: ModelingTolerance) throws {
        try checkDepth(depth, tolerance)
        switch surface {
        case .bSpline(let spline):
            let uCount = spline.controlPoints.first?.count ?? 0, vCount = spline.controlPoints.count
            guard vCount <= controls, spline.controlPoints.allSatisfy({ $0.count <= controls }),
                  spline.weights.count <= controls, spline.weights.allSatisfy({ $0.count <= controls }) else {
                throw failure(.resourceLimitExceeded, tolerance, "Area chart support dimensions exceed admission.")
            }
            try splineDimensions(controls: uCount, degree: spline.uDegree, knots: spline.uKnots.count,
                weights: uCount, limit: controls, tolerance: tolerance)
            try splineDimensions(controls: vCount, degree: spline.vDegree, knots: spline.vKnots.count,
                weights: spline.weights.count, limit: controls, tolerance: tolerance)
            guard spline.controlPoints.allSatisfy({ $0.count == uCount }), spline.weights.allSatisfy({ $0.count == uCount }) else {
                throw failure(.invalidInput, tolerance, "Area chart support has inconsistent row dimensions.")
            }
            guard uCount <= controls / vCount else { throw failure(.resourceLimitExceeded, tolerance, "Area chart support control limit exceeded.") }
            var expanded = 1
            for factor in [uCount - spline.uDegree, vCount - spline.vDegree, spline.uDegree + 1, spline.vDegree + 1] {
                guard factor <= controls / expanded else { throw failure(.resourceLimitExceeded, tolerance, "Area chart Bezier preparation limit exceeded.") }
                expanded *= factor
            }
        case .procedural(.offset(let offset)):
            try preflight(offset.source, controls: controls, boundaries: boundaries, depth: depth + 1, tolerance: tolerance)
        case .procedural(.ruled(let ruled)):
            try preflight(ruled.startBoundary, controls: controls, boundaries: boundaries, depth: depth + 1, tolerance: tolerance)
            try preflight(ruled.endBoundary, controls: controls, boundaries: boundaries, depth: depth + 1, tolerance: tolerance)
        case .procedural(.rollingBall(let blend)):
            for rail in [blend.centerSpine, blend.firstContact, blend.secondContact] {
                try preflight(rail, controls: controls, boundaries: boundaries, depth: depth + 1, tolerance: tolerance)
            }
        default: break
        }
    }

    private static func preflight(_ curve: Curve3D, controls: Int, boundaries: Int,
                                   depth: Int, tolerance: ModelingTolerance) throws {
        try checkDepth(depth, tolerance)
        switch curve {
        case .line, .circle: break
        case .analytic(let analytic):
            if case .planeTorus(let intersection) = analytic {
                try preflight(intersection.planeSurface, controls:controls,boundaries:boundaries,
                    depth:depth+1,tolerance:tolerance)
                try preflight(intersection.torusSurface, controls:controls,boundaries:boundaries,
                    depth:depth+1,tolerance:tolerance)
            }
        case .bSpline(let spline):
            try splineDimensions(controls: spline.controlPoints.count, degree: spline.degree,
                knots: spline.knots.count, weights: spline.weights.count, limit: controls, tolerance: tolerance)
        case .surfaceLift(let lift):
            try preflight(lift.surface, controls: controls, boundaries: boundaries, depth: depth + 1, tolerance: tolerance)
            try preflight(lift.parameterCurve, controls: controls, boundaries: boundaries, depth: depth + 1, tolerance: tolerance)
        case .rigidImage(let image):
            try preflight(image.source, controls: controls, boundaries: boundaries, depth: depth + 1, tolerance: tolerance)
        case .affineImage(let image):
            try preflight(image.source, controls: controls, boundaries: boundaries, depth: depth + 1, tolerance: tolerance)
        default:
            // FIXME(INCOMPLETE_IMPLEMENTATION): Certified implicit source rails lack bounded
            // mapped-chart admission on production face-area queries. Complete only when
            // their input graph and full original derivative chart are certified for integration.
            throw failure(.unsupportedCapability, tolerance, "Area mapped source has no bounded curve admission.")
        }
    }

    private static func failure(_ code: KernelErrorCode, _ tolerance: ModelingTolerance, _ message: String) -> KernelError {
        KernelError(phase: .geometry, code: code, tolerance: tolerance, message: message)
    }
}
