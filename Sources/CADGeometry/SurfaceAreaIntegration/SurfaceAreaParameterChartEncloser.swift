import CADCore

/// Invocation-owned authority for numeric trims in their exact destination chart.
package struct SurfaceAreaParameterChartEncloser: Sendable {
    /// An original boundary image, separate from a replacement parameter curve.
    package struct IsoBoundaryImage: Sendable {
        package let axis: SurfaceAreaTranslationCertificate
        package let fixedParameter: Double
        package let start: (u: ScalarInterval, v: ScalarInterval)
        package let end: (u: ScalarInterval, v: ScalarInterval)
        private let curve: SurfaceParameterCurve
        private let support: Surface3D
        private let tolerance: ModelingTolerance
        private let root: ImplicitCurveIntervalJetEncloser.ParameterEnclosureState
        private let monotoneDerivative: OutwardScalarInterval

        fileprivate init(axis: SurfaceAreaTranslationCertificate, fixedParameter: Double,
            start: (u: ScalarInterval, v: ScalarInterval), end: (u: ScalarInterval, v: ScalarInterval),
            chart: SurfaceAreaParameterChartEncloser, tolerance: ModelingTolerance,
            root: ImplicitCurveIntervalJetEncloser.ParameterEnclosureState,
            monotoneDerivative: OutwardScalarInterval) {
            self.axis = axis
            self.fixedParameter = fixedParameter
            self.start = start
            self.end = end
            curve = chart.curve
            support = chart.support
            self.tolerance = tolerance
            self.root = root
            self.monotoneDerivative = monotoneDerivative
        }

        package func validate(for chart: SurfaceAreaParameterChartEncloser,
            on surface: Surface3D, tolerance: ModelingTolerance) throws {
            guard curve == chart.curve, support == chart.support, support == surface,
                  self.tolerance == tolerance,monotoneDerivative.isFinite,
                  monotoneDerivative.lower > 0 || monotoneDerivative.upper < 0 else {
                throw SurfaceAreaParameterChartEncloser.failure(.invalidInput,tolerance,
                    "An original iso-image receipt belongs to another source chart, support or tolerance.")
            }
        }
    }

    /// A join range owns values and one-sided tangents, never higher derivatives.
    package enum IntervalProof {
        case smooth(u: SurfaceIntervalJet, v: SurfaceIntervalJet)
        case valueOnly(u: OutwardScalarInterval, v: OutwardScalarInterval,
                       tangentU: OutwardScalarInterval, tangentV: OutwardScalarInterval)

        package var values: (u: OutwardScalarInterval, v: OutwardScalarInterval,
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

    private struct OriginalQueryPolicy: Sendable {
        let maximumSubdivisionDepth: Int
        let remainingSourceDepth: Int
        let maximumAlgebraicDepth: Int
    }

    private indirect enum Storage: Sendable {
        case originalHigher(SurfaceParameterCurve, OriginalQueryPolicy)
        case originalImage(Storage, OriginalImageSurfaceParameterCurve, OriginalQueryPolicy?)
        case numeric(SurfaceParameterCurve)
        case originalContinuation(OriginalBSplineCurve2DContinuation, OriginalBSplineCurve2DContinuationSource)
        case nativeNumeric(SurfaceAreaNativeNumericChartEncloser)
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
        case .nonlinearImplicit, .nativeNumeric, .originalContinuation: return true
        case .originalImage(let child,_,_), .rigid(let child,_,_,_), .translated(let child,_,_): return requiresCallerWork(child)
        case .numeric, .affineImplicit: return false
        case .originalHigher: return true
        }
    }

    /// Prepared native numeric and nonlinear callers must bind the original work owner.
    package static func requireCallerWork() throws {
        throw KernelError(phase: .geometry, code: .invalidInput, tolerance: nil,
            message: "Prepared original area charts require a caller-owned work budget.")
    }

    private static func hasNativeJoins(_ storage: Storage) -> Bool {
        switch storage {
        case .affineImplicit(let prepared): return prepared.hasNativeJoins
        case .originalImage(let child,_,_), .rigid(let child,_,_,_), .translated(let child,_,_): return hasNativeJoins(child)
        case .nonlinearImplicit(let prepared): return prepared.hasNativeJoins
        case .originalContinuation: return true
        case .numeric: return false
        case .originalHigher(let curve,_):
            switch curve { case .originalBSplineContinuation,.polyline: return true; default: return false }
        case .nativeNumeric: return true
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

    package init(curve: SurfaceParameterCurve, on surface: Surface3D,
        maximumControlPointCount: Int = 65_536, maximumBoundaryCurveCount: Int = 4_096,
        tolerance: ModelingTolerance, maximumSubdivisionDepth: Int,
        remainingSourceDepth: Int, maximumAlgebraicDepth: Int,
        consumeWork: (Int) throws -> Void,
        consumeStorage: ((Int) throws -> Void)? = nil) throws {
        guard maximumSubdivisionDepth >= 0, (0...16).contains(remainingSourceDepth),
            (0...32).contains(maximumAlgebraicDepth), maximumControlPointCount > 0,
            maximumControlPointCount <= 1_048_576, maximumBoundaryCurveCount > 0,
            maximumBoundaryCurveCount <= 65_536 else {
            throw Self.failure(.invalidInput,tolerance,"Original area chart policy is invalid.")
        }
        try curve.validateOriginalSource(on:surface,tolerance:tolerance,
            remainingSourceDepth:remainingSourceDepth,maximumSubdivisionDepth:maximumSubdivisionDepth,
            consumeWork:consumeWork,consumeStorage:consumeStorage,maximumAlgebraicDepth:maximumAlgebraicDepth)
        try Self.preflight(surface,controls:maximumControlPointCount,boundaries:maximumBoundaryCurveCount,
            depth:0,tolerance:tolerance,consumeWork:{ try consumeWork(0) })
        try Self.preflight(curve,controls:maximumControlPointCount,boundaries:maximumBoundaryCurveCount,
            depth:0,tolerance:tolerance,consumeWork:{ try consumeWork(0) })
        let policy = OriginalQueryPolicy(maximumSubdivisionDepth:maximumSubdivisionDepth,
            remainingSourceDepth:remainingSourceDepth,maximumAlgebraicDepth:maximumAlgebraicDepth)
        self.curve = curve; support = surface
        let prepared = try Self.prepareOriginal(curve,policy:policy,
            maximumControlPointCount:maximumControlPointCount,maximumBoundaryCurveCount:maximumBoundaryCurveCount,
            tolerance:tolerance,consumeWork:{ try consumeWork(0) },consumeStorage:consumeStorage)
        storage = prepared.storage; exactIsoBoundary = prepared.iso
    }

    private static func prepareOriginal(_ curve: SurfaceParameterCurve, policy: OriginalQueryPolicy,
        maximumControlPointCount: Int, maximumBoundaryCurveCount: Int,
        tolerance: ModelingTolerance, consumeWork: () throws -> Void,
        consumeStorage: ((Int) throws -> Void)?) throws -> (storage:Storage,iso:SurfaceParameterCurve?) {
        try consumeWork()
        func childPolicy() throws -> OriginalQueryPolicy {
            guard policy.remainingSourceDepth > 0 else {
                throw failure(.resourceLimitExceeded,tolerance,"Original area child exhausted source depth.")
            }
            return OriginalQueryPolicy(maximumSubdivisionDepth:policy.maximumSubdivisionDepth,
                remainingSourceDepth:policy.remainingSourceDepth-1,maximumAlgebraicDepth:policy.maximumAlgebraicDepth)
        }
        switch curve {
        case .bSpline(let spline):
            try splineDimensions(controls:spline.controlPointCount,degree:spline.degree,
                knots:spline.knots.count,weights:spline.weights.count,limit:maximumControlPointCount,tolerance:tolerance)
            return (.nativeNumeric(try SurfaceAreaNativeNumericChartEncloser(curve:spline,
                tolerance:tolerance,consumeWork:consumeWork,consumeStorage:consumeStorage)),nil)
        case .affine, .harmonic, .constantU, .constantV, .originalBSplineContinuation:
            let iso:SurfaceParameterCurve?
            switch curve { case .constantU,.constantV: iso = curve; default: iso = nil }
            return (.originalHigher(curve,policy),iso)
        case .polyline(let values):
            guard values.count <= maximumBoundaryCurveCount else {
                throw failure(.resourceLimitExceeded,tolerance,"Original area chart boundary count exceeds admission.")
            }
            return (.originalHigher(curve,policy),nil)
        case .originalImage(let image):
            let child = try prepareOriginal(image.source.parameterCurve,policy:try childPolicy(),
                maximumControlPointCount:maximumControlPointCount,maximumBoundaryCurveCount:maximumBoundaryCurveCount,
                tolerance:tolerance,consumeWork:consumeWork,consumeStorage:consumeStorage)
            return (.originalImage(child.storage,image,policy),nil)
        case .originalAffineWord(let image):
            let child = try prepareOriginal(image.source.parameterCurve,policy:try childPolicy(),
                maximumControlPointCount:maximumControlPointCount,maximumBoundaryCurveCount:maximumBoundaryCurveCount,
                tolerance:tolerance,consumeWork:consumeWork,consumeStorage:consumeStorage)
            return (.rigid(child.storage,.identity,image.startFraction,image.endFraction),nil)
        case .periodicTranslation(let source,let u,let v):
            let child = try prepareOriginal(source,policy:try childPolicy(),
                maximumControlPointCount:maximumControlPointCount,maximumBoundaryCurveCount:maximumBoundaryCurveCount,
                tolerance:tolerance,consumeWork:consumeWork,consumeStorage:consumeStorage)
            return (.translated(child.storage,u,v),nil)
        case .offsetSurfaceImage(let image):
            return try prepareOriginal(image.source,policy:try childPolicy(),
                maximumControlPointCount:maximumControlPointCount,maximumBoundaryCurveCount:maximumBoundaryCurveCount,
                tolerance:tolerance,consumeWork:consumeWork,consumeStorage:consumeStorage)
        case .certifiedImplicit(let implicit):
            guard implicit.intersection.cells.count <= maximumBoundaryCurveCount else {
                throw failure(.resourceLimitExceeded,tolerance,"Original area root-cell count exceeds admission.")
            }
            if case .bSpline(let first) = implicit.intersection.firstSurface,
                case .bSpline(let second) = implicit.intersection.secondSurface,
                ExactAffineBSplineSurfacePatch(first) != nil, ExactAffineBSplineSurfacePatch(second) != nil {
                return (.affineImplicit(try SurfaceAreaAffineImplicitChartEncloser(curve:implicit,
                    tolerance:tolerance,consumeWork:consumeWork,consumeStorage:consumeStorage)),nil)
            }
            return (.nonlinearImplicit(try SurfaceAreaImplicitParameterChartEncloser(curve:implicit,
                tolerance:tolerance,consumeWork:consumeWork,maximumSubdivisionDepth:policy.maximumSubdivisionDepth,
                remainingSourceDepth:policy.remainingSourceDepth,maximumAlgebraicDepth:policy.maximumAlgebraicDepth,
                consumeStorage:consumeStorage)),nil)
        default:
            // FIXME(INCOMPLETE_IMPLEMENTATION): Bounded integral chart preparation
            // still needs the retained implicit/inverse root owners' complete source,
            // depth and BYTE callbacks. Public UV area and volume consumers must not
            // treat legacy preparation as a bounded original chart receipt.
            throw failure(.unsupportedCapability,tolerance,"Original area chart family requires its bounded preparation owner.")
        }
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
        case .originalAffineWord(let image):
            try validateImplicitIdentity(image.source.parameterCurve, on: image.source.surface, tolerance: tolerance)
        case .originalImage(let image):
            try validateImplicitIdentity(image.source.parameterCurve,on:image.source.surface,tolerance:tolerance)
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
                     consumeWork: () throws -> Void = SurfaceAreaParameterChartEncloser.requireCallerWork,
                     consumeStorage: ((Int) throws -> Void)? = nil)
        throws -> (u: SurfaceIntervalJet, v: SurfaceIntervalJet) {
        switch try intervalProof(over:fraction,tolerance:tolerance,consumeWork:consumeWork,consumeStorage:consumeStorage) {
        case .smooth(let u,let v): return (u,v)
        case .valueOnly:
            throw Self.failure(.unsupportedCapability,tolerance,"A native chart join has no smooth interval jet authority.")
        }
    }

    package func intervalProof(over fraction: ScalarInterval, tolerance: ModelingTolerance,
                       consumeWork: () throws -> Void,
                     consumeStorage: ((Int) throws -> Void)? = nil) throws -> IntervalProof {
        guard fraction.lower >= 0, fraction.upper <= 1 else {
            throw Self.failure(.invalidInput, tolerance, "Area chart enclosure requires its original normalized interval.")
        }
        return try Self.enclose(storage, over: fraction, tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)
    }

    /// Reuses the same owner's certified midpoint to restrict its whole smooth range.
    func centeredIntervalJets(over fraction: ScalarInterval, tolerance: ModelingTolerance,
        consumeWork: () throws -> Void = SurfaceAreaParameterChartEncloser.requireCallerWork,
                     consumeStorage: ((Int) throws -> Void)? = nil)
        throws -> (range: (u: SurfaceIntervalJet, v: SurfaceIntervalJet),
                   midpoint: (u: SurfaceIntervalJet, v: SurfaceIntervalJet)) {
        let result = try centeredIntervalJetsRetainingRoot(over:fraction,tolerance:tolerance,consumeWork:consumeWork,consumeStorage:consumeStorage)
        return (result.range,result.midpoint)
    }

    func centeredIntervalJetsRetainingRoot(over fraction: ScalarInterval, tolerance: ModelingTolerance,
        consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil)
        throws -> (range: (u: SurfaceIntervalJet, v: SurfaceIntervalJet),
                   midpoint: (u: SurfaceIntervalJet, v: SurfaceIntervalJet),
                   root: ImplicitCurveIntervalJetEncloser.ParameterEnclosureState?) {
        let whole = try intervalProofRetainingRoot(over:fraction,tolerance:tolerance,consumeWork:consumeWork,consumeStorage:consumeStorage)
        guard case .smooth(let u,let v) = whole.proof else {
            throw Self.failure(.unsupportedCapability,tolerance,"A native chart join has no smooth retained root pair.")
        }
        let range = (u:u,v:v)
        let center = fraction.midpoint
        let point = try intervalProofRetainingRoot(over:ScalarInterval(lower:center,upper:center),
            restricting:whole.root,tolerance:tolerance,consumeWork:consumeWork,consumeStorage:consumeStorage)
        guard case .smooth(let pointU,let pointV) = point.proof else {
            throw Self.failure(.unsupportedCapability,tolerance,"A retained midpoint lost its smooth chart proof.")
        }
        let pair = try centeredRestriction(of:range,at:(pointU,pointV),over:fraction,tolerance:tolerance)
        // The point state is a subset, not authority for a sibling or grandchild.
        return (pair.range,pair.midpoint,whole.root)
    }

    /// The integrand's original parent proof owns the whole containing smooth range.
    /// This child obtains its own closed midpoint truth from the same root owner.
    func centeredIntervalJets(over fraction: ScalarInterval,
        restricting range: (u: SurfaceIntervalJet, v: SurfaceIntervalJet),
        root: ImplicitCurveIntervalJetEncloser.ParameterEnclosureState? = nil,
        tolerance: ModelingTolerance, consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil)
        throws -> (range: (u: SurfaceIntervalJet, v: SurfaceIntervalJet),
                   midpoint: (u: SurfaceIntervalJet, v: SurfaceIntervalJet)) {
        let center = fraction.midpoint
        let point = try intervalProofRetainingRoot(over:ScalarInterval(lower:center,upper:center),
            restricting:root,tolerance:tolerance,consumeWork:consumeWork,consumeStorage:consumeStorage)
        guard case .smooth(let u,let v) = point.proof else {
            throw Self.failure(.unsupportedCapability,tolerance,"An original restricted midpoint lost smooth authority.")
        }
        let midpoint = (u:u,v:v)
        return try centeredRestriction(of:range,at:midpoint,over:fraction,tolerance:tolerance)
    }

    private func centeredRestriction(of range: (u: SurfaceIntervalJet, v: SurfaceIntervalJet),
        at midpoint: (u: SurfaceIntervalJet, v: SurfaceIntervalJet), over fraction: ScalarInterval,
        tolerance: ModelingTolerance)
        throws -> (range: (u: SurfaceIntervalJet, v: SurfaceIntervalJet),
                   midpoint: (u: SurfaceIntervalJet, v: SurfaceIntervalJet)) {
        let center = fraction.midpoint
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
                                  consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil) throws -> OutwardScalarInterval {
        let proof = try intervalProof(over: fraction, tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage).values
        let flux = proof.u * proof.tangentV
        guard flux.isFinite else {
            throw Self.failure(.classificationFailure, tolerance, "Area effort flux exceeded finite chart arithmetic.")
        }
        return flux
    }

    /// Original whole-cell flux with same-owner midpoint and smooth remainder.
    package func signedFluxIntegrationBounds(over fraction: ScalarInterval,
        tolerance: ModelingTolerance, consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil) throws -> SurfaceParameterFluxIntegrationBounds {
        let original = try intervalProofRetainingRoot(over: fraction, tolerance: tolerance,
            consumeWork: consumeWork, consumeStorage: consumeStorage)
        let value = original.proof.values
        let flux = value.u * value.tangentV
        guard flux.isFinite else {
            throw Self.failure(.classificationFailure, tolerance, "Original signed flux has nonfinite value bounds.")
        }
        guard case .smooth(let u, let v) = original.proof else {
            return SurfaceParameterFluxIntegrationBounds(value: flux, midpoint: nil, secondDerivative: nil)
        }
        let center = fraction.midpoint
        let point = try intervalProofRetainingRoot(over: ScalarInterval(lower: center, upper: center),
            restricting: original.root, tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)
        guard case .smooth(let pu, let pv) = point.proof else {
            throw Self.failure(.classificationFailure, tolerance, "Original signed flux midpoint lost smooth chart authority.")
        }
        let midpoint = pu.value * pv.derivativeU
        let second = u.secondDerivativeUU * v.derivativeU
            + u.derivativeU * v.secondDerivativeUU * .exact(2)
            + u.value * v.thirdDerivativeUUU
        guard midpoint.isFinite, second.isFinite else {
            throw Self.failure(.classificationFailure, tolerance, "Original signed flux has nonfinite midpoint or derivative bounds.")
        }
        return SurfaceParameterFluxIntegrationBounds(value: flux, midpoint: midpoint, secondDerivative: second)
    }

    /// Closed original endpoints are root proofs, not numerical parameter solves.
    package func endpointBounds(atEnd: Bool, tolerance: ModelingTolerance,
                                consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil) throws -> (u: ScalarInterval, v: ScalarInterval) {
        let fraction = atEnd ? 1.0 : 0.0
        let values: (u: OutwardScalarInterval, v: OutwardScalarInterval,
                     tangentU: OutwardScalarInterval, tangentV: OutwardScalarInterval)
        do {
            values = try intervalProof(over:ScalarInterval(lower:fraction,upper:fraction),
                tolerance:tolerance,consumeWork:consumeWork,consumeStorage:consumeStorage).values
        } catch is SurfaceAreaEnclosureRefinementRequired {
            throw Self.failure(.classificationFailure,tolerance,"An original closed trim endpoint has no resolved root enclosure.")
        }
        guard values.u.isFinite,values.v.isFinite else {
            throw Self.failure(.classificationFailure,tolerance,"An original closed trim endpoint has nonfinite chart bounds.")
        }
        return try (ScalarInterval(lower:values.u.lower,upper:values.u.upper),
                    ScalarInterval(lower:values.v.lower,upper:values.v.upper))
    }

    /// Preparation and every original root phase remain charged to the query.
    /// A nonadmitted image keeps its existing fan algorithm.
    package func certifiedIsoBoundaryImage(tolerance: ModelingTolerance,
        consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil) throws -> IsoBoundaryImage? {
        guard case .bSpline(let spline) = support, !spline.isUPeriodic, !spline.isVPeriodic,
              let constant = try Self.constantAxisAuthority(storage,tolerance:tolerance,consumeWork:consumeWork,consumeStorage:consumeStorage) else { return nil }
        let whole: (proof: IntervalProof, root: ImplicitCurveIntervalJetEncloser.ParameterEnclosureState?)
        do {
            whole = try intervalProofRetainingRoot(over:ScalarInterval(lower:0,upper:1),
                tolerance:tolerance,consumeWork:consumeWork,consumeStorage:consumeStorage)
        } catch is SurfaceAreaEnclosureRefinementRequired { return nil }
        guard case .smooth(let u,let v) = whole.proof, let root = whole.root else { return nil }
        let fixed = constant.axis == .v ? v : u
        let other = constant.axis == .v ? u : v
        guard fixed.value.isFinite,other.value.isFinite,other.derivativeU.isFinite,
              fixed.value.lower <= constant.parameter, fixed.value.upper >= constant.parameter else {
            throw Self.failure(.classificationFailure,tolerance,"Original iso-image coefficients contradict their root enclosure.")
        }
        guard other.derivativeU.lower > 0 || other.derivativeU.upper < 0 else { return nil }
        let start = try endpointBounds(atEnd:false,tolerance:tolerance,consumeWork:consumeWork,consumeStorage:consumeStorage)
        let end = try endpointBounds(atEnd:true,tolerance:tolerance,consumeWork:consumeWork,consumeStorage:consumeStorage)
        for point in [start,end] {
            let coordinate = constant.axis == .v ? point.v : point.u
            guard coordinate.contains(constant.parameter) else {
                throw Self.failure(.classificationFailure,tolerance,"An original iso-image endpoint contradicts its constant-axis proof.")
            }
        }
        let first = constant.axis == .v ? start.u : start.v
        let last = constant.axis == .v ? end.u : end.v
        guard (other.derivativeU.lower > 0 && first.upper < last.lower)
            || (other.derivativeU.upper < 0 && last.upper < first.lower) else { return nil }
        return IsoBoundaryImage(axis:constant.axis,fixedParameter:constant.parameter,
            start:start,end:end,chart:self,tolerance:tolerance,root:root,
            monotoneDerivative:other.derivativeU)
    }

    private static func constantAxisAuthority(_ storage: Storage, tolerance: ModelingTolerance,
        consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil) throws -> (axis: SurfaceAreaTranslationCertificate, parameter: Double)? {
        switch storage {
        case .nonlinearImplicit(let prepared):
            return try prepared.constantAxisAuthority(tolerance:tolerance,consumeWork:consumeWork)
        case .rigid(let child,let mapping,_,_) where mapping == .identity:
            return try constantAxisAuthority(child,tolerance:tolerance,consumeWork:consumeWork,consumeStorage:consumeStorage)
        case .originalImage,.numeric,.originalHigher,.nativeNumeric,.affineImplicit,.translated,.rigid,.originalContinuation: return nil
        }
    }

    private static func chargeContinuation(_ value: OriginalBSplineCurve2DContinuation,
        consumeWork: () throws -> Void, tolerance: ModelingTolerance) throws {
        let degree = value.original.degree + 1
        let first = value.original.controlPoints.count.multipliedReportingOverflow(by: degree)
        let second = first.partialValue.multipliedReportingOverflow(by: degree)
        let third = second.partialValue.multipliedReportingOverflow(by: degree * 128)
        guard !first.overflow, !second.overflow, !third.overflow else {
            throw failure(.resourceLimitExceeded, tolerance, "Original continuation chart work dimensions overflowed.")
        }
        for _ in 0..<third.partialValue { try Task.checkCancellation(); try consumeWork() }
    }

    private static func prepare(_ curve: SurfaceParameterCurve, tolerance: ModelingTolerance,
                                consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil)
        throws -> (storage: Storage, iso: SurfaceParameterCurve?) {
        switch curve {
        case .originalAffineWord(let image):
            let child = try prepare(image.source.parameterCurve, tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)
            return (.rigid(child.storage, .identity, image.startFraction, image.endFraction), nil)
        case .originalImage(let image):
            let child = try prepare(image.source.parameterCurve, tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)
            return (.originalImage(child.storage, image,nil), nil)

        case .affine, .harmonic:
            return (.numeric(curve), nil)
        case .originalBSplineContinuation(let continuation):
            try chargeContinuation(continuation, consumeWork: consumeWork, tolerance: tolerance)
            return (.originalContinuation(continuation, try OriginalBSplineCurve2DContinuationSource(
                curve: continuation.original, tolerance: tolerance)), nil)
        case .bSpline(let spline):
            if SurfaceAreaNativeNumericChartEncloser.needsPiecewiseAuthority(spline) {
                return (.nativeNumeric(try SurfaceAreaNativeNumericChartEncloser(curve:spline,
                    tolerance:tolerance,consumeWork:consumeWork,consumeStorage:consumeStorage)),nil)
            }
            return (.numeric(curve),nil)
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
            return try prepare(image.source, tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)
        case .periodicTranslation(let base, let u, let v):
            let child = try prepare(base, tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)
            return (.translated(child.storage, u, v), nil)
        case .rigidImage(let image):
            // FIXME(INCOMPLETE_IMPLEMENTATION): Non-affine spherical rigid-image charts lack
            // whole-interval jets on the production face-area path. Complete only after
            // the original spherical chart and integral/error fixtures are certified.
            guard let mapping = try image.affineParameterTransform(tolerance: tolerance) else {
                throw failure(.unsupportedCapability, tolerance, "Area chart requires an affine rigid parameter map.")
            }
            let child = try prepare(image.source.parameterCurve, tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)
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
                                tolerance: ModelingTolerance, consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil) throws -> IntervalProof {
        try encloseRetainingRoot(storage,over:fraction,restricting:nil,
            tolerance:tolerance,consumeWork:consumeWork,consumeStorage:consumeStorage).proof
    }

    func intervalProofRetainingRoot(over fraction: ScalarInterval,
        restricting parent: ImplicitCurveIntervalJetEncloser.ParameterEnclosureState? = nil,
        tolerance: ModelingTolerance, consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil)
        throws -> (proof: IntervalProof, root: ImplicitCurveIntervalJetEncloser.ParameterEnclosureState?) {
        guard fraction.lower >= 0, fraction.upper <= 1 else {
            throw Self.failure(.invalidInput,tolerance,"Retained root chart requires its original normalized interval.")
        }
        return try Self.encloseRetainingRoot(storage,over:fraction,restricting:parent,
            tolerance:tolerance,consumeWork:consumeWork,consumeStorage:consumeStorage)
    }

    private static func encloseRetainingRoot(_ storage: Storage, over fraction: ScalarInterval,
        restricting parent: ImplicitCurveIntervalJetEncloser.ParameterEnclosureState?,
        tolerance: ModelingTolerance, consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil)
        throws -> (proof: IntervalProof, root: ImplicitCurveIntervalJetEncloser.ParameterEnclosureState?) {
        switch storage {
        case .originalHigher(let curve,let policy):
            let original = try OriginalParameterCurveHigherTaylor.enclosure(curve,over:fraction,order:3,
                tolerance:tolerance,maximumSpanCount:262_144,
                maximumSubdivisionDepth:policy.maximumSubdivisionDepth,remainingSourceDepth:policy.remainingSourceDepth,
                consumeWork:consumeWork,consumeStorage:consumeStorage,maximumAlgebraicDepth:policy.maximumAlgebraicDepth)
            func field(_ jet:SurfaceAreaIntervalTaylorScalarJet) throws -> SurfaceIntervalJet {
                let zero = OutwardScalarInterval.exact(0)
                return try SurfaceIntervalJet(value:jet.coefficient(0,0),derivativeU:jet.coefficient(1,0),derivativeV:zero,
                    secondDerivativeUU:jet.coefficient(2,0) * .exact(2),secondDerivativeUV:zero,secondDerivativeVV:zero,
                    thirdDerivativeUUU:jet.coefficient(3,0) * .exact(6),thirdDerivativeUUV:zero,
                    thirdDerivativeUVV:zero,thirdDerivativeVVV:zero)
            }
            return try (.smooth(u:field(original.u),v:field(original.v)),nil)
        case .originalImage(let child, let image,let policy):
            // FIXME(INCOMPLETE_IMPLEMENTATION): Hosted image range and coefficient
            // transport now share source-bound algebra/work/BYTES. Deeper original
            // implicit/specialized child families still need their complete lower
            // source-validation and query ports before all-family flux closure.
            let source = try encloseRetainingRoot(child, over: image.mappedRange(fraction,consumeWork:consumeWork,consumeStorage:consumeStorage,
                maximumAlgebraicDepth:policy?.maximumAlgebraicDepth), restricting: parent,
                tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)
            try consumeWork()
            switch source.proof {
            case .smooth(let u, let v):
                let mapped = try image.mappedParameterJets(u:u,v:v,consumeWork:consumeWork,consumeStorage:consumeStorage,
                    maximumAlgebraicDepth:policy?.maximumAlgebraicDepth)
                return (.smooth(u: mapped.u, v: mapped.v), source.root)
            case .valueOnly(let u, let v, let du, let dv):
                let zero = OutwardScalarInterval.exact(0)
                func field(_ value: OutwardScalarInterval, _ derivative: OutwardScalarInterval) -> SurfaceIntervalJet {
                    .init(value: value, derivativeU: derivative, derivativeV: zero,
                        secondDerivativeUU: zero, secondDerivativeUV: zero, secondDerivativeVV: zero,
                        thirdDerivativeUUU: zero, thirdDerivativeUUV: zero, thirdDerivativeUVV: zero, thirdDerivativeVVV: zero)
                }
                let mapped = try image.mappedParameterJets(u:field(u,du),v:field(v,dv),consumeWork:consumeWork,consumeStorage:consumeStorage,
                    maximumAlgebraicDepth:policy?.maximumAlgebraicDepth)
                return (.valueOnly(u: mapped.u.value, v: mapped.v.value,
                    tangentU: mapped.u.derivativeU, tangentV: mapped.v.derivativeU), source.root)
            }

        case .affineImplicit(let prepared):
            return (try prepared.intervalProof(over:fraction,tolerance:tolerance,consumeWork:consumeWork),nil)
        case .nonlinearImplicit(let prepared):
            // FIXME(INCOMPLETE_IMPLEMENTATION): The retained original implicit
            // localization now shares query work/depth/BYTES; certification-contract
            // admission still needs its complete bounded source-validation producer
            // before this integral chart can establish all-family source closure.
            let result = try prepared.intervalProofRetainingRoot(over:fraction,restricting:parent,
                tolerance:tolerance,consumeWork:consumeWork,consumeStorage:consumeStorage)
            return (result.proof,result.root)
        case .nativeNumeric(let prepared):
            return (try prepared.intervalProof(over:fraction,tolerance:tolerance,consumeWork:consumeWork,consumeStorage:consumeStorage),nil)
        case .originalContinuation(let continuation, let prepared):
            try Task.checkCancellation(); try consumeWork()
            let jet = try continuation.intervalJet(over: fraction, source: prepared, tolerance: tolerance)
            let native = SurfaceIntervalJet.constant(continuation.startParameter)
                + .parameterU(fraction) * .constant(continuation.endParameter - continuation.startParameter)
            let originalLower = continuation.original.knots[continuation.original.degree]
            let originalUpper = continuation.original.knots[continuation.original.controlPoints.count]
            let joins = continuation.original.knots.contains {
                $0 > originalLower && $0 < originalUpper && $0 > native.value.lower && $0 < native.value.upper
            }
            if joins {
                return (.valueOnly(u: jet.u.value, v: jet.v.value,
                    tangentU: jet.u.derivativeU, tangentV: jet.v.derivativeU), nil)
            }
            return (.smooth(u: jet.u, v: jet.v), nil)
        case .numeric(let curve):
            if consumeStorage != nil {
                // FIXME(INCOMPLETE_IMPLEMENTATION): Legacy chart metadata has no
                // bounded original source-policy receipt. Selected BYTE consumers
                // must use the bounded original chart constructor.
                throw failure(.unsupportedCapability,tolerance,"Legacy area chart has no bounded original preparation receipt.")
            }
            guard let jet = try SurfaceParameterIntervalJet.enclose(curve, over: fraction, tolerance: tolerance) else {
                throw failure(.unsupportedCapability, tolerance, "Admitted area chart lost its numeric interval derivatives.")
            }
            return (.smooth(u:jet.u,v:jet.v),nil)
        case .translated(let child, let u, let v):
            let source = try encloseRetainingRoot(child,over:fraction,restricting:parent,
                tolerance:tolerance,consumeWork:consumeWork,consumeStorage:consumeStorage)
            switch source.proof {
            case .smooth(let x,let y): return (.smooth(u:x + .constant(u),v:y + .constant(v)),source.root)
            case .valueOnly(let x,let y,let dx,let dy):
                return (.valueOnly(u:x + .exact(u),v:y + .exact(v),tangentU:dx,tangentV:dy),source.root)
            }
        case .rigid(let child, let map, let start, let end):
            if map == .identity, start == 0, end == 1 {
                // Exact identity composition preserves every original interval
                // and derivative order without another arithmetic enclosure.
                return try encloseRetainingRoot(child,over:fraction,restricting:parent,
                    tolerance:tolerance,consumeWork:consumeWork,consumeStorage:consumeStorage)
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
            let source = try encloseRetainingRoot(child,over:range,restricting:parent,
                tolerance:tolerance,consumeWork:consumeWork,consumeStorage:consumeStorage)
            if case .valueOnly(let u,let v,let du,let dv) = source.proof {
                let slope = OutwardScalarInterval.exact(end) - .exact(start)
                return (.valueOnly(u:u * .exact(map.uu) + v * .exact(map.uv) + .exact(map.uOffset),
                    v:u * .exact(map.vu) + v * .exact(map.vv) + .exact(map.vOffset),
                    tangentU:(du * .exact(map.uu) + dv * .exact(map.uv))*slope,
                    tangentV:(du * .exact(map.vu) + dv * .exact(map.vv))*slope),source.root)
            }
            guard case .smooth(let sourceU,let sourceV) = source.proof else {
                throw failure(.classificationFailure,tolerance,"An area chart lost its interval proof kind.")
            }
            let composed = SurfaceParameterThirdOrderChainRule.intervalJet(
                surface: SurfaceIntervalVectorJet(x: sourceU, y: sourceV, z: .constant(0)),
                u: parameter, v: .constant(0))
            return (.smooth(u:composed.x * .constant(map.uu) + composed.y * .constant(map.uv) + .constant(map.uOffset),
                           v:composed.x * .constant(map.vu) + composed.y * .constant(map.vv) + .constant(map.vOffset)),source.root)
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
                                   depth: Int, tolerance: ModelingTolerance,
        consumeWork: () throws -> Void = { try Task.checkCancellation() }) throws {
        try consumeWork(); try checkDepth(depth, tolerance)
        switch curve {
        case .affine, .constantU, .constantV, .harmonic: break
        case .polyline(let points):
            guard points.count <= boundaries else { throw failure(.resourceLimitExceeded, tolerance, "Area chart polyline limit exceeded.") }
        case .originalAffineWord(let image):
            try preflight(image.source.surface,controls:controls,boundaries:boundaries,
                depth:depth+1,tolerance:tolerance,consumeWork:consumeWork)
            try preflight(image.source.parameterCurve,controls:controls,boundaries:boundaries,
                depth:depth+1,tolerance:tolerance,consumeWork:consumeWork)
        case .originalImage(let image):
            try preflight(image.source.surface, controls: controls, boundaries: boundaries, depth: depth + 1, tolerance: tolerance, consumeWork: consumeWork)
            try preflight(.procedural(.originalImage(image.targetImage)), controls: controls, boundaries: boundaries, depth: depth + 1, tolerance: tolerance, consumeWork: consumeWork)
            try preflight(image.source.parameterCurve, controls: controls, boundaries: boundaries, depth: depth + 1, tolerance: tolerance, consumeWork: consumeWork)
        case .originalBSplineContinuation(let continuation):
            try preflight(.bSpline(continuation.original), controls: controls, boundaries: boundaries,
                depth: depth + 1, tolerance: tolerance, consumeWork: consumeWork)
        case .bSpline(let spline):
            try splineDimensions(controls: spline.controlPoints.count, degree: spline.degree,
                knots: spline.knots.count, weights: spline.weights.count, limit: controls, tolerance: tolerance)
            let lower = spline.knots[spline.degree], upper = spline.knots[spline.controlPoints.count]
            guard try spline.knots.allSatisfy({ try consumeWork(); return $0.isFinite }), lower < upper,
                  try spline.knots.indices.dropFirst().allSatisfy({ try consumeWork(); return spline.knots[$0 - 1] <= spline.knots[$0] }) else {
                throw failure(.invalidInput,tolerance,"Area chart spline knots require a finite ordered native domain.")
            }
            // Original validation retains C0 connectivity; the native chart owner
            // provides one-sided jets instead of assuming C2 across interior knots.
        case .periodicTranslation(let base, _, _):
            try preflight(base, controls: controls, boundaries: boundaries, depth: depth + 1, tolerance: tolerance, consumeWork: consumeWork)
        case .offsetSurfaceImage(let image):
            try preflight(.procedural(.offset(image.offset)), controls: controls, boundaries: boundaries,
                depth: depth + 1, tolerance: tolerance, consumeWork: consumeWork)
            try preflight(image.source, controls: controls, boundaries: boundaries, depth: depth + 1, tolerance: tolerance, consumeWork: consumeWork)
        case .rigidImage(let image):
            guard image.startFraction.isFinite, image.endFraction.isFinite,
                  image.startFraction >= 0, image.startFraction <= 1,
                  image.endFraction >= 0, image.endFraction <= 1, image.startFraction != image.endFraction else {
                throw failure(.invalidInput, tolerance, "Area rigid chart fractions must stay inside the original source interval.")
            }
            try preflight(image.source.surface, controls: controls, boundaries: boundaries, depth: depth + 1, tolerance: tolerance, consumeWork: consumeWork)
            try preflight(image.targetSurface, controls: controls, boundaries: boundaries, depth: depth + 1, tolerance: tolerance, consumeWork: consumeWork)
            try preflight(image.source.parameterCurve, controls: controls, boundaries: boundaries, depth: depth + 1, tolerance: tolerance, consumeWork: consumeWork)
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
                depth:depth+1,tolerance:tolerance,consumeWork:consumeWork)
            try preflight(implicit.intersection.secondSurface,controls:controls,boundaries:boundaries,
                depth:depth+1,tolerance:tolerance,consumeWork:consumeWork)
        default:
            // FIXME(INCOMPLETE_IMPLEMENTATION): Remaining non-numeric source charts have no bounded
            // derivative admission for production face-area queries. Complete only after
            // whole-chart integral authority and success/failure fixtures are implemented.
            throw failure(.unsupportedCapability, tolerance, "Area chart source is not an admitted numeric chart.")
        }
    }

    private static func preflight(_ surface: Surface3D, controls: Int, boundaries: Int,
                                   depth: Int, tolerance: ModelingTolerance,
        consumeWork: () throws -> Void = { try Task.checkCancellation() }) throws {
        try consumeWork(); try checkDepth(depth, tolerance)
        switch surface {
        case .bSpline(let spline):
            let uCount = spline.controlPoints.first?.count ?? 0, vCount = spline.controlPoints.count
            guard vCount <= controls, try spline.controlPoints.allSatisfy({ try consumeWork(); return $0.count <= controls }),
                  spline.weights.count <= controls, try spline.weights.allSatisfy({ try consumeWork(); return $0.count <= controls }) else {
                throw failure(.resourceLimitExceeded, tolerance, "Area chart support dimensions exceed admission.")
            }
            try splineDimensions(controls: uCount, degree: spline.uDegree, knots: spline.uKnots.count,
                weights: uCount, limit: controls, tolerance: tolerance)
            try splineDimensions(controls: vCount, degree: spline.vDegree, knots: spline.vKnots.count,
                weights: spline.weights.count, limit: controls, tolerance: tolerance)
            guard try spline.controlPoints.allSatisfy({ try consumeWork(); return $0.count == uCount }), try spline.weights.allSatisfy({ try consumeWork(); return $0.count == uCount }) else {
                throw failure(.invalidInput, tolerance, "Area chart support has inconsistent row dimensions.")
            }
            guard uCount <= controls / vCount else { throw failure(.resourceLimitExceeded, tolerance, "Area chart support control limit exceeded.") }
            var expanded = 1
            func admitFactor(_ factor:Int) throws {
                try consumeWork()
                guard factor > 0, factor <= controls / expanded else {
                    throw failure(.resourceLimitExceeded,tolerance,"Area chart Bezier preparation limit exceeded.")
                }
                expanded *= factor
            }
            try admitFactor(uCount-spline.uDegree); try admitFactor(vCount-spline.vDegree)
            try admitFactor(spline.uDegree+1); try admitFactor(spline.vDegree+1)
        case .procedural(.originalAffineWord(let image)):
            try preflight(image.source,controls:controls,boundaries:boundaries,
                depth:depth+1,tolerance:tolerance,consumeWork:consumeWork)
        case .procedural(.originalAngularTransport(let image)):
            try preflight(image.source,controls:controls,boundaries:boundaries,
                depth:depth+1,tolerance:tolerance,consumeWork:consumeWork)
        case .procedural(.originalImage(let image)):
            try preflight(image.source, controls: controls, boundaries: boundaries, depth: depth + 1, tolerance: tolerance, consumeWork: consumeWork)
        case .procedural(.offset(let offset)):
            try preflight(offset.source, controls: controls, boundaries: boundaries, depth: depth + 1, tolerance: tolerance, consumeWork: consumeWork)
        case .procedural(.originalRevolution(let revolution)):
            try preflight(revolution.generator.source, controls: controls, boundaries: boundaries, depth: depth + 1, tolerance: tolerance, consumeWork: consumeWork)
        case .procedural(.originalBoundaryCorrected(let corrected)):
            try preflight(.bSpline(corrected.construction), controls: controls, boundaries: boundaries, depth: depth + 1, tolerance: tolerance, consumeWork: consumeWork)
            try preflight(.procedural(.originalCoons(corrected.boundaries)), controls: controls, boundaries: boundaries, depth: depth + 1, tolerance: tolerance, consumeWork: consumeWork)
        case .procedural(.originalCoons(let coons)):
            try preflight(coons.vMinimumBoundary.source,controls:controls,boundaries:boundaries,depth:depth+1,tolerance:tolerance,consumeWork:consumeWork)
            try preflight(coons.vMaximumBoundary.source,controls:controls,boundaries:boundaries,depth:depth+1,tolerance:tolerance,consumeWork:consumeWork)
            try preflight(coons.uMinimumBoundary.source,controls:controls,boundaries:boundaries,depth:depth+1,tolerance:tolerance,consumeWork:consumeWork)
            try preflight(coons.uMaximumBoundary.source,controls:controls,boundaries:boundaries,depth:depth+1,tolerance:tolerance,consumeWork:consumeWork)
        case .procedural(.ruled(let ruled)):
            try preflight(ruled.startBoundary, controls: controls, boundaries: boundaries, depth: depth + 1, tolerance: tolerance, consumeWork: consumeWork)
            try preflight(ruled.endBoundary, controls: controls, boundaries: boundaries, depth: depth + 1, tolerance: tolerance, consumeWork: consumeWork)
        case .procedural(.rollingBall(let blend)):
            try preflight(blend.centerSpine,controls:controls,boundaries:boundaries,depth:depth+1,tolerance:tolerance,consumeWork:consumeWork)
            try preflight(blend.firstContact,controls:controls,boundaries:boundaries,depth:depth+1,tolerance:tolerance,consumeWork:consumeWork)
            try preflight(blend.secondContact,controls:controls,boundaries:boundaries,depth:depth+1,tolerance:tolerance,consumeWork:consumeWork)
        default: break
        }
    }

    private static func preflight(_ curve: Curve3D, controls: Int, boundaries: Int,
                                   depth: Int, tolerance: ModelingTolerance,
        consumeWork: () throws -> Void = { try Task.checkCancellation() }) throws {
        try consumeWork(); try checkDepth(depth, tolerance)
        switch curve {
        case .line, .circle: break
        case .analytic(let analytic):
            if case .planeTorus(let intersection) = analytic {
                try preflight(intersection.planeSurface, controls:controls,boundaries:boundaries,
                    depth:depth+1,tolerance:tolerance,consumeWork:consumeWork)
                try preflight(intersection.torusSurface, controls:controls,boundaries:boundaries,
                    depth:depth+1,tolerance:tolerance,consumeWork:consumeWork)
            }
        case .bSpline(let spline):
            try splineDimensions(controls: spline.controlPoints.count, degree: spline.degree,
                knots: spline.knots.count, weights: spline.weights.count, limit: controls, tolerance: tolerance)
        case .surfaceLift(let lift):
            try preflight(lift.surface, controls: controls, boundaries: boundaries, depth: depth + 1, tolerance: tolerance, consumeWork: consumeWork)
            try preflight(lift.parameterCurve, controls: controls, boundaries: boundaries, depth: depth + 1, tolerance: tolerance, consumeWork: consumeWork)
        case .originalAffineWord(let image):
            try preflight(image.source,controls:controls,boundaries:boundaries,
                depth:depth+1,tolerance:tolerance,consumeWork:consumeWork)
        case .originalAngularTransport(let image):
            try preflight(image.source,controls:controls,boundaries:boundaries,
                depth:depth+1,tolerance:tolerance,consumeWork:consumeWork)
        case .rigidImage(let image):
            try preflight(image.source, controls: controls, boundaries: boundaries, depth: depth + 1, tolerance: tolerance, consumeWork: consumeWork)
        case .parameterImage(let image):
            try preflight(image.source, controls: controls, boundaries: boundaries, depth: depth + 1, tolerance: tolerance, consumeWork: consumeWork)
        case .affineImage(let image):
            try preflight(image.source, controls: controls, boundaries: boundaries, depth: depth + 1, tolerance: tolerance, consumeWork: consumeWork)
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
