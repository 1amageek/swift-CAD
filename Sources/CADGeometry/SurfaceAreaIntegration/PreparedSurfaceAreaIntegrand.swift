import CADCore
#if !hasFeature(Embedded)
import Foundation
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#else
#error("CADGeometry numeric algorithms require the target C math module.")
#endif

/// Integral-specific fields; derivative coordinates are boundary fraction and radial fraction.
package struct SurfaceAreaIntegrandBounds: Sendable {
    package let value: OutwardScalarInterval
    package let derivativeU: OutwardScalarInterval?
    package let derivativeV: OutwardScalarInterval?
    package let secondUU: OutwardScalarInterval?
    package let secondUV: OutwardScalarInterval?
    package let secondVV: OutwardScalarInterval?
}

/// Immutable exact geometry preparation for signed boundary-fan integration.
package struct PreparedSurfaceAreaIntegrand: Sendable {
    /// Geometry-owned chart authority, opaque to the topology cell retaining it.
    package struct CenteredFanChartProof: Sendable {
        fileprivate let curve: SurfaceParameterCurve
        fileprivate let support: Surface3D
        fileprivate let fraction: ScalarInterval
        fileprivate let tolerance: ModelingTolerance
        fileprivate let root: ImplicitCurveIntervalJetEncloser.ParameterEnclosureState
        fileprivate let range: (u: SurfaceIntervalJet, v: SurfaceIntervalJet)
        fileprivate let midpoint: (u: SurfaceIntervalJet, v: SurfaceIntervalJet)

        fileprivate init(curve: SurfaceParameterCurve, support: Surface3D,
            fraction: ScalarInterval, tolerance: ModelingTolerance,
            root: ImplicitCurveIntervalJetEncloser.ParameterEnclosureState,
            range: (u: SurfaceIntervalJet, v: SurfaceIntervalJet),
            midpoint: (u: SurfaceIntervalJet, v: SurfaceIntervalJet)) {
            self.curve = curve
            self.support = support
            self.fraction = fraction
            self.tolerance = tolerance
            self.root = root
            self.range = range
            self.midpoint = midpoint
        }
    }

    private indirect enum Storage: Sendable {
        case spline(SurfaceAreaNativeSpanPartition)
        case ruledTensor(SurfaceAreaRuledTensorAuthority, SurfaceAreaNativeSpanPartition)
        case offset(OffsetSurface3D, PreparedSurfaceAreaIntegrand)
        case direct(PreparedSurfaceDifferentialEncloser)
        case translatedRollingBall(SurfaceAreaTranslatedRollingBallJet)
        case nativeRollingBall(SurfaceAreaNativeRollingBallPartition)
        case nativeOffset(SurfaceAreaNativeOffsetTaylorPartition)
        case nativeRuled(SurfaceAreaNativeRuledPartition)
        case generalRollingBall(SurfaceAreaGeneralRollingBallPartition)
    }
    package let surface: Surface3D
    private let storage: Storage
    private let receipt: OriginalGeometryPreparationReceipt
    private let derivativeOrder: Int
    private let originalRadialIntegrationIsExact: Bool
    private let preparationTolerance: ModelingTolerance
    private let maximumOriginalSubdivisionDepth: Int?
    private let remainingOriginalSourceDepth: Int
    private let maximumOriginalAlgebraicDepth: Int?
    private let originalTranslationDirection: SurfaceAreaTranslationCertificate?
    package var translationDirection: SurfaceAreaTranslationCertificate? {
        if case .nativeOffset(let partition) = storage { return partition.translationDirection ?? originalTranslationDirection }
        return originalTranslationDirection
    }
    package var hasOriginalOffsetRectangleIntegral: Bool {
        if case .nativeOffset(let partition) = storage { return partition.hasOriginalPlanarRectangle }
        return false
    }
    package func originalOffsetRectangleIntegral(over rectangle: SurfaceParameterBox,reference: Point3D,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> [OutwardScalarInterval]? {
        try receipt.admit(tolerance: tolerance, using: &execution)
        if case .nativeOffset(let partition) = storage {
            return try partition.originalPlanarRectangleIntegral(over:rectangle,reference:reference,
                tolerance:tolerance, using: &execution)
        }
        return nil
    }

    package init(surface: Surface3D, tolerance: ModelingTolerance, maximumControlPointCount: Int = 65_536,
        maximumSubdivisionDepth: Int? = nil, remainingSourceDepth: Int = 16,
        maximumAlgebraicDepth: Int? = nil, using execution: inout OriginalQueryExecution) throws {
        let maximumSubdivisionDepth = maximumSubdivisionDepth ?? execution.effectiveLimits.maximumSubdivisionDepth
        let preparation = try execution.withPreparationScope { execution in
            try Self.prepare(surface: surface, tolerance: tolerance,
                maximumControlPointCount: maximumControlPointCount,
                maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
                maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
        }
        self.surface = surface
        storage = preparation.result.storage
        derivativeOrder = preparation.result.derivativeOrder
        originalRadialIntegrationIsExact = preparation.result.radialIntegrationIsExact
        originalTranslationDirection = preparation.result.translation
        preparationTolerance = tolerance
        maximumOriginalSubdivisionDepth = maximumSubdivisionDepth
        remainingOriginalSourceDepth = remainingSourceDepth
        maximumOriginalAlgebraicDepth = maximumAlgebraicDepth
        receipt = try OriginalGeometryPreparationReceipt(tolerance: tolerance, depth: preparation.depth, using: &execution)
    }

    private static func prepare(surface: Surface3D, tolerance: ModelingTolerance,
        maximumControlPointCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        maximumAlgebraicDepth: Int?, using execution: inout OriginalQueryExecution)
        throws -> (storage: Storage, derivativeOrder: Int, translation: SurfaceAreaTranslationCertificate?, radialIntegrationIsExact: Bool) {
        try Self.admitDimensions(surface,limit:maximumControlPointCount,tolerance:tolerance, using: &execution)
        do {
            try surface.validateOriginalSource(tolerance:tolerance,remainingSourceDepth:remainingSourceDepth,
                maximumSubdivisionDepth:maximumSubdivisionDepth,maximumAlgebraicDepth:maximumAlgebraicDepth, using: &execution)
        }
        func prepareDifferential(_ value: Surface3D) throws -> PreparedSurfaceDifferentialEncloser {
            try PreparedSurfaceDifferentialEncloser(surface: value, tolerance: tolerance,
                remainingSourceDepth: remainingSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth,
                maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
        }
        let originalTranslationDirection = try SurfaceAreaTranslationCertificate.direction(of: surface,
            remainingSourceDepth:remainingSourceDepth,maximumAlgebraicDepth:maximumAlgebraicDepth, using: &execution)
        let storage: Storage
        let derivativeOrder: Int
        switch surface {
        case .bSpline(let spline):
            let partition = try SurfaceAreaNativeSpanPartition(surface:spline,tolerance:tolerance,maximumAlgebraicDepth:maximumAlgebraicDepth, using: &execution)
            storage = .spline(partition)
            derivativeOrder = partition.derivativeOrder
        case .procedural(.originalDrafted(let drafted)):
            storage = .direct(try prepareDifferential(surface))
            let box = try SurfaceParameterBox(u: ScalarInterval(lower:0,upper:1),
                v:ScalarInterval(lower:0,upper:1))
            derivativeOrder = try drafted.hasOriginalFirstOrderContinuity(over:box,
                tolerance:tolerance,maximumSpanCount:262_144,
                maximumSubdivisionDepth:maximumSubdivisionDepth ?? execution.effectiveLimits.maximumSubdivisionDepth,
                remainingSourceDepth:remainingSourceDepth, using: &execution) ? 1 : 0
        case .procedural(.originalAffineWord(let image)):
            let original = try PreparedSurfaceAreaIntegrand(surface: image.source,
                tolerance: tolerance, maximumControlPointCount: maximumControlPointCount,
                maximumSubdivisionDepth:maximumSubdivisionDepth,remainingSourceDepth:remainingSourceDepth-1,
                maximumAlgebraicDepth:maximumAlgebraicDepth, using: &execution)
            storage = .direct(try prepareDifferential(surface))
            derivativeOrder = original.derivativeOrder
        case .procedural(.originalImage(let image)):
            let original = try PreparedSurfaceAreaIntegrand(surface: image.source,
                tolerance: tolerance, maximumControlPointCount: maximumControlPointCount,maximumSubdivisionDepth:maximumSubdivisionDepth,
                remainingSourceDepth:remainingSourceDepth-1,maximumAlgebraicDepth:maximumAlgebraicDepth, using: &execution)
            storage = .direct(try prepareDifferential(surface))
            derivativeOrder = original.derivativeOrder
        case .procedural(.offset(let offset)):
            if let exact = try offset.exactChartPreservingSurface(tolerance: tolerance, using: &execution) {
                let prepared = try PreparedSurfaceAreaIntegrand(surface: exact, tolerance: tolerance, maximumControlPointCount: maximumControlPointCount,
                    maximumSubdivisionDepth:maximumSubdivisionDepth,remainingSourceDepth:remainingSourceDepth-1,
                    maximumAlgebraicDepth:maximumAlgebraicDepth, using: &execution)
                storage = prepared.storage
                derivativeOrder = prepared.derivativeOrder
            } else if !(try SurfaceAreaTranslationCertificate.fourthDerivativesAreExactlyZero(of:offset.source, using: &execution)),
                let native = try SurfaceAreaNativeOffsetTaylorPartition(surface:surface,
                    tolerance:tolerance,maximumAlgebraicDepth:maximumAlgebraicDepth,remainingSourceDepth:remainingSourceDepth, using: &execution) {
                storage = .nativeOffset(native)
                derivativeOrder = 3
            } else {
                let source = try PreparedSurfaceAreaIntegrand(surface: offset.source, tolerance: tolerance, maximumControlPointCount: maximumControlPointCount,
                    maximumSubdivisionDepth:maximumSubdivisionDepth,remainingSourceDepth:remainingSourceDepth-1,
                    maximumAlgebraicDepth:maximumAlgebraicDepth, using: &execution)
                // FIXME(INCOMPLETE_IMPLEMENTATION): Sources below third order, including
                // sources outside the original B-spline higher-coefficient family,
                // lack derivatives for production face-area/centroid integration.
                // Complete only after original higher source jets and integral fixtures certify.
                guard source.derivativeOrder >= 3 else {
                    throw Self.failure(.unsupportedCapability, tolerance,
                        "Offset area density gradients require certified third source derivatives.")
                }
                storage = .offset(offset, source)
                // OffsetSurface3D's actual interval path zeroes third tangent jets.
                // Those are fourth source derivatives: use density Hessians only
                // when structural polynomial authority proves every one is zero.
                derivativeOrder = (try SurfaceAreaTranslationCertificate.fourthDerivativesAreExactlyZero(of: offset.source, using: &execution)) ? 3 : 2
            }
        case .procedural(.ruled(let ruled)):
            let order = min(try Self.curveOrder(ruled.startBoundary, tolerance: tolerance,maximumSubdivisionDepth:maximumSubdivisionDepth,
                remainingSourceDepth:remainingSourceDepth,maximumAlgebraicDepth:maximumAlgebraicDepth, using: &execution),
                            try Self.curveOrder(ruled.endBoundary, tolerance: tolerance,maximumSubdivisionDepth:maximumSubdivisionDepth,
                remainingSourceDepth:remainingSourceDepth,maximumAlgebraicDepth:maximumAlgebraicDepth, using: &execution))
            if order < 2, let authority = try SurfaceAreaRuledTensorAuthority(original: ruled,
                maximumControlPointCount: maximumControlPointCount, tolerance: tolerance,
                maximumSubdivisionDepth:maximumSubdivisionDepth,remainingSourceDepth:remainingSourceDepth,
                maximumAlgebraicDepth:maximumAlgebraicDepth, using: &execution) {
                let partition = try SurfaceAreaNativeSpanPartition(surface:authority.tensor,tolerance:tolerance,maximumAlgebraicDepth:maximumAlgebraicDepth, using: &execution)
                storage = .ruledTensor(authority, partition)
                derivativeOrder = partition.derivativeOrder
            } else {
                if order < 2 {
                    storage = .nativeRuled(try SurfaceAreaNativeRuledPartition(original: ruled,
                        tolerance: tolerance,maximumSubdivisionDepth:maximumSubdivisionDepth,
                        remainingSourceDepth:remainingSourceDepth,maximumAlgebraicDepth:maximumAlgebraicDepth, using: &execution))
                    derivativeOrder = 1
                } else {
                    derivativeOrder = order
                    storage = .direct(try prepareDifferential(surface))
                }
            }
        case .procedural(.rollingBall(let blend)):
            if case .bSpline(let spine) = blend.centerSpine,
               spine.controlPoints.count > maximumControlPointCount {
                throw Self.failure(.resourceLimitExceeded, tolerance, "Area center-spine admission limit exceeded.")
            }
            let order = min(try Self.curveOrder(blend.centerSpine, tolerance: tolerance,maximumSubdivisionDepth:maximumSubdivisionDepth,
                remainingSourceDepth:remainingSourceDepth,maximumAlgebraicDepth:maximumAlgebraicDepth, using: &execution),
                            try Self.curveOrder(blend.firstContact, tolerance: tolerance,maximumSubdivisionDepth:maximumSubdivisionDepth,
                remainingSourceDepth:remainingSourceDepth,maximumAlgebraicDepth:maximumAlgebraicDepth, using: &execution),
                            try Self.curveOrder(blend.secondContact, tolerance: tolerance,maximumSubdivisionDepth:maximumSubdivisionDepth,
                remainingSourceDepth:remainingSourceDepth,maximumAlgebraicDepth:maximumAlgebraicDepth, using: &execution))
            if order < 2, let native = try SurfaceAreaNativeRollingBallPartition(blend:blend,
                tolerance:tolerance,maximumSubdivisionDepth:maximumSubdivisionDepth,
                remainingSourceDepth:remainingSourceDepth,maximumAlgebraicDepth:maximumAlgebraicDepth, using: &execution) {
                storage = .nativeRollingBall(native)
                derivativeOrder = 1
            } else {
                if order < 2 {
                    storage = .generalRollingBall(try SurfaceAreaGeneralRollingBallPartition(original: blend,
                        tolerance: tolerance,maximumSubdivisionDepth:maximumSubdivisionDepth,
                        remainingSourceDepth:remainingSourceDepth,maximumAlgebraicDepth:maximumAlgebraicDepth, using: &execution))
                    derivativeOrder = 1
                    break
                }
                derivativeOrder = order
                if let translated = try SurfaceAreaTranslatedRollingBallJet(blend,maximumSubdivisionDepth:maximumSubdivisionDepth,
                    remainingSourceDepth:remainingSourceDepth,maximumAlgebraicDepth:maximumAlgebraicDepth, using: &execution) {
                    storage = .translatedRollingBall(translated)
                } else {
                    storage = .direct(try prepareDifferential(surface))
                }
            }
        default:
            storage = .direct(try prepareDifferential(surface))
            derivativeOrder = 3
        }
        return (storage, derivativeOrder, originalTranslationDirection, try surface.hasExactAffineParameterization(using: &execution))
    }

    /// Original divergence-theorem fluxes in V, X, Y, Z, XX, YY, ZZ, XY, XZ, YZ order.
    package func volumeMomentBounds(over box: SurfaceParameterBox, reference: Point3D,
        tolerance: ModelingTolerance, domain: SurfaceAreaNativeSpanDomain? = nil, using execution: inout OriginalQueryExecution) throws -> [SurfaceAreaIntegrandBounds] {
        try receipt.admit(tolerance: tolerance, using: &execution)
        let result = try volumeFields(over: box, u: .parameterU(box.u), v: .parameterV(box.v),
            measure: .constant(1), reference: reference, domain: domain,
            tolerance: tolerance, using: &execution)
        try execution.checkpoint()
        return result
    }

    package func volumeMomentFanBounds(curve: SurfaceParameterCurve,
        parameterChart: SurfaceAreaParameterChartEncloser, anchor: SurfaceParameter,
        reference: Point3D, boundaryFraction: ScalarInterval, radialFraction: ScalarInterval,
        tolerance: ModelingTolerance, domain: SurfaceAreaNativeSpanDomain? = nil, using execution: inout OriginalQueryExecution) throws -> [SurfaceAreaIntegrandBounds] {
        try receipt.admit(tolerance: tolerance, using: &execution)
        guard boundaryFraction.lower >= 0, boundaryFraction.upper <= 1,
              boundaryFraction.lower <= boundaryFraction.upper,
              radialFraction.lower >= 0, radialFraction.upper <= 1,
              radialFraction.lower <= radialFraction.upper else {
            throw Self.failure(.invalidInput, tolerance, "Original volume fan requires closed normalized chart fractions.")
        }
        if let domain {
            guard domain.curve == curve, domain.anchor == anchor,
                  let radial = domain.radialRange,
                  radialFraction.lower >= radial.lower, radialFraction.upper <= radial.upper else {
                throw Self.failure(.invalidInput, tolerance, "Native span authority does not cover this original volume fan measure.")
            }
        }
        let proof = try chartProof(curve: curve, prepared: parameterChart, over: boundaryFraction,
            tolerance: tolerance, using: &execution)
        if case .smooth(let chartU, let chartV) = proof {
            let pulled = try fanPullback(u: chartU, v: chartV, anchor: anchor,
                radialFraction: radialFraction, tolerance: tolerance)
            return try volumeFields(over: pulled.box, u: pulled.u, v: pulled.v,
                measure: pulled.measure, reference: reference, domain: domain,
                tolerance: tolerance, using: &execution)
        }
        let values = proof.values
        let radial = OutwardScalarInterval(lower: radialFraction.lower, upper: radialFraction.upper)
        let du = values.u - .exact(anchor.u), dv = values.v - .exact(anchor.v)
        let box = SurfaceParameterBox(u: try clipped(.exact(anchor.u) + du * radial,
            to: surface.uDomain, tolerance: tolerance),
            v: try clipped(.exact(anchor.v) + dv * radial, to: surface.vDomain, tolerance: tolerance))
        let measure = radial * (du * values.tangentV - dv * values.tangentU)
        let ranged = try volumeFields(over: box, u: .parameterU(box.u), v: .parameterV(box.v),
            measure: .constant(1), reference: reference, domain: domain,
            tolerance: tolerance, using: &execution)
        try OriginalCoefficientAllocation.reserve(count:ranged.count,of:SurfaceAreaIntegrandBounds.self, using: &execution)
        return ranged.map { .init(value: $0.value * measure, derivativeU: nil, derivativeV: nil,
            secondUU: nil, secondUV: nil, secondVV: nil) }
    }

    private func volumeFields(over box: SurfaceParameterBox, u: SurfaceIntervalJet,
        v: SurfaceIntervalJet, measure: SurfaceIntervalJet, reference: Point3D,
        domain: SurfaceAreaNativeSpanDomain?, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> [SurfaceAreaIntegrandBounds] {
        guard tolerance == preparationTolerance, reference.isFinite else {
            throw Self.failure(.invalidInput, tolerance, "Original volume flux requires its retained tolerance and finite reference.")
        }
        func exponent(_ index: Int) -> (Int,Int,Int) {
            switch index {
            case 0:return (0,0,0);case 1:return (1,0,0);case 2:return (0,1,0);case 3:return (0,0,1)
            case 4:return (2,0,0);case 5:return (0,2,0);case 6:return (0,0,2)
            case 7:return (1,1,0);case 8:return (1,0,1);default:return (0,1,1)
            }
        }
        var result: [SurfaceAreaIntegrandBounds]?
        try forEachSurfaceJet(over: box, domain: domain, tolerance: tolerance, using: &execution) { jet, order, execution in
            // The callback counts original integrand visits, not scalar scratch
            // slots. Cross and each fixed-degree monomial have bounded algebra
            // and operation-local lifetime; no retained workspace grows here.
            try CurrentTaskCancellationChecker().checkCancellation(); try execution.consumeWork(1)
            let cross = jet.differentiatedUThroughSecondOrder().cross(jet.differentiatedVThroughSecondOrder())
            let x = jet.x - .constant(reference.x)
            let y = jet.y - .constant(reference.y)
            let z = jet.z - .constant(reference.z)
            func power(_ value: SurfaceIntervalJet, _ exponent: Int) -> SurfaceIntervalJet {
                var result = SurfaceIntervalJet.constant(1)
                for _ in 0..<exponent { result = result * value }
                return result
            }
            try OriginalCoefficientAllocation.reserve(count:10,of:SurfaceAreaIntegrandBounds.self, using: &execution)
            let fields = try (0..<10).map { index -> SurfaceAreaIntegrandBounds in
                let (a,b,c) = exponent(index)
                try CurrentTaskCancellationChecker().checkCancellation(); try execution.consumeWork(1)
                let native = power(x, a + 1) * power(y, b) * power(z, c) * cross.x * .constant(1 / Double(a + 1))
                let field = compose(native, u: u, v: v) * measure
                return .init(value: field.value,
                    derivativeU: order >= 2 ? field.derivativeU : nil,
                    derivativeV: order >= 2 ? field.derivativeV : nil,
                    secondUU: order >= 3 ? field.secondDerivativeUU : nil,
                    secondUV: order >= 3 ? field.secondDerivativeUV : nil,
                    secondVV: order >= 3 ? field.secondDerivativeVV : nil)
            }
            guard fields.allSatisfy({ field in
                field.value.isFinite && (field.derivativeU?.isFinite ?? true) && (field.derivativeV?.isFinite ?? true)
                    && (field.secondUU?.isFinite ?? true) && (field.secondUV?.isFinite ?? true) && (field.secondVV?.isFinite ?? true)
            }) else {
                throw Self.failure(.resourceLimitExceeded, tolerance, "Original monomial volume flux is nonfinite.")
            }
            if let prior = result {
                func union(_ a: OutwardScalarInterval?, _ b: OutwardScalarInterval?) -> OutwardScalarInterval? {
                    guard let a, let b else { return nil }; return a.union(b)
                }
                try OriginalCoefficientAllocation.reserve(count:10,of:SurfaceAreaIntegrandBounds.self, using: &execution)
                result = zip(prior, fields).map { a, b in .init(value: a.value.union(b.value),
                    derivativeU: union(a.derivativeU, b.derivativeU), derivativeV: union(a.derivativeV, b.derivativeV),
                    secondUU: union(a.secondUU, b.secondUU), secondUV: union(a.secondUV, b.secondUV),
                    secondVV: union(a.secondVV, b.secondVV)) }
            } else { result = fields }
        }
        guard let result else { throw Self.failure(.classificationFailure, tolerance, "Original volume flux lost its native cover.") }
        return result
    }

    /// Bounds exact density and three reference-centered moments over a fan square.
    package func bounds(
        curve: SurfaceParameterCurve, anchor: SurfaceParameter, reference: Point3D,
        boundaryFraction: ScalarInterval, radialFraction: ScalarInterval,
        tolerance: ModelingTolerance, domain: SurfaceAreaNativeSpanDomain? = nil,
        parameterChart: SurfaceAreaParameterChartEncloser? = nil, using execution: inout OriginalQueryExecution) throws -> [SurfaceAreaIntegrandBounds] {
        try receipt.admit(tolerance: tolerance, using: &execution)
        let proof = try chartProof(curve:curve,prepared:parameterChart,over:boundaryFraction,tolerance:tolerance, using: &execution)
        return try fanBounds(proof:proof,curve:curve,anchor:anchor,reference:reference,
            radialFraction:radialFraction,tolerance:tolerance,domain:domain, using: &execution)
    }

    /// The existing two chart/source evaluations composed as one original fan pair.
    package func pairedFanBounds(curve: SurfaceParameterCurve,
        parameterChart: SurfaceAreaParameterChartEncloser, anchor: SurfaceParameter,
        reference: Point3D, boundaryFraction: ScalarInterval, radialFraction: ScalarInterval,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution)
        throws -> (range: [SurfaceAreaIntegrandBounds], midpoint: [SurfaceAreaIntegrandBounds]) {
        let range = try chartProof(curve:curve,prepared:parameterChart,over:boundaryFraction,
            tolerance:tolerance, using: &execution)
        let midpoint = try chartProof(curve:curve,prepared:parameterChart,
            over:ScalarInterval(lower:boundaryFraction.midpoint,upper:boundaryFraction.midpoint),
            tolerance:tolerance, using: &execution)
        return try pairedFanFields(range:range,midpoint:midpoint,curve:curve,anchor:anchor,
            reference:reference,radialFraction:radialFraction,tolerance:tolerance, using: &execution)
    }

    /// A smooth original implicit chart pair composed with the same signed fan.
    package func centeredFanBounds(curve: SurfaceParameterCurve,
        parameterChart: SurfaceAreaParameterChartEncloser, anchor: SurfaceParameter,
        reference: Point3D, boundaryFraction: ScalarInterval, radialFraction: ScalarInterval,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution)
        throws -> (range: [SurfaceAreaIntegrandBounds], midpoint: [SurfaceAreaIntegrandBounds]) {
        let proof = try prepareCenteredFanChartProof(curve:curve,parameterChart:parameterChart,
            boundaryFraction:boundaryFraction,tolerance:tolerance, using: &execution)
        return try centeredFanBounds(using:proof,curve:curve,parameterChart:parameterChart,
            anchor:anchor,reference:reference,boundaryFraction:boundaryFraction,
            radialFraction:radialFraction,tolerance:tolerance, using: &execution)
    }

    /// Every actual lower preparation and phase is charged when this proof is minted.
    package func prepareCenteredFanChartProof(curve: SurfaceParameterCurve,
        parameterChart: SurfaceAreaParameterChartEncloser, boundaryFraction: ScalarInterval,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> CenteredFanChartProof {
        try receipt.admit(tolerance: tolerance, using: &execution)
        guard parameterChart.curve == curve, parameterChart.support == surface,
              parameterChart.requiresCallerWork, !parameterChart.hasNativeJoins,
              !radialIntegrationIsExact, !hasNativeDensityJumps else {
            throw Self.failure(.invalidInput,tolerance,
                "Centered fan fields require their smooth non-affine original implicit chart and support.")
        }
        let jets = try parameterChart.centeredIntervalJetsRetainingRoot(over:boundaryFraction,
            tolerance:tolerance, using: &execution)
        guard let root = jets.root else {
            throw Self.failure(.classificationFailure,tolerance,"Implicit fan preparation lost its original whole root cover.")
        }
        return CenteredFanChartProof(curve:curve,support:surface,fraction:boundaryFraction,
            tolerance:tolerance,root:root,range:jets.range,midpoint:jets.midpoint)
    }

    /// A parent whole-range proof is authority only within its original closed T domain.
    /// A changed T midpoint still executes and pays for the original singleton localizer.
    package func prepareCenteredFanChartProof(restricting parent: CenteredFanChartProof,
        curve: SurfaceParameterCurve, parameterChart: SurfaceAreaParameterChartEncloser,
        boundaryFraction: ScalarInterval, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> CenteredFanChartProof {
        try receipt.admit(tolerance: tolerance, using: &execution)
        guard parent.curve == curve, parent.support == surface, parent.tolerance == tolerance,
              parameterChart.curve == curve, parameterChart.support == surface,
              boundaryFraction.lower >= parent.fraction.lower,
              boundaryFraction.upper <= parent.fraction.upper else {
            throw Self.failure(.invalidInput,tolerance,
                "Child fan chart restriction requires its original containing parent authority.")
        }
        if boundaryFraction == parent.fraction { return parent }
        let jets = try parameterChart.centeredIntervalJets(over:boundaryFraction,
            restricting:parent.range,root:parent.root,tolerance:tolerance, using: &execution)
        return CenteredFanChartProof(curve:curve,support:surface,fraction:boundaryFraction,
            tolerance:tolerance,root:parent.root,range:jets.range,midpoint:jets.midpoint)
    }

    /// R-only subdivision reuses chart authority without repeating a root operation.
    package func centeredFanBounds(using proof: CenteredFanChartProof,
        curve: SurfaceParameterCurve, parameterChart: SurfaceAreaParameterChartEncloser,
        anchor: SurfaceParameter, reference: Point3D, boundaryFraction: ScalarInterval,
        radialFraction: ScalarInterval, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution)
        throws -> (range: [SurfaceAreaIntegrandBounds], midpoint: [SurfaceAreaIntegrandBounds]) {
        guard proof.curve == curve, proof.support == surface, proof.fraction == boundaryFraction,
              proof.tolerance == tolerance, parameterChart.curve == curve,
              parameterChart.support == surface else {
            throw Self.failure(.invalidInput,tolerance,
                "Retained centered fan chart authority belongs to another curve, support, interval or tolerance.")
        }
        return try pairedFanFields(range:.smooth(u:proof.range.u,v:proof.range.v),
            midpoint:.smooth(u:proof.midpoint.u,v:proof.midpoint.v),curve:curve,anchor:anchor,
            reference:reference,radialFraction:radialFraction,tolerance:tolerance, using: &execution)
    }

    private func pairedFanFields(range: SurfaceAreaParameterChartEncloser.IntervalProof,
        midpoint: SurfaceAreaParameterChartEncloser.IntervalProof, curve: SurfaceParameterCurve,
        anchor: SurfaceParameter, reference: Point3D, radialFraction: ScalarInterval,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution)
        throws -> (range: [SurfaceAreaIntegrandBounds], midpoint: [SurfaceAreaIntegrandBounds]) {
        let midpointR = try ScalarInterval(lower:radialFraction.midpoint,upper:radialFraction.midpoint)
        guard case .smooth(let rangeU,let rangeV) = range,
              case .smooth(let midpointU,let midpointV) = midpoint else {
            return try (fanBounds(proof:range,curve:curve,anchor:anchor,reference:reference,
                radialFraction:radialFraction,tolerance:tolerance,domain:nil, using: &execution),
                fanBounds(proof:midpoint,curve:curve,anchor:anchor,reference:reference,
                    radialFraction:midpointR,tolerance:tolerance,domain:nil, using: &execution))
        }
        let whole = try fanPullback(u:rangeU,v:rangeV,anchor:anchor,radialFraction:radialFraction,tolerance:tolerance)
        let point = try fanPullback(u:midpointU,v:midpointV,anchor:anchor,radialFraction:midpointR,tolerance:tolerance)
        if let patch = originalSingleSpanPatch(over:whole.box,midpoint:point.box), let partition = nativePartition {
            guard preparationTolerance == tolerance else {
                throw Self.failure(.invalidInput,tolerance,"A centered source pair requires its original preparation tolerance.")
            }
            guard !Task.isCancelled else { throw Self.failure(.cancelled,tolerance,"Original source range evaluation was cancelled.") }
            let rangeJet = try partition.intervalJet(of:patch,over:whole.box,tolerance:tolerance, using: &execution)
            guard !Task.isCancelled else { throw Self.failure(.cancelled,tolerance,"Original source midpoint evaluation was cancelled.") }
            let midpointJet = try partition.intervalJet(of:patch,over:point.box,tolerance:tolerance, using: &execution)
            let tightened = try Self.centeredSourceRange(rangeJet,midpoint:midpointJet,
                over:whole.box,midpointBox:point.box,tolerance:tolerance)
            return try (fields(from:tightened,order:3,u:whole.u,v:whole.v,measure:whole.measure,
                reference:reference,tolerance:tolerance, using: &execution),
                fields(from:midpointJet,order:3,u:point.u,v:point.v,measure:point.measure,
                    reference:reference,tolerance:tolerance, using: &execution))
        }
        return try (fields(over:whole.box,u:whole.u,v:whole.v,measure:whole.measure,
            reference:reference,domain:nil,tolerance:tolerance, using: &execution),
            fields(over:point.box,u:point.u,v:point.v,measure:point.measure,
                reference:reference,domain:nil,tolerance:tolerance, using: &execution))
    }

    /// Retains the same original one-sided native owner for the centered source pair.
    private func originalSingleSpanPatch(over box: SurfaceParameterBox, midpoint: SurfaceParameterBox)
        -> PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan? {
        guard case .bSpline(let stored) = surface, case .spline(let partition) = storage,
              stored == partition.surface, partition.derivativeOrder == 3,
              partition.spans.count == 1 else { return nil }
        let patch = partition.spans[0]
        guard box.u.lower >= patch.uBounds.lower, box.u.upper <= patch.uBounds.upper,
              box.v.lower >= patch.vBounds.lower, box.v.upper <= patch.vBounds.upper,
              midpoint.u.lower >= box.u.lower, midpoint.u.upper <= box.u.upper,
              midpoint.v.lower >= box.v.lower, midpoint.v.upper <= box.v.upper else { return nil }
        return patch
    }

    private func fanPullback(u chartU: SurfaceIntervalJet, v chartV: SurfaceIntervalJet,
        anchor: SurfaceParameter, radialFraction: ScalarInterval, tolerance: ModelingTolerance)
        throws -> (box: SurfaceParameterBox, u: SurfaceIntervalJet, v: SurfaceIntervalJet, measure: SurfaceIntervalJet) {
        let r = SurfaceIntervalJet.parameterV(radialFraction)
        let du = chartU - .constant(anchor.u), dv = chartV - .constant(anchor.v)
        let u = SurfaceIntervalJet.constant(anchor.u) + du*r
        let v = SurfaceIntervalJet.constant(anchor.v) + dv*r
        let box = SurfaceParameterBox(u:try clipped(u.value,to:surface.uDomain,tolerance:tolerance),
            v:try clipped(v.value,to:surface.vDomain,tolerance:tolerance))
        let measure = r*(du*chartV.differentiatedUThroughSecondOrder()-dv*chartU.differentiatedUThroughSecondOrder())
        return (box,u,v,measure)
    }

    private func fanBounds(proof: SurfaceAreaParameterChartEncloser.IntervalProof,
        curve: SurfaceParameterCurve, anchor: SurfaceParameter, reference: Point3D,
        radialFraction: ScalarInterval, tolerance: ModelingTolerance,
        domain: SurfaceAreaNativeSpanDomain?, using execution: inout OriginalQueryExecution) throws -> [SurfaceAreaIntegrandBounds] {
        try receipt.admit(tolerance: tolerance, using: &execution)
        if case .valueOnly(let u,let v,let tangentU,let tangentV) = proof {
            let radial = OutwardScalarInterval(lower:radialFraction.lower,upper:radialFraction.upper)
            let du = u - .exact(anchor.u), dv = v - .exact(anchor.v)
            let parameters = SurfaceParameterBox(
                u:try clipped(.exact(anchor.u)+du*radial,to:surface.uDomain,tolerance:tolerance),
                v:try clipped(.exact(anchor.v)+dv*radial,to:surface.vDomain,tolerance:tolerance))
            if let domain {
                guard domain.curve == curve,domain.anchor == anchor,let range = domain.radialRange,
                      radialFraction.lower >= range.lower,radialFraction.upper <= range.upper else {
                    throw Self.failure(.invalidInput,tolerance,"Native span authority does not cover the original fan cell.")
                }
            }
            return try rangeFields(over:parameters,measure:radial*(du*tangentV-dv*tangentU),
                reference:reference,domain:domain,tolerance:tolerance, using: &execution)
        }
        guard case .smooth(let chartU,let chartV) = proof else {
            throw Self.failure(.classificationFailure,tolerance,"Area fan lost its chart proof kind.")
        }
        let chart = (u:chartU,v:chartV)
        let r = SurfaceIntervalJet.parameterV(radialFraction)
        let du = chart.u - .constant(anchor.u)
        let dv = chart.v - .constant(anchor.v)
        let u: SurfaceIntervalJet = .constant(anchor.u) + du * r
        let v: SurfaceIntervalJet = .constant(anchor.v) + dv * r
        let parameters = SurfaceParameterBox(
            u: try clipped(u.value, to: surface.uDomain, tolerance: tolerance),
            v: try clipped(v.value, to: surface.vDomain, tolerance: tolerance))
        if let domain {
            guard domain.curve == curve, domain.anchor == anchor,
                  let radial = domain.radialRange,
                  radialFraction.lower >= radial.lower, radialFraction.upper <= radial.upper else {
                throw Self.failure(.invalidInput,tolerance,"Native span authority does not cover the original fan cell.")
            }
        }
        let jacobian = r * (du * chart.v.differentiatedUThroughSecondOrder()
                           - dv * chart.u.differentiatedUThroughSecondOrder())
        return try fields(over:parameters,u:u,v:v,measure:jacobian,reference:reference,domain:domain,tolerance:tolerance, using: &execution)
    }

    /// Structural affine authority permits exact radial integration for every numeric trim.
    package var radialIntegrationIsExact: Bool { originalRadialIntegrationIsExact }

    package var hasNativeDensityJumps: Bool {
        if case .nativeRollingBall = storage { return true }
        if case .nativeRuled(let partition) = storage { return partition.hasNativeJoins }
        if case .generalRollingBall(let partition) = storage { return partition.hasNativeJoins }
        if case .nativeOffset(let partition) = storage { return partition.hasNativeJoins }
        if let partition = nativePartition { return partition.derivativeOrder == 1 }
        return false
    }

    /// Native translation elimination is valid only inside its issued owning rectangle.
    package var hasNativeRectangleTranslation: Bool {
        if case .nativeRollingBall(let partition) = storage { return partition.isPiecewiseTranslation }
        return translationDirection != nil
    }

    /// The original ruled receipt remains retained beside its equivalent tensor owner.
    private var nativePartition: SurfaceAreaNativeSpanPartition? {
        switch storage {
        case .spline(let partition), .ruledTensor(_, let partition): return partition
        default: return nil
        }
    }

    package func nativeRectangleDomains(over box: SurfaceParameterBox, maximumCount: Int,
                                        tolerance: ModelingTolerance, maximumSubdivisionDepth: Int = Int.max, using execution: inout OriginalQueryExecution) throws -> [SurfaceAreaNativeSpanDomain]? {
        try receipt.admit(tolerance: tolerance, using: &execution)
        guard maximumSubdivisionDepth >= 0, maximumCount > 0 else {
            throw GeometryConversionError.resourceLimitExceeded("Original native partition exhausted caller admission.")
        }
        try execution.visitGeometricCell(depth: 0)

        func admit(_ interval:ScalarInterval,on domain:ParameterDomain) throws {
            try execution.visitGeometricCell(depth: 0)
            if case .closed(let lower,let upper) = domain,
               interval.lower < lower || interval.upper > upper {
                throw Self.failure(.classificationFailure,tolerance,"Native area partition cannot discard an out-of-support part of the original rectangle.")
            }
        }
        try admit(box.u,on:surface.uDomain); try admit(box.v,on:surface.vDomain)
        if case .nativeOffset(let partition) = storage {
            return try partition.rectangleDomains(over:box,maximumCount:maximumCount,tolerance:tolerance,maximumSubdivisionDepth:maximumSubdivisionDepth, using: &execution)
        }
        if case .nativeRollingBall(let partition) = storage {
            return try partition.rectangleDomains(over:box,maximumCount:maximumCount,tolerance:tolerance,maximumSubdivisionDepth:maximumSubdivisionDepth, using: &execution)
        }
        if case .nativeRuled(let partition) = storage {
            return try partition.rectangleDomains(over: box, maximumCount: maximumCount, tolerance: tolerance, maximumSubdivisionDepth: maximumSubdivisionDepth, using: &execution)
        }
        if case .generalRollingBall(let partition) = storage {
            return try partition.rectangleDomains(over: box, maximumCount: maximumCount, tolerance: tolerance, maximumSubdivisionDepth: maximumSubdivisionDepth, using: &execution)
        }
        if let partition = nativePartition {
            return try partition.rectangleDomains(over:box,maximumCount:maximumCount,tolerance:tolerance,maximumSubdivisionDepth:maximumSubdivisionDepth, using: &execution)
        }
        return nil
    }

    package func nativeFanDomains(curve: SurfaceParameterCurve, anchor: SurfaceParameter,
                                  maximumCount: Int, tolerance: ModelingTolerance,
                                  parameterChart: SurfaceAreaParameterChartEncloser? = nil,
                                  maximumSubdivisionDepth: Int = Int.max, using execution: inout OriginalQueryExecution) throws -> [SurfaceAreaNativeSpanDomain]? {
        try receipt.admit(tolerance: tolerance, using: &execution)
        guard maximumSubdivisionDepth >= 0, maximumCount > 0 else {
            throw GeometryConversionError.resourceLimitExceeded("Original native partition exhausted caller admission.")
        }
        try execution.visitGeometricCell(depth: 0)

        if let parameterChart, parameterChart.curve != curve || parameterChart.support != surface {
            throw Self.failure(.invalidInput,tolerance,"Native fan chart authority belongs to another retained trim or support.")
        }
        if case .nativeOffset(let partition) = storage {
            let boundary = parameterChart?.exactIsoBoundary ?? curve
            guard let domains = try partition.fanDomains(curve:boundary,anchor:anchor,maximumCount:maximumCount,tolerance:tolerance,maximumSubdivisionDepth:maximumSubdivisionDepth, using: &execution) else { return nil }
            try OriginalCoefficientAllocation.reserve(count:domains.count,of:SurfaceAreaNativeSpanDomain.self, using: &execution)
            return try domains.map { try execution.visitGeometricCell(depth: 0); return .init(rectangle:$0.rectangle,radialRange:$0.radialRange,
                index:$0.index,source:$0.source,curve:curve,anchor:anchor) }
        }
        if case .nativeRollingBall(let partition) = storage {
            let boundary = parameterChart?.exactIsoBoundary ?? curve
            guard let domains = try partition.fanDomains(curve:boundary,anchor:anchor,maximumCount:maximumCount,tolerance:tolerance,maximumSubdivisionDepth:maximumSubdivisionDepth, using: &execution) else { return nil }
            try OriginalCoefficientAllocation.reserve(count:domains.count,of:SurfaceAreaNativeSpanDomain.self, using: &execution)
            return try domains.map { try execution.visitGeometricCell(depth: 0); return .init(rectangle:$0.rectangle,radialRange:$0.radialRange,
                index:$0.index,source:$0.source,curve:curve,anchor:anchor) }
        }
        if case .nativeRuled(let partition) = storage {
            let boundary = parameterChart?.exactIsoBoundary ?? curve
            guard let domains = try partition.fanDomains(curve: boundary, anchor: anchor,
                maximumCount: maximumCount, tolerance: tolerance, maximumSubdivisionDepth: maximumSubdivisionDepth, using: &execution) else { return nil }
            try OriginalCoefficientAllocation.reserve(count:domains.count,of:SurfaceAreaNativeSpanDomain.self, using: &execution)
            return try domains.map { try execution.visitGeometricCell(depth: 0); return .init(rectangle: $0.rectangle, radialRange: $0.radialRange,
                index: $0.index, source: $0.source, curve: curve, anchor: anchor) }
        }
        if case .generalRollingBall(let partition) = storage {
            let boundary = parameterChart?.exactIsoBoundary ?? curve
            guard let domains = try partition.fanDomains(curve: boundary, anchor: anchor,
                maximumCount: maximumCount, tolerance: tolerance, maximumSubdivisionDepth: maximumSubdivisionDepth, using: &execution) else { return nil }
            try OriginalCoefficientAllocation.reserve(count:domains.count,of:SurfaceAreaNativeSpanDomain.self, using: &execution)
            return try domains.map { try execution.visitGeometricCell(depth: 0); return .init(rectangle: $0.rectangle, radialRange: $0.radialRange,
                index: $0.index, source: $0.source, curve: curve, anchor: anchor) }
        }
        if let partition = nativePartition {
            let boundary = parameterChart?.exactIsoBoundary ?? curve
            guard let domains = try partition.fanDomains(curve:boundary,anchor:anchor,maximumCount:maximumCount,tolerance:tolerance,maximumSubdivisionDepth:maximumSubdivisionDepth, using: &execution) else { return nil }
            try OriginalCoefficientAllocation.reserve(count:domains.count,of:SurfaceAreaNativeSpanDomain.self, using: &execution)
            return try domains.map { try execution.visitGeometricCell(depth: 0); return SurfaceAreaNativeSpanDomain(rectangle:$0.rectangle,radialRange:$0.radialRange,
                index:$0.index,source:$0.source,curve:curve,anchor:anchor) }
        }
        return nil
    }

    package func fanIsExactlyZero(curve: SurfaceParameterCurve, anchor: SurfaceParameter,
                                 parameterChart: SurfaceAreaParameterChartEncloser? = nil,
                                 using execution: inout OriginalQueryExecution) throws -> Bool {
        try receipt.admit(tolerance: preparationTolerance, using: &execution)
        if let parameterChart, parameterChart.curve != curve || parameterChart.support != surface { return false }
        switch parameterChart?.exactIsoBoundary ?? curve {
        case .constantU(let u,_,_): return u == anchor.u
        case .constantV(let v,_,_): return v == anchor.v
        case .affine(let origin,let direction,let start,let end):
            if start == end { return true }
            let dx = try FloatingPointExpansion.difference(origin.x,anchor.u, using: &execution)
            let dy = try FloatingPointExpansion.difference(origin.y,anchor.v, using: &execution)
            let x = try OriginalCoefficientAllocation.singleton(direction.x, using: &execution)
            let y = try OriginalCoefficientAllocation.singleton(direction.y, using: &execution)
            let first = try FloatingPointExpansion.product(dx,y, using: &execution)
            let second = try FloatingPointExpansion.product(dy,x, using: &execution)
            let determinant = try FloatingPointExpansion.subtract(first,second, using: &execution)
            return try FloatingPointExpansion.sign(determinant, using: &execution) == .zero
        default: return false
        }
    }

    package func boundaryBounds(curve: SurfaceParameterCurve, anchor: SurfaceParameter,
                                reference: Point3D, boundaryFraction: ScalarInterval,
                                tolerance: ModelingTolerance,
                                parameterChart: SurfaceAreaParameterChartEncloser? = nil, using execution: inout OriginalQueryExecution) throws -> [SurfaceAreaIntegrandBounds] {
        try receipt.admit(tolerance: tolerance, using: &execution)
        guard radialIntegrationIsExact else {
            throw Self.failure(.unsupportedCapability, tolerance, "Exact radial area requires an affine support.")
        }
        let proof = try chartProof(curve:curve,prepared:parameterChart,over:boundaryFraction,tolerance:tolerance, using: &execution)
        if case .valueOnly(let u,let v,let tangentU,let tangentV) = proof {
            let du = u - .exact(anchor.u),dv = v - .exact(anchor.v)
            let radial = OutwardScalarInterval(lower:0,upper:1)
            _ = try clipped(.exact(anchor.u)+du*radial,to:surface.uDomain,tolerance:tolerance)
            _ = try clipped(.exact(anchor.v)+dv*radial,to:surface.vDomain,tolerance:tolerance)
            let box = SurfaceParameterBox(
                u:try clipped(.exact(anchor.u),to:surface.uDomain,tolerance:tolerance),
                v:try clipped(.exact(anchor.v),to:surface.vDomain,tolerance:tolerance))
            let map = try surfaceJet(over:box,tolerance:tolerance, using: &execution)
            let cross = map.differentiatedUThroughSecondOrder().cross(map.differentiatedVThroughSecondOrder())
            guard let density = cross.dot(cross).squareRoot() else {
                throw Self.failure(.singularSystem,tolerance,"Affine area element is unresolved.")
            }
            let determinant = du*tangentV-dv*tangentU
            let area = density.value*determinant * .exact(0.5)
            try OriginalCoefficientAllocation.reserve(count:3,of:SurfaceIntervalJet.self, using: &execution)
            try OriginalCoefficientAllocation.reserve(count:3,of:Double.self, using: &execution)
            try OriginalCoefficientAllocation.reserve(count:4,of:OutwardScalarInterval.self, using: &execution)
            let point = [map.x,map.y,map.z],origins = [reference.x,reference.y,reference.z]
            var values: [OutwardScalarInterval] = []; values.reserveCapacity(4); values.append(area)
            for index in 0..<3 {
                let offset = point[index].value - .exact(origins[index])
                let displacement = point[index].derivativeU*du + point[index].derivativeV*dv
                values.append(offset*area+displacement*density.value*determinant*OutwardScalarInterval(1.0/3))
            }
            try OriginalCoefficientAllocation.reserve(count:4,of:SurfaceAreaIntegrandBounds.self, using: &execution)
            return values.map { SurfaceAreaIntegrandBounds(value:$0,derivativeU:nil,derivativeV:nil,
                secondUU:nil,secondUV:nil,secondVV:nil) }
        }
        guard case .smooth(let chartU,let chartV) = proof else {
            throw Self.failure(.classificationFailure,tolerance,"Area boundary lost its chart proof kind.")
        }
        let chart = (u:chartU,v:chartV)
        // Prove the exact boundary fan remains within the original support domain.
        let fullR = SurfaceIntervalJet.parameterV(try ScalarInterval(lower: 0, upper: 1))
        let du = chart.u - .constant(anchor.u), dv = chart.v - .constant(anchor.v)
        let fanU: SurfaceIntervalJet = .constant(anchor.u) + du * fullR
        let fanV: SurfaceIntervalJet = .constant(anchor.v) + dv * fullR
        _ = try clipped(fanU.value, to: surface.uDomain, tolerance: tolerance)
        _ = try clipped(fanV.value, to: surface.vDomain, tolerance: tolerance)
        let pointBox = SurfaceParameterBox(
            u: try clipped(.exact(anchor.u), to: surface.uDomain, tolerance: tolerance),
            v: try clipped(.exact(anchor.v), to: surface.vDomain, tolerance: tolerance))
        let map = try surfaceJet(over:pointBox,tolerance:tolerance, using: &execution)
        let areaCross = map.differentiatedUThroughSecondOrder().cross(map.differentiatedVThroughSecondOrder())
        guard let nativeDensity = areaCross.dot(areaCross).squareRoot() else {
            throw Self.failure(.singularSystem, tolerance, "Affine area element is unresolved.")
        }
        func constant(_ interval: OutwardScalarInterval) -> SurfaceIntervalJet {
            let zero = OutwardScalarInterval.exact(0)
            return SurfaceIntervalJet(value: interval, derivativeU: zero, derivativeV: zero,
                secondDerivativeUU: zero, secondDerivativeUV: zero, secondDerivativeVV: zero,
                thirdDerivativeUUU: zero, thirdDerivativeUUV: zero, thirdDerivativeUVV: zero, thirdDerivativeVVV: zero)
        }
        let density = constant(nativeDensity.value)
        let determinant = du * chart.v.differentiatedUThroughSecondOrder()
            - dv * chart.u.differentiatedUThroughSecondOrder()
        let area = density * determinant * .constant(0.5)
        try OriginalCoefficientAllocation.reserve(count:3,of:SurfaceIntervalJet.self, using: &execution)
        try OriginalCoefficientAllocation.reserve(count:3,of:Double.self, using: &execution)
        try OriginalCoefficientAllocation.reserve(count:4,of:SurfaceIntervalJet.self, using: &execution)
        let point = [map.x, map.y, map.z]
        let origins = [reference.x, reference.y, reference.z]
        var fields: [SurfaceIntervalJet] = []; fields.reserveCapacity(4); fields.append(area)
        for index in 0..<3 {
            let native = point[index]
            let offset = constant(native.value - .exact(origins[index]))
            let displacement = constant(native.derivativeU) * du + constant(native.derivativeV) * dv
            // Integral r dr = 1/2; integral r^2 dr = 1/3 exactly.
            fields.append(offset * area + displacement * density * determinant * .constant(1.0 / 3))
        }
        try OriginalCoefficientAllocation.reserve(count:4,of:SurfaceAreaIntegrandBounds.self, using: &execution)
        return fields.map { field in
            SurfaceAreaIntegrandBounds(value: field.value, derivativeU: field.derivativeU,
                derivativeV: field.derivativeV, secondUU: field.secondDerivativeUU,
                secondUV: field.secondDerivativeUV, secondVV: field.secondDerivativeVV)
        }
    }

    /// The original affine signed fan, expressed as Green fields plus endpoint primitives.
    package func centeredAffineBoundaryBounds(parameterChart: SurfaceAreaParameterChartEncloser,
        anchor: SurfaceParameter, reference: Point3D, boundaryFraction: ScalarInterval,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution)
        throws -> (range: [SurfaceAreaIntegrandBounds], midpoint: [SurfaceAreaIntegrandBounds]) {
        guard parameterChart.support == surface else {
            throw Self.failure(.invalidInput, tolerance, "Centered boundary fields require their exact prepared chart support.")
        }
        let basis = try affineBoundaryBasis(anchor:anchor,reference:reference,tolerance:tolerance, using: &execution)
        let jets = try parameterChart.centeredIntervalJets(over: boundaryFraction,
            tolerance: tolerance, using: &execution)
        func fields(_ chart: (u: SurfaceIntervalJet, v: SurfaceIntervalJet)) throws -> [SurfaceAreaIntegrandBounds] {
        try receipt.admit(tolerance: tolerance, using: &execution)
            let a = chart.u - .constant(anchor.u), b = chart.v - .constant(anchor.v)
            let radial = SurfaceIntervalJet.parameterV(try ScalarInterval(lower: 0, upper: 1))
            _ = try clipped((.constant(anchor.u) + a * radial).value, to: surface.uDomain, tolerance: tolerance)
            _ = try clipped((.constant(anchor.v) + b * radial).value, to: surface.vDomain, tolerance: tolerance)
            let tangent = b.differentiatedUThroughSecondOrder()
            let area = constantInterval(basis.density) * a * tangent
            let momentU = constantInterval(basis.density) * a * a * tangent * .constant(0.5)
            let momentV = constantInterval(basis.density) * a * b * tangent
            try OriginalCoefficientAllocation.reserve(count:4,of:SurfaceIntervalJet.self, using: &execution)
            var result: [SurfaceIntervalJet] = []; result.reserveCapacity(4); result.append(area)
            for index in 0..<3 {
                result.append(constantInterval(basis.offsets[index]) * area
                    + constantInterval(basis.columnsU[index]) * momentU
                    + constantInterval(basis.columnsV[index]) * momentV)
            }
            try OriginalCoefficientAllocation.reserve(count:4,of:SurfaceAreaIntegrandBounds.self, using: &execution)
            return result.map { SurfaceAreaIntegrandBounds(value: $0.value, derivativeU: $0.derivativeU,
                derivativeV: $0.derivativeV, secondUU: $0.secondDerivativeUU,
                secondUV: $0.secondDerivativeUV, secondVV: $0.secondDerivativeVV) }
        }
        return try (fields(jets.range), fields(jets.midpoint))
    }

    /// Keeps each original curve's endpoint correction, including rounding-sized joins.
    package func affineBoundaryCorrection(start: (u: ScalarInterval, v: ScalarInterval),
        end: (u: ScalarInterval, v: ScalarInterval), anchor: SurfaceParameter,
        reference: Point3D, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> [OutwardScalarInterval] {
        try receipt.admit(tolerance: tolerance, using: &execution)
        let basis = try affineBoundaryBasis(anchor:anchor,reference:reference,tolerance:tolerance, using: &execution)
        func primitives(_ point: (u: ScalarInterval, v: ScalarInterval)) throws -> [OutwardScalarInterval] {
            let a = OutwardScalarInterval(lower: point.u.lower, upper: point.u.upper) - .exact(anchor.u)
            let b = OutwardScalarInterval(lower: point.v.lower, upper: point.v.upper) - .exact(anchor.v)
            _ = try clipped(a + .exact(anchor.u), to: surface.uDomain, tolerance: tolerance)
            _ = try clipped(b + .exact(anchor.v), to: surface.vDomain, tolerance: tolerance)
            let area = -basis.density * a * b * .exact(0.5)
            let momentU = -basis.density * a * a * b * OutwardScalarInterval(1.0 / 6)
            let momentV = -basis.density * a * b * b * OutwardScalarInterval(1.0 / 3)
            try OriginalCoefficientAllocation.reserve(count:4,of:OutwardScalarInterval.self, using: &execution)
            var result: [OutwardScalarInterval] = []; result.reserveCapacity(4); result.append(area)
            for index in 0..<3 {
                try execution.consumeWork(1)
                result.append(
                basis.offsets[index] * area + basis.columnsU[index] * momentU
                    + basis.columnsV[index] * momentV)
            }
            return result
        }
        let first = try primitives(start), last = try primitives(end)
        try OriginalCoefficientAllocation.reserve(count:4,of:OutwardScalarInterval.self, using: &execution)
        return zip(last, first).map { $0 - $1 }
    }

    private func affineBoundaryBasis(anchor: SurfaceParameter, reference: Point3D,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> (density: OutwardScalarInterval,
        offsets: [OutwardScalarInterval], columnsU: [OutwardScalarInterval], columnsV: [OutwardScalarInterval]) {
        guard radialIntegrationIsExact else {
            throw Self.failure(.unsupportedCapability, tolerance, "Green boundary fields require an exact affine support.")
        }
        let map = try surfaceJet(over: SurfaceParameterBox(
            u: clipped(.exact(anchor.u), to: surface.uDomain, tolerance: tolerance),
            v:clipped(.exact(anchor.v),to:surface.vDomain,tolerance:tolerance)),tolerance:tolerance, using: &execution)
        let cross = map.differentiatedUThroughSecondOrder().cross(map.differentiatedVThroughSecondOrder())
        guard let density = cross.dot(cross).squareRoot() else {
            throw Self.failure(.singularSystem, tolerance, "Affine Green area density is unresolved.")
        }
        try execution.consumeWork(1)
        try OriginalCoefficientAllocation.reserve(count:3,of:OutwardScalarInterval.self, using: &execution)
        try OriginalCoefficientAllocation.reserve(count:3,of:OutwardScalarInterval.self, using: &execution)
        try OriginalCoefficientAllocation.reserve(count:3,of:OutwardScalarInterval.self, using: &execution)
        return (density.value,
            [map.x.value - .exact(reference.x),map.y.value - .exact(reference.y),map.z.value - .exact(reference.z)],
            [map.x.derivativeU,map.y.derivativeU,map.z.derivativeU],
            [map.x.derivativeV,map.y.derivativeV,map.z.derivativeV])
    }

    private func constantInterval(_ value: OutwardScalarInterval) -> SurfaceIntervalJet {
        let zero = OutwardScalarInterval.exact(0)
        return SurfaceIntervalJet(value: value, derivativeU: zero, derivativeV: zero,
            secondDerivativeUU: zero, secondDerivativeUV: zero, secondDerivativeVV: zero,
            thirdDerivativeUUU: zero, thirdDerivativeUUV: zero, thirdDerivativeUVV: zero, thirdDerivativeVVV: zero)
    }

    /// Both original endpoint fans remain in the integral. The replacement
    /// rectangle is only a measure decomposition, never a replacement trim.
    package func isoImageEndpointCorrection(image: SurfaceAreaParameterChartEncloser.IsoBoundaryImage,
        parameterChart: SurfaceAreaParameterChartEncloser,
        nominalStart: SurfaceParameter, nominalEnd: SurfaceParameter,
        anchor: SurfaceParameter, reference: Point3D, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> [OutwardScalarInterval] {
        try receipt.admit(tolerance: tolerance, using: &execution)
        try execution.consumeWork(1)
        try image.validate(for:parameterChart,on:surface,tolerance:tolerance, using: &execution)
        guard tolerance == preparationTolerance, translationDirection == image.axis else {
            throw Self.failure(.invalidInput,tolerance,"Iso-image correction lost its original translation or preparation authority.")
        }
        guard [nominalStart.u,nominalStart.v,nominalEnd.u,nominalEnd.v,anchor.u,anchor.v,
               reference.x,reference.y,reference.z].allSatisfy({ $0.isFinite }),
              case .closed(let uLow,let uHigh) = surface.uDomain,
              case .closed(let vLow,let vHigh) = surface.vDomain,
              [nominalStart,nominalEnd,anchor].allSatisfy({
                  $0.u >= uLow && $0.u <= uHigh && $0.v >= vLow && $0.v <= vHigh
              }) else {
            throw Self.failure(.invalidInput,tolerance,"Iso-image endpoint correction requires finite vertices in its original native domain.")
        }
        let fixed = image.fixedParameter
        let anchorAxis = image.axis == .v ? anchor.v : anchor.u
        let anchorOther = image.axis == .v ? anchor.u : anchor.v
        guard (image.axis == .v ? nominalStart.v : nominalStart.u) == fixed,
              (image.axis == .v ? nominalEnd.v : nominalEnd.u) == fixed else {
            throw Self.failure(.invalidInput,tolerance,"Iso-image correction requires its proved original constant axis.")
        }
        try OriginalCoefficientAllocation.reserve(count:4,of:OutwardScalarInterval.self, using: &execution)
        var total = Array(repeating:OutwardScalarInterval.exact(0),count:4)
        for index in 0..<2 {
            try execution.consumeWork(1)
            let endpoint = index == 0 ? image.start : image.end
            let nominal = index == 0 ? nominalStart : nominalEnd
            let originalOther = image.axis == .v ? endpoint.u : endpoint.v
            let nominalOther = image.axis == .v ? nominal.u : nominal.v
            let delta = OutwardScalarInterval(lower:originalOther.lower,upper:originalOther.upper) - .exact(nominalOther)
            let scale = max(1,abs(originalOther.lower),abs(originalOther.upper),abs(nominalOther),abs(fixed))
            guard delta.isFinite,delta.absoluteUpperBound <= Double.ulpOfOne * scale * 64 else {
                throw Self.failure(.invalidInput,tolerance,"Iso-image endpoint correction exceeds the original parameter connection authority.")
            }
            let orientation = (image.axis == .v ? 1.0 : -1.0) * (index == 0 ? -1.0 : 1.0)
            let signedMeasure = (.exact(anchorAxis) - .exact(fixed)) * delta * .exact(orientation * 0.5)
            let axisRange = OutwardScalarInterval(lower:min(anchorAxis,fixed),upper:max(anchorAxis,fixed))
            let otherRange = OutwardScalarInterval(lower:min(anchorOther,nominalOther,originalOther.lower),
                upper:max(anchorOther,nominalOther,originalOther.upper))
            let box = try SurfaceParameterBox(
                u:clipped(image.axis == .v ? otherRange : axisRange,to:surface.uDomain,tolerance:tolerance),
                v:clipped(image.axis == .v ? axisRange : otherRange,to:surface.vDomain,tolerance:tolerance))
            var ranges: [OutwardScalarInterval]?
            try forEachSurfaceJet(over:box,domain:nil,tolerance:tolerance, using: &execution) { jet, _, execution in
                try execution.consumeWork(1)
                let cross = jet.differentiatedUThroughSecondOrder().cross(jet.differentiatedVThroughSecondOrder())
                let normal = IntervalVector3DBounds(x:cross.x.value,y:cross.y.value,z:cross.z.value)
                let upper = normal.lengthUpperBound
                guard upper.isFinite else {
                    throw Self.failure(.classificationFailure,tolerance,"Iso-image endpoint triangle has no finite original density cover.")
                }
                let density = OutwardScalarInterval(lower:0,upper:upper)
                try OriginalCoefficientAllocation.reserve(count:4,of:OutwardScalarInterval.self, using: &execution)
                let fields = [density,(jet.x.value - .exact(reference.x))*density,
                    (jet.y.value - .exact(reference.y))*density,(jet.z.value - .exact(reference.z))*density]
                for field in fields {
                    try execution.consumeWork(1)
                    guard field.isFinite else {
                        throw Self.failure(.classificationFailure,tolerance,"Iso-image endpoint triangle has nonfinite original moment bounds.")
                    }
                }
                if let prior = ranges {
                    try OriginalCoefficientAllocation.reserve(count:4,of:OutwardScalarInterval.self, using: &execution)
                    var merged:[OutwardScalarInterval] = []; merged.reserveCapacity(4)
                    for field in 0..<4 { try execution.consumeWork(1); merged.append(prior[field].union(fields[field])) }
                    ranges = merged
                } else { ranges = fields }
            }
            guard signedMeasure.isFinite,let ranges else {
                throw Self.failure(.classificationFailure,tolerance,"Iso-image endpoint triangle lost original support coverage.")
            }
            for field in 0..<4 { try execution.consumeWork(1); total[field] = total[field] + signedMeasure * ranges[field] }
        }
        guard total.allSatisfy({ $0.isFinite }) else {
            throw Self.failure(.classificationFailure,tolerance,"Iso-image endpoint correction overflowed finite integral arithmetic.")
        }
        return total
    }

    /// Integrates a proved translation coordinate exactly over one rectangular trim.
    /// Density is independent of that coordinate and position is affine in it.
    /// Original degree-one translated rail integration on an actual native rectangle.
    /// A nil result retains the existing adaptive route for other chart families.
    package func originalRuledRectangleIntegral(
        rectangle: SurfaceParameterBox, fraction: ScalarInterval, reference: Point3D,
        tolerance: ModelingTolerance, domain: SurfaceAreaNativeSpanDomain?, using execution: inout OriginalQueryExecution) throws -> [OutwardScalarInterval]? {
        try receipt.admit(tolerance: tolerance, using: &execution)
        guard case .ruledTensor(let authority, let partition) = storage,
              translationDirection == .v, let domain else { return nil }
        guard tolerance == preparationTolerance,
              surface == .procedural(.ruled(authority.original)),
              domain.source == .bSpline(authority.tensor), domain.source == .bSpline(partition.surface),
              domain.curve == nil, domain.radialRange == nil,
              domain.rectangle == rectangle, partition.spans.indices.contains(domain.index) else {
            throw Self.failure(.invalidInput, tolerance, "Original ruled rectangle receipt belongs to another source, chart or preparation.")
        }
        let patch = partition.spans[domain.index]
        guard rectangle.u.lower >= patch.uBounds.lower, rectangle.u.upper <= patch.uBounds.upper,
              rectangle.v.lower >= patch.vBounds.lower, rectangle.v.upper <= patch.vBounds.upper,
              patch.vBounds.lower == 0, patch.vBounds.upper == 1 else {
            throw Self.failure(.invalidInput, tolerance, "Original ruled rectangle misses its owning native span.")
        }
        return try authority.rectangleIntegral(rectangle: rectangle, fraction: fraction,
            nativeLower: patch.uBounds.lower, nativeUpper: patch.uBounds.upper,
            reference: reference, tolerance: tolerance, using: &execution)
    }

    package func rectangularTranslationBounds(
        rectangle: SurfaceParameterBox, fraction: ScalarInterval, reference: Point3D,
        tolerance: ModelingTolerance, domain: SurfaceAreaNativeSpanDomain? = nil, using execution: inout OriginalQueryExecution) throws -> [SurfaceAreaIntegrandBounds] {
        try receipt.admit(tolerance: tolerance, using: &execution)
        let direction: SurfaceAreaTranslationCertificate
        if case .nativeRollingBall(let partition) = storage, partition.isPiecewiseTranslation {
            guard let domain else {
                throw Self.failure(.unsupportedCapability,tolerance,"Piecewise rolling translation requires its owning native rectangle.")
            }
            guard domain.source == surface else {
                throw Self.failure(.invalidInput,tolerance,"Rolling translation authority belongs to another original support.")
            }
            direction = .u
        } else if let global = translationDirection { direction = global }
        else {
            throw Self.failure(.unsupportedCapability, tolerance, "A surface translation certificate is required.")
        }
        if let domain {
            guard domain.curve == nil, domain.radialRange == nil, domain.rectangle == rectangle else {
                throw Self.failure(.invalidInput,tolerance,"Native span authority does not cover the translation rectangle.")
            }
        }
        // Exact elimination must preserve admission of the entire original band,
        // including endpoints that are absent from the midpoint evaluation box.
        _ = try clipped(OutwardScalarInterval(lower: rectangle.u.lower, upper: rectangle.u.upper),
                        to: surface.uDomain, tolerance: tolerance)
        _ = try clipped(OutwardScalarInterval(lower: rectangle.v.lower, upper: rectangle.v.upper),
                        to: surface.vDomain, tolerance: tolerance)
        func constant(_ interval: OutwardScalarInterval) -> SurfaceIntervalJet {
            let zero = OutwardScalarInterval.exact(0)
            return SurfaceIntervalJet(value: interval, derivativeU: zero, derivativeV: zero,
                secondDerivativeUU: zero, secondDerivativeUV: zero, secondDerivativeVV: zero,
                thirdDerivativeUUU: zero, thirdDerivativeUUV: zero, thirdDerivativeUVV: zero, thirdDerivativeVVV: zero)
        }
        let varying = direction == .v ? rectangle.u : rectangle.v
        let integrated = direction == .v ? rectangle.v : rectangle.u
        let width = OutwardScalarInterval.exact(varying.upper) - .exact(varying.lower)
        let bandWidth = OutwardScalarInterval.exact(integrated.upper) - .exact(integrated.lower)
        let midpoint = (OutwardScalarInterval.exact(integrated.lower) + .exact(integrated.upper)) * .exact(0.5)
        let t = SurfaceIntervalJet.parameterU(fraction)
        let native = constant(.exact(varying.lower)) + constant(width) * t
        let middle = constant(midpoint)
        let u = direction == .v ? native : middle
        let v = direction == .v ? middle : native
        let box = SurfaceParameterBox(u: try clipped(u.value, to: surface.uDomain, tolerance: tolerance),
                                      v: try clipped(v.value, to: surface.vDomain, tolerance: tolerance))
        let measure = constant(width * bandWidth)
        return try fields(over:box,u:u,v:v,measure:measure,reference:reference,domain:domain,tolerance:tolerance, using: &execution)
    }

    private func chartProof(curve: SurfaceParameterCurve, prepared: SurfaceAreaParameterChartEncloser?,
                          over interval: ScalarInterval, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution)
        throws -> SurfaceAreaParameterChartEncloser.IntervalProof {
        if let prepared {
            guard prepared.curve == curve, prepared.support == surface else {
                throw Self.failure(.invalidInput,tolerance,"Area chart authority belongs to another retained trim.")
            }
            return try prepared.intervalProof(over:interval,tolerance:tolerance, using: &execution)
        }
        if let maximumOriginalSubdivisionDepth {
            return try SurfaceAreaParameterChartEncloser(curve:curve,on:surface,tolerance:tolerance,
                maximumSubdivisionDepth:maximumOriginalSubdivisionDepth,remainingSourceDepth:remainingOriginalSourceDepth,
                maximumAlgebraicDepth:maximumOriginalAlgebraicDepth ?? 32, using: &execution)
                .intervalProof(over:interval,tolerance:tolerance, using: &execution)
        }
        return try SurfaceAreaParameterChartEncloser(curve:curve,on:surface,tolerance:tolerance, using: &execution)
            .intervalProof(over:interval,tolerance:tolerance, using: &execution)
    }

    private func rangeFields(over box: SurfaceParameterBox, measure: OutwardScalarInterval,
                             reference: Point3D, domain: SurfaceAreaNativeSpanDomain?,
                             tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> [SurfaceAreaIntegrandBounds] {
        var result: [OutwardScalarInterval]?
        try forEachSurfaceJet(over:box,domain:domain,tolerance:tolerance, using: &execution) { jet, _, execution in
            let cross = jet.differentiatedUThroughSecondOrder().cross(jet.differentiatedVThroughSecondOrder())
            let vector = IntervalVector3DBounds(x:cross.x.value,y:cross.y.value,z:cross.z.value)
            let density = OutwardScalarInterval(lower:vector.lengthLowerBound,upper:vector.lengthUpperBound)
            try execution.consumeWork(1)
            try OriginalCoefficientAllocation.reserve(count:4,of:OutwardScalarInterval.self, using: &execution)
            let fields = [density*measure,
                (jet.x.value - .exact(reference.x))*density*measure,
                (jet.y.value - .exact(reference.y))*density*measure,
                (jet.z.value - .exact(reference.z))*density*measure]
            if let previous = result {
                try execution.consumeWork(1)
                try OriginalCoefficientAllocation.reserve(count:4,of:OutwardScalarInterval.self, using: &execution)
                result = zip(previous,fields).map { $0.union($1) }
            }
            else { result = fields }
        }
        guard let result else { throw Self.failure(.classificationFailure,tolerance,"Area range proof has no native support coverage.") }
        try OriginalCoefficientAllocation.reserve(count:4,of:SurfaceAreaIntegrandBounds.self, using: &execution)
        return result.map { SurfaceAreaIntegrandBounds(value:$0,derivativeU:nil,derivativeV:nil,
            secondUU:nil,secondUV:nil,secondVV:nil) }
    }

    private func fields(over box: SurfaceParameterBox, u: SurfaceIntervalJet, v: SurfaceIntervalJet,
                        measure: SurfaceIntervalJet, reference: Point3D, domain: SurfaceAreaNativeSpanDomain?,
                        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> [SurfaceAreaIntegrandBounds] {
        var result: [SurfaceAreaIntegrandBounds]?
        try forEachSurfaceJet(over:box,domain:domain,tolerance:tolerance, using: &execution) { jet, order, execution in
            let values = try fields(from:jet,order:order,u:u,v:v,measure:measure,
                reference:reference,tolerance:tolerance, using: &execution)
            if let prior = result {
                func merge(_ a: OutwardScalarInterval?, _ b: OutwardScalarInterval?) -> OutwardScalarInterval? {
                    guard let a,let b else { return nil }; return a.union(b)
                }
                try execution.consumeWork(1)
                try OriginalCoefficientAllocation.reserve(count:4,of:SurfaceAreaIntegrandBounds.self, using: &execution)
                result = zip(prior,values).map { a,b in
                    SurfaceAreaIntegrandBounds(value:a.value.union(b.value),derivativeU:merge(a.derivativeU,b.derivativeU),
                        derivativeV:merge(a.derivativeV,b.derivativeV),secondUU:merge(a.secondUU,b.secondUU),
                        secondUV:merge(a.secondUV,b.secondUV),secondVV:merge(a.secondVV,b.secondVV))
                }
            } else { result = values }
        }
        guard let result else { throw Self.failure(.classificationFailure,tolerance,"Area integrand has no native support coverage.") }
        return result
    }

    /// Composes the same supplied source proof into all four physical fan fields.
    /// Source/native-span authority is owned by the enclosure caller, not this algebra.
    func fields(from jet: SurfaceIntervalVectorJet, order: Int, u: SurfaceIntervalJet,
        v: SurfaceIntervalJet, measure: SurfaceIntervalJet, reference: Point3D,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> [SurfaceAreaIntegrandBounds] {
        try execution.consumeWork(1)
        let cross = jet.differentiatedUThroughSecondOrder().cross(jet.differentiatedVThroughSecondOrder())
        try OriginalCoefficientAllocation.reserve(count:4,of:SurfaceAreaIntegrandBounds.self, using: &execution)
        if order == 0 {
            let vector = IntervalVector3DBounds(x:cross.x.value,y:cross.y.value,z:cross.z.value)
            let density = OutwardScalarInterval(lower:vector.lengthLowerBound,upper:vector.lengthUpperBound)
            func value(_ x: OutwardScalarInterval) throws -> SurfaceAreaIntegrandBounds {
                try execution.consumeWork(1)
                return .init(value:x*measure.value,derivativeU:nil,derivativeV:nil,
                    secondUU:nil,secondUV:nil,secondVV:nil)
            }
            return try [value(density),value((jet.x.value - .exact(reference.x))*density),
                value((jet.y.value - .exact(reference.y))*density),value((jet.z.value - .exact(reference.z))*density)]
        }
        guard let density = cross.dot(cross).squareRoot() else {
            throw Self.failure(.singularSystem,tolerance,"Area density is unresolved inside a smooth native span.")
        }
        func field(_ value:SurfaceIntervalJet) throws -> SurfaceAreaIntegrandBounds {
            try execution.consumeWork(1)
            let f = compose(value,u:u,v:v)*measure
            return .init(value:f.value,derivativeU:f.derivativeU,derivativeV:f.derivativeV,
                secondUU:order >= 3 ? f.secondDerivativeUU : nil,
                secondUV:order >= 3 ? f.secondDerivativeUV : nil,secondVV:order >= 3 ? f.secondDerivativeVV : nil)
        }
        return try [field(density),field((jet.x - .constant(reference.x))*density),
            field((jet.y - .constant(reference.y))*density),field((jet.z - .constant(reference.z))*density)]
    }

    /// Algebraic restriction of already-certified same-span source jets.
    /// The pair factory owns original source/span identity. This helper retains
    /// midpoint-coordinate uncertainty and never predicts a midpoint source value.
    static func centeredSourceRange(_ range: SurfaceIntervalVectorJet,
        midpoint: SurfaceIntervalVectorJet, over box: SurfaceParameterBox,
        midpointBox: SurfaceParameterBox, tolerance: ModelingTolerance) throws -> SurfaceIntervalVectorJet {
        guard midpointBox.u.lower >= box.u.lower, midpointBox.u.upper <= box.u.upper,
              midpointBox.v.lower >= box.v.lower, midpointBox.v.upper <= box.v.upper else {
            throw failure(.invalidInput,tolerance,"Source midpoint box is outside its containing range proof.")
        }
        let du = OutwardScalarInterval(lower:box.u.lower,upper:box.u.upper)
            - OutwardScalarInterval(lower:midpointBox.u.lower,upper:midpointBox.u.upper)
        let dv = OutwardScalarInterval(lower:box.v.lower,upper:box.v.upper)
            - OutwardScalarInterval(lower:midpointBox.v.lower,upper:midpointBox.v.upper)
        let uu = du*du, uv = du*dv, vv = dv*dv
        let half = OutwardScalarInterval.exact(0.5)
        let sixth = OutwardScalarInterval(1.0/6)
        func intersect(_ original: OutwardScalarInterval, _ candidate: OutwardScalarInterval) throws -> OutwardScalarInterval {
            guard original.isFinite, candidate.isFinite else {
                throw failure(.classificationFailure,tolerance,"Centered source restriction exceeded finite arithmetic.")
            }
            guard let intersection = original.intersection(with:candidate) else {
                throw failure(.classificationFailure,tolerance,"Centered source restriction contradicts its original range jet.")
            }
            return intersection
        }
        func component(_ f: SurfaceIntervalJet, _ p: SurfaceIntervalJet) throws -> SurfaceIntervalJet {
            let uuu = f.thirdDerivativeUUU, uuv = f.thirdDerivativeUUV
            let uvv = f.thirdDerivativeUVV, vvv = f.thirdDerivativeVVV
            let secondUU = try intersect(f.secondDerivativeUU,p.secondDerivativeUU+uuu*du+uuv*dv)
            let secondUV = try intersect(f.secondDerivativeUV,p.secondDerivativeUV+uuv*du+uvv*dv)
            let secondVV = try intersect(f.secondDerivativeVV,p.secondDerivativeVV+uvv*du+vvv*dv)
            let firstU = try intersect(f.derivativeU,p.derivativeU+p.secondDerivativeUU*du+p.secondDerivativeUV*dv
                + (uuu*uu + .exact(2)*uuv*uv + uvv*vv)*half)
            let firstV = try intersect(f.derivativeV,p.derivativeV+p.secondDerivativeUV*du+p.secondDerivativeVV*dv
                + (uuv*uu + .exact(2)*uvv*uv + vvv*vv)*half)
            let value = try intersect(f.value,p.value+p.derivativeU*du+p.derivativeV*dv
                + (p.secondDerivativeUU*uu + .exact(2)*p.secondDerivativeUV*uv + p.secondDerivativeVV*vv)*half
                + (uuu*uu*du + .exact(3)*uuv*uu*dv + .exact(3)*uvv*du*vv + vvv*vv*dv)*sixth)
            return SurfaceIntervalJet(value:value,derivativeU:firstU,derivativeV:firstV,
                secondDerivativeUU:secondUU,secondDerivativeUV:secondUV,secondDerivativeVV:secondVV,
                thirdDerivativeUUU:uuu,thirdDerivativeUUV:uuv,thirdDerivativeUVV:uvv,thirdDerivativeVVV:vvv)
        }
        return try SurfaceIntervalVectorJet(x:component(range.x,midpoint.x),
            y:component(range.y,midpoint.y),z:component(range.z,midpoint.z))
    }

    private func forEachSurfaceJet(over box: SurfaceParameterBox, domain: SurfaceAreaNativeSpanDomain?,
                                   tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution,
                                   _ consume: (SurfaceIntervalVectorJet, Int, inout OriginalQueryExecution) throws -> Void) throws {
        if case .nativeOffset(let partition) = storage {
            try partition.forEachJet(over:box,domain:domain,tolerance:tolerance, using: &execution,consume)
        } else if case .nativeRollingBall(let partition) = storage {
            try partition.forEachJet(over:box,domain:domain,tolerance:tolerance, using: &execution,consume)
        } else if case .nativeRuled(let partition) = storage {
            try partition.forEachJet(over: box, domain: domain, tolerance: tolerance, using: &execution, consume)
        } else if case .generalRollingBall(let partition) = storage {
            try partition.forEachJet(over: box, domain: domain, tolerance: tolerance, using: &execution, consume)
        } else if let partition = nativePartition {
            try partition.forEachJet(over:box,domain:domain,tolerance:tolerance, using: &execution,consume)
        } else {
            guard domain == nil else { throw Self.failure(.invalidInput,tolerance,"Native spline authority cannot select a procedural support.") }
            let jet = try surfaceJet(over:box,tolerance:tolerance, using: &execution)
            try consume(jet,derivativeOrder, &execution)
        }
    }

    private func surfaceJet(over box: SurfaceParameterBox,
                            tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> SurfaceIntervalVectorJet {
        switch storage {
        case .nativeRuled(let partition):
            var result: SurfaceIntervalVectorJet?
            try partition.forEachJet(over: box, domain: nil, tolerance: tolerance, using: &execution) { jet, _, execution in
                result = result.map { $0.union(jet) } ?? jet
            }
            guard let result else { throw Self.failure(.classificationFailure, tolerance, "Original ruled query has no complete native jet coverage.") }
            return result
        case .generalRollingBall(let partition):
            var result: SurfaceIntervalVectorJet?
            try partition.forEachJet(over: box, domain: nil, tolerance: tolerance, using: &execution) { jet, _, execution in
                result = result.map { $0.union(jet) } ?? jet
            }
            guard let result else { throw Self.failure(.classificationFailure, tolerance, "Original rolling-ball query has no complete native jet coverage.") }
            return result
        case .nativeOffset(let partition):
            var result: SurfaceIntervalVectorJet?
            try partition.forEachJet(over:box,domain:nil,tolerance:tolerance, using: &execution) { jet, _, execution in
                result = result.map { $0.union(jet) } ?? jet
            }
            guard let result else { throw Self.failure(.classificationFailure,tolerance,"Nested offset area box misses every original native span.") }
            return result
        case .nativeRollingBall(let partition):
            var result: SurfaceIntervalVectorJet?
            try partition.forEachJet(over:box,domain:nil,tolerance:tolerance, using: &execution) { jet, _, execution in
                result = result.map { $0.union(jet) } ?? jet
            }
            guard let result else { throw Self.failure(.classificationFailure,tolerance,"Rolling-ball area box misses every native span.") }
            return result
        case .translatedRollingBall(let prepared): return try prepared.intervalJet(over:box,tolerance:tolerance, using: &execution)
        case .direct(let prepared):
            if let maximumOriginalSubdivisionDepth {
                return try prepared.intervalJet(overClosedBox:box,tolerance:tolerance,
                    maximumSpanCount:262_144,maximumSubdivisionDepth:maximumOriginalSubdivisionDepth,
                    remainingSourceDepth:remainingOriginalSourceDepth, using: &execution)
            }
            if box.u.width == 0 || box.v.width == 0 {
                return try prepared.intervalJet(overClosedBox: box, tolerance: tolerance, using: &execution)
            }
            return try prepared.intervalJet(overClosedBox: box, tolerance: tolerance, using: &execution)
        case .offset(let offset, let source):
            return try offset.intervalJet(fromValidatedSourceJet: source.surfaceJet(over:box,tolerance:tolerance, using: &execution),
                tolerance:tolerance, using: &execution)
        case .spline(let partition), .ruledTensor(_, let partition):
            var result: SurfaceIntervalVectorJet?
            try partition.forEachJet(over:box,domain:nil,tolerance:tolerance, using: &execution) { jet, _, execution in result = result.map { $0.union(jet) } ?? jet }
            guard let result else {
                throw Self.failure(.classificationFailure, tolerance, "Area parameter box misses all exact spline spans.")
            }
            return result
        }
    }

    private func clipped(_ interval: OutwardScalarInterval, to domain: ParameterDomain,
                         tolerance: ModelingTolerance) throws -> ScalarInterval {
        var lower = interval.lower, upper = interval.upper
        if case let .closed(a, b) = domain {
            let slack = Double.ulpOfOne * max(1, abs(a), abs(b)) * 64
            guard lower >= a - slack, upper <= b + slack else {
                throw SurfaceAreaEnclosureRefinementRequired.parameterDomain
            }
            lower = max(lower, a); upper = min(upper, b)
        }
        guard lower.isFinite, upper.isFinite, lower <= upper else {
            throw Self.failure(.classificationFailure, tolerance, "Area integrand bounds are nonfinite or disjoint.")
        }
        // A degenerate chart coordinate is enlarged solely to obtain a containing surface box.
        if lower == upper {
            lower = lower.nextDown; upper = upper.nextUp
            if case let .closed(a, b) = domain { lower = max(lower, a); upper = min(upper, b) }
        }
        return try ScalarInterval(lower: lower, upper: upper)
    }

    private func compose(_ f: SurfaceIntervalJet, u: SurfaceIntervalJet,
                         v: SurfaceIntervalJet) -> SurfaceIntervalJet {
        let two = OutwardScalarInterval.exact(2)
        func second(_ a: OutwardScalarInterval, _ b: OutwardScalarInterval,
                    _ c: OutwardScalarInterval, _ d: OutwardScalarInterval) -> OutwardScalarInterval {
            f.secondDerivativeUU * a * a + two * f.secondDerivativeUV * a * b
                + f.secondDerivativeVV * b * b + f.derivativeU * c + f.derivativeV * d
        }
        let zero = OutwardScalarInterval.exact(0)
        return SurfaceIntervalJet(value: f.value,
            derivativeU: f.derivativeU * u.derivativeU + f.derivativeV * v.derivativeU,
            derivativeV: f.derivativeU * u.derivativeV + f.derivativeV * v.derivativeV,
            secondDerivativeUU: second(u.derivativeU, v.derivativeU, u.secondDerivativeUU, v.secondDerivativeUU),
            secondDerivativeUV: f.secondDerivativeUU * u.derivativeU * u.derivativeV
                + f.secondDerivativeUV * (u.derivativeU * v.derivativeV + u.derivativeV * v.derivativeU)
                + f.secondDerivativeVV * v.derivativeU * v.derivativeV
                + f.derivativeU * u.secondDerivativeUV + f.derivativeV * v.secondDerivativeUV,
            secondDerivativeVV: second(u.derivativeV, v.derivativeV, u.secondDerivativeVV, v.secondDerivativeVV),
            thirdDerivativeUUU: zero, thirdDerivativeUUV: zero, thirdDerivativeUVV: zero, thirdDerivativeVVV: zero)
    }

    private static func admitDimensions(_ surface: Surface3D, limit: Int,
                                        tolerance: ModelingTolerance, depth: Int = 0, using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        guard limit > 0, limit <= 1_048_576, depth <= 16 else {
            throw failure(.resourceLimitExceeded, tolerance, "Area geometry admission exceeds finite dimensions or nesting.")
        }
        func chart(_ value: SurfaceParameterCurve, chartDepth: Int = 0) throws {
            try execution.consumeWork(1)
            guard chartDepth <= 16 else {
                throw failure(.resourceLimitExceeded, tolerance, "Area rail chart nesting admission exceeded.")
            }
            switch value {
            case .bSpline(let spline):
                guard spline.controlPoints.count <= limit, spline.weights.count <= limit,
                      spline.knots.count <= 2 * limit + 1 else {
                    throw failure(.resourceLimitExceeded, tolerance, "Area rail chart dimension admission exceeded.")
                }
                guard spline.degree >= 1, spline.degree < spline.controlPoints.count,
                      spline.knots.count == spline.controlPoints.count + spline.degree + 1,
                      spline.weights.count == spline.controlPoints.count else {
                    throw failure(.invalidInput, tolerance, "Area rail chart spline dimensions are inconsistent.")
                }
            case .polyline(let points):
                guard points.count <= limit else {
                    throw failure(.resourceLimitExceeded,tolerance,"Original area polyline chart dimension admission exceeded.")
                }
                for _ in points { try execution.consumeWork(1) }
            case .originalImage(let image): try chart(image.source.parameterCurve,chartDepth:chartDepth+1)
            case .originalAffineWord(let image): try chart(image.source.parameterCurve,chartDepth:chartDepth+1)
            case .periodicTranslation(let base, _, _): try chart(base, chartDepth: chartDepth + 1)
            case .offsetSurfaceImage(let image): try chart(image.source, chartDepth: chartDepth + 1)
            case .affine, .constantU, .constantV, .harmonic: break
            default:
                throw failure(.unsupportedCapability, tolerance, "Area rail chart has no certified derivative admission.")
            }
        }
        func curve(_ value: Curve3D, curveDepth: Int = 0) throws {
            try execution.consumeWork(1)
            guard depth + curveDepth <= 16 else {
                throw failure(.resourceLimitExceeded,tolerance,"Original area curve dimension source depth is exhausted.")
            }
            switch value {
            case .originalPolyline(let polyline):
                guard polyline.points.count <= limit else {
                    throw failure(.resourceLimitExceeded, tolerance, "Area original polyline point admission exceeded.")
                }
                for point in polyline.points { try execution.consumeWork(1); try point.validate() }
            case .originalGuideEndpointConnector(let connector):
                try curve(connector.source.source,curveDepth:curveDepth+2)
                try curve(connector.startBoundary.source,curveDepth:curveDepth+2)
                try curve(connector.endBoundary.source,curveDepth:curveDepth+2)
            case .originalGuideTraversalChain(let chain):
                for traversal in chain.traversals {
                    try execution.consumeWork(1)
                    try curve(traversal.source,curveDepth:curveDepth+2)
                }
            case .originalDrafted(let drafted):
                try curve(drafted.generator.source,curveDepth:curveDepth+2)
            case .originalPlaneDerivative(let connector):
                try curve(connector.source.source,curveDepth:curveDepth+2)
                for constraint in connector.startConstraints {
                    try execution.consumeWork(1); try admitDimensions(constraint.surface,limit:limit,tolerance:tolerance,
                        depth:depth+curveDepth+1, using: &execution)
                }
                for constraint in connector.endConstraints {
                    try execution.consumeWork(1); try admitDimensions(constraint.surface,limit:limit,tolerance:tolerance,
                        depth:depth+curveDepth+1, using: &execution)
                }
            case .originalEndpointConnector(let connector):
                try curve(.bSpline(connector.construction),curveDepth:curveDepth+1)
                try curve(connector.startBoundary.source,curveDepth:curveDepth+2)
                try curve(connector.endBoundary.source,curveDepth:curveDepth+2)
            case .originalConstructionChart(let image): try curve(image.source,curveDepth:curveDepth+1)
            case .originalAngularTransport(let image): try curve(image.source,curveDepth:curveDepth+1)
            case .rigidImage(let image): try curve(image.source,curveDepth:curveDepth+1)
            case .affineImage(let image): try curve(image.source,curveDepth:curveDepth+1)
            case .parameterImage(let image): try curve(image.source,curveDepth:curveDepth+1)
            case .originalAffineWord(let image): try curve(image.source,curveDepth:curveDepth+1)
            case .bSpline(let spline):
                guard spline.controlPoints.count <= limit, spline.weights.count <= limit,
                      spline.knots.count <= 2 * limit + 1 else {
                    throw failure(.resourceLimitExceeded, tolerance, "Area curve dimension admission exceeded.")
                }
                guard spline.degree >= 1, spline.degree < spline.controlPoints.count,
                      spline.knots.count == spline.controlPoints.count + spline.degree + 1,
                      spline.weights.count == spline.controlPoints.count else {
                    throw failure(.invalidInput, tolerance, "Area curve spline dimensions are inconsistent.")
                }
            case .surfaceLift(let lift):
                try chart(lift.parameterCurve)
                try admitDimensions(lift.surface, limit: limit, tolerance: tolerance,
                    depth: depth + curveDepth + 1, using: &execution)
            default: break
            }
        }
        switch surface {
        case .bSpline(let spline):
            let uCount = spline.controlPoints.first?.count ?? 0
            let vCount = spline.controlPoints.count
            guard vCount <= limit, try spline.controlPoints.allSatisfy({ try execution.consumeWork(1); return $0.count <= limit }),
                  spline.weights.count <= limit, try spline.weights.allSatisfy({ try execution.consumeWork(1); return $0.count <= limit }),
                  spline.uKnots.count <= 2 * limit + 1, spline.vKnots.count <= 2 * limit + 1 else {
                throw failure(.resourceLimitExceeded, tolerance, "Area surface dimension admission exceeded.")
            }
            guard uCount > 0, vCount > 0, spline.uDegree >= 1, spline.uDegree < uCount,
                  spline.vDegree >= 1, spline.vDegree < vCount,
                  spline.uKnots.count == uCount + spline.uDegree + 1,
                  spline.vKnots.count == vCount + spline.vDegree + 1,
                  spline.weights.count == vCount,
                  try spline.controlPoints.allSatisfy({ try execution.consumeWork(1); return $0.count == uCount }),
                  try spline.weights.allSatisfy({ try execution.consumeWork(1); return $0.count == uCount }) else {
                throw failure(.invalidInput, tolerance, "Area surface spline dimensions are inconsistent.")
            }
        case .procedural(.originalAffineWord(let image)):
            try admitDimensions(image.source, limit: limit, tolerance: tolerance, depth: depth + 1, using: &execution)
        case .procedural(.originalImage(let image)):
            try admitDimensions(image.source, limit: limit, tolerance: tolerance, depth: depth + 1, using: &execution)
        case .procedural(.offset(let offset)):
            try admitDimensions(offset.source, limit: limit, tolerance: tolerance, depth: depth + 1, using: &execution)
        case .procedural(.originalRevolution(let revolution)):
            try curve(revolution.generator.source)
        case .procedural(.originalDrafted(let drafted)):
            try curve(.originalDrafted(drafted.start),curveDepth:1)
        case .procedural(.originalPlaneDerivative(let corrected)):
            try admitDimensions(.procedural(.originalBoundaryCorrected(corrected.construction)),
                limit:limit,tolerance:tolerance,depth:depth+1, using: &execution)
            try admitDimensions(.procedural(.originalCoons(corrected.boundaries)),
                limit:limit,tolerance:tolerance,depth:depth+1, using: &execution)
            for constraint in corrected.startConstraints {
                try execution.consumeWork(1); try admitDimensions(constraint.surface,limit:limit,tolerance:tolerance,depth:depth+1, using: &execution)
            }
            for constraint in corrected.endConstraints {
                try execution.consumeWork(1); try admitDimensions(constraint.surface,limit:limit,tolerance:tolerance,depth:depth+1, using: &execution)
            }
        case .procedural(.originalBoundaryCorrected(let corrected)):
            try admitDimensions(.bSpline(corrected.construction), limit: limit, tolerance: tolerance, depth: depth + 1, using: &execution)
            try admitDimensions(.procedural(.originalCoons(corrected.boundaries)), limit: limit, tolerance: tolerance, depth: depth + 1, using: &execution)
        case .procedural(.originalCoons(let coons)):
            try curve(coons.vMinimumBoundary.source); try curve(coons.vMaximumBoundary.source)
            try curve(coons.uMinimumBoundary.source); try curve(coons.uMaximumBoundary.source)
        case .procedural(.ruled(let ruled)):
            try curve(ruled.startBoundary); try curve(ruled.endBoundary)
        case .procedural(.rollingBall(let blend)):
            try curve(blend.centerSpine); try curve(blend.firstContact); try curve(blend.secondContact)
        default: break
        }
    }

    private static func curveOrder(_ curve: Curve3D, tolerance: ModelingTolerance,
        maximumSubdivisionDepth:Int? = nil,remainingSourceDepth:Int = 16,
        maximumAlgebraicDepth:Int? = nil, using execution: inout OriginalQueryExecution) throws -> Int {
        try execution.consumeWork(1)
        guard remainingSourceDepth >= 0 else {
            throw failure(.resourceLimitExceeded,tolerance,"Original area rail exhausted source depth.")
        }
        func child(_ value:Curve3D) throws -> Int {
            try curveOrder(value,tolerance:tolerance,
                maximumSubdivisionDepth:maximumSubdivisionDepth,remainingSourceDepth:remainingSourceDepth-1,
                maximumAlgebraicDepth:maximumAlgebraicDepth, using: &execution)
        }
        switch curve {
        case .bSpline(let spline):
            guard let first=spline.knots.first,let last=spline.knots.last else {
                throw failure(.invalidInput,tolerance,"Original area rail has no native knots.")
            }
            var index=0,order=3
            while index<spline.knots.count {
                try execution.consumeWork(1)
                var end=index+1
                while end<spline.knots.count,spline.knots[end]==spline.knots[index] {
                    try execution.consumeWork(1); end+=1
                }
                if spline.knots[index]>first,spline.knots[index]<last {
                    order=min(order,spline.degree-(end-index)+1)
                }
                index=end
            }
            return order
        case .surfaceLift(let lift):
            if let maximumSubdivisionDepth {
                _ = try OriginalParameterCurveHigherTaylor.enclosure(lift.parameterCurve,
                    over:ScalarInterval(lower:0,upper:1),order:3,tolerance:tolerance,
                    maximumSpanCount:262_144,maximumSubdivisionDepth:maximumSubdivisionDepth,
                    remainingSourceDepth:remainingSourceDepth-1,maximumAlgebraicDepth:maximumAlgebraicDepth, using: &execution)
            } else {
                guard try SurfaceParameterIntervalJet.enclose(lift.parameterCurve,
                    over:ScalarInterval(lower:0,upper:1),tolerance:tolerance, using: &execution) != nil else {
                    throw failure(.unsupportedCapability,tolerance,"Area rail requires its original parameter derivatives.")
                }
            }
            return try PreparedSurfaceAreaIntegrand(surface:lift.surface,tolerance:tolerance,maximumSubdivisionDepth:maximumSubdivisionDepth,
                remainingSourceDepth:remainingSourceDepth-1,maximumAlgebraicDepth:maximumAlgebraicDepth, using: &execution).derivativeOrder
        case .rigidImage(let image): return try child(image.source)
        case .affineImage(let image): return try child(image.source)
        case .parameterImage(let image): return try child(image.source)
        case .originalAffineWord(let image): return try child(image.source)
        case .originalAngularTransport(let image): return try child(image.source)
        case .originalGuideEndpointConnector(let connector):
            // A smooth endpoint correction cannot improve a raw guide join.
            return try curveOrder(connector.source.source,tolerance:tolerance,
                maximumSubdivisionDepth:maximumSubdivisionDepth,remainingSourceDepth:remainingSourceDepth-2,
                maximumAlgebraicDepth:maximumAlgebraicDepth, using: &execution)
        case .originalGuideTraversalChain(let chain):
            try chain.validate(tolerance:tolerance, using: &execution)
            return chain.provenContinuityOrder
        case .originalDrafted(let drafted):
            return try drafted.hasOriginalFirstOrderContinuity(
                over:ScalarInterval(lower:0,upper:1),tolerance:tolerance,
                maximumSpanCount:262_144,
                maximumSubdivisionDepth:maximumSubdivisionDepth ?? execution.effectiveLimits.maximumSubdivisionDepth,
                remainingSourceDepth:remainingSourceDepth, using: &execution) ? 1 : 0
        case .originalPlaneDerivative(let image):
            // The retained endpoint correction is a single smooth polynomial.
            // It cannot improve continuity across an original source join.
            return try curveOrder(image.source.source,tolerance:tolerance,
                maximumSubdivisionDepth:maximumSubdivisionDepth,remainingSourceDepth:remainingSourceDepth-2,
                maximumAlgebraicDepth:maximumAlgebraicDepth, using: &execution)
        case .line,.circle,.analytic: return 3
        case .originalPolyline: return 0
        default:
            // FIXME(INCOMPLETE_IMPLEMENTATION): General constructed/root charts
            // need original continuity-order admission before this area-rail
            // partition selector can establish complete source-domain support.
            throw failure(.unsupportedCapability,tolerance,
                "Area procedural support has no certified derivative-order admission for its source curve.")
        }
    }

    private static func failure(_ code: KernelErrorCode, _ tolerance: ModelingTolerance,
                                _ message: String) -> KernelError {
        KernelError(phase: .geometry, code: code, tolerance: tolerance, message: message)
    }
}
