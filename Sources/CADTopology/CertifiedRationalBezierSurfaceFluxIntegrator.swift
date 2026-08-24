import CADCore
import CADGeometry
import Foundation

/// Certifies a rectangular rational B-spline surface-flux integral. Every
/// active clamped or non-clamped span is reconstructed from outward-rounded
/// homogeneous basis derivatives. Tensor three-point Gauss values are widened
/// by sixth-derivative remainder bounds from each complete control net.
struct CertifiedRationalBezierSurfaceFluxIntegrator {
    enum AxisAlignedProjection: Sendable, Hashable {
        case normalX
        case normalY
        case normalZ
    }

    struct Bounds: Sendable, Hashable {
        let lower: Double
        let upper: Double

        var errorRadius: Double {
            (upper - lower) * 0.5
        }
    }

    struct PreparedField {
        struct SecondOrderBounds {
            typealias Interval = CertifiedUnivariateTaylorJet.Interval

            let value: Interval
            let derivativeU: Interval
            let derivativeV: Interval
            let secondDerivativeUU: Interval
            let secondDerivativeUV: Interval
            let secondDerivativeVV: Interval
        }

        struct ParameterSpan: Sendable, Hashable {
            let lower: Double
            let upper: Double
        }

        private struct SourcePatch {
            let patch: Patch
            let uLower: Double
            let uUpper: Double
            let vLower: Double
            let vUpper: Double
        }

        private let patches: [SourcePatch]
        private let sourceSurface: BSplineSurface3D
        private let reference: Point3D
        private let tolerance: ModelingTolerance

        let uSpans: [ParameterSpan]
        let vSpans: [ParameterSpan]

        fileprivate init(
            certifiedPatches: [CertifiedHomogeneousBezierSurfacePatch],
            sourceSurface: BSplineSurface3D,
            reference: Point3D,
            includeFluxNumerator: Bool,
            tolerance: ModelingTolerance
        ) throws {
            patches = try certifiedPatches.map {
                SourcePatch(
                    patch: try Patch(
                        certified: $0,
                        reference: reference,
                        includeFluxNumerator: includeFluxNumerator,
                        tolerance: tolerance
                    ),
                    uLower: $0.uLower,
                    uUpper: $0.uUpper,
                    vLower: $0.vLower,
                    vUpper: $0.vUpper
                )
            }
            self.sourceSurface = sourceSurface
            self.reference = reference
            self.tolerance = tolerance
            uSpans = Self.distinctSpans(
                certifiedPatches.map {
                    ParameterSpan(lower: $0.uLower, upper: $0.uUpper)
                }
            )
            vSpans = Self.distinctSpans(
                certifiedPatches.map {
                    ParameterSpan(lower: $0.vLower, upper: $0.vUpper)
                }
            )
        }

        func exactPlanarAffineFluxTraversal(
            for curve: CertifiedImplicitSurfaceParameterCurve
        ) throws -> CertifiedPlanarAffineFluxTraversal? {
            try curve.exactPlanarAffineFluxTraversal(
                on: sourceSurface,
                reference: reference,
                tolerance: tolerance
            )
        }

        func containingVSpan(
            _ range: TrimmedAnalyticSurfaceVolumeEvaluator.Interval
        ) -> ParameterSpan? {
            containingSpan(range, candidates: vSpans)
        }

        func strictlyContainingVSpan(
            _ range: TrimmedAnalyticSurfaceVolumeEvaluator.Interval
        ) -> ParameterSpan? {
            vSpans.first {
                range.lower >= $0.lower && range.upper <= $0.upper
            }
        }

        func containingUSpan(
            _ range: TrimmedAnalyticSurfaceVolumeEvaluator.Interval
        ) -> ParameterSpan? {
            containingSpan(range, candidates: uSpans)
        }

        func bounds(
            uLower: Double,
            uUpper: Double,
            vLower: Double,
            vUpper: Double
        ) throws -> Bounds {
            guard uLower.isFinite,
                  uUpper.isFinite,
                  vLower.isFinite,
                  vUpper.isFinite,
                  uLower <= uUpper,
                  vLower <= vUpper else {
                throw KernelError(
                    phase: .topology,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "Certified rational surface flux range requires finite ordered parameter bounds."
                )
            }
            var ranges: [Interval] = []
            for source in patches {
                let overlapULower = max(uLower, source.uLower)
                let overlapUUpper = min(uUpper, source.uUpper)
                let overlapVLower = max(vLower, source.vLower)
                let overlapVUpper = min(vUpper, source.vUpper)
                guard overlapULower <= overlapUUpper,
                      overlapVLower <= overlapVUpper else {
                    continue
                }
                let uSpan = Interval.exact(source.uUpper)
                    - Interval.exact(source.uLower)
                let vSpan = Interval.exact(source.vUpper)
                    - Interval.exact(source.vLower)
                guard uSpan.lower > 0.0,
                      vSpan.lower > 0.0 else {
                    throw KernelError(
                        phase: .topology,
                        code: .topologyFailure,
                        tolerance: tolerance,
                        message: "Certified rational surface flux field contains a degenerate Bezier patch."
                    )
                }
                let localU = Interval(
                    lower: overlapULower,
                    upper: overlapUUpper
                ) - .exact(source.uLower)
                let localV = Interval(
                    lower: overlapVLower,
                    upper: overlapVUpper
                ) - .exact(source.vLower)
                let flux = try source.patch.flux(
                    u: localU / uSpan,
                    v: localV / vSpan,
                    tolerance: tolerance
                ) / (uSpan * vSpan)
                ranges.append(flux)
            }
            guard !ranges.isEmpty else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "Certified rational surface flux range does not overlap an extracted Bezier patch."
                )
            }
            let result = Interval.hull(ranges)
            return Bounds(lower: result.lower, upper: result.upper)
        }

        func bounds(
            u: TrimmedAnalyticSurfaceVolumeEvaluator.Interval,
            v: TrimmedAnalyticSurfaceVolumeEvaluator.Interval,
            uSpan: ParameterSpan,
            vSpan: ParameterSpan
        ) throws -> Bounds {
            guard let source = patches.first(where: {
                $0.uLower == uSpan.lower
                    && $0.uUpper == uSpan.upper
                    && $0.vLower == vSpan.lower
                    && $0.vUpper == vSpan.upper
            }) else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "Certified rational surface flux could not bind a point range to its Bezier patch."
                )
            }
            let clippedU = Interval(
                lower: max(u.lower, source.uLower),
                upper: min(u.upper, source.uUpper)
            )
            let clippedV = Interval(
                lower: max(v.lower, source.vLower),
                upper: min(v.upper, source.vUpper)
            )
            guard clippedU.lower <= clippedU.upper,
                  clippedV.lower <= clippedV.upper else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "Certified rational surface flux point range does not overlap its Bezier patch."
                )
            }
            let uWidth = Interval.exact(source.uUpper) - .exact(source.uLower)
            let vWidth = Interval.exact(source.vUpper) - .exact(source.vLower)
            guard uWidth.lower > 0.0, vWidth.lower > 0.0 else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "Certified rational surface flux field contains a degenerate Bezier patch."
                )
            }
            let normalizedU = (clippedU - .exact(source.uLower)) / uWidth
            let normalizedV = (clippedV - .exact(source.vLower)) / vWidth
            let flux = try source.patch.flux(
                u: normalizedU,
                v: normalizedV,
                tolerance: tolerance
            ) / (uWidth * vWidth)
            return Bounds(lower: flux.lower, upper: flux.upper)
        }

        func directionalFluxJet(
            u: CertifiedUnivariateTaylorJet,
            v: CertifiedUnivariateTaylorJet,
            uSpan: ParameterSpan,
            vSpan: ParameterSpan
        ) throws -> CertifiedUnivariateTaylorJet {
            guard let source = patches.first(where: {
                $0.uLower == uSpan.lower
                    && $0.uUpper == uSpan.upper
                    && $0.vLower == vSpan.lower
                    && $0.vUpper == vSpan.upper
            }) else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "Certified rational surface flux could not bind a directional jet to its Bezier patch."
                )
            }
            let clippedURange = CertifiedUnivariateTaylorJet.Interval(
                lower: max(u.value.lower, uSpan.lower),
                upper: min(u.value.upper, uSpan.upper)
            )
            let clippedVRange = CertifiedUnivariateTaylorJet.Interval(
                lower: max(v.value.lower, vSpan.lower),
                upper: min(v.value.upper, vSpan.upper)
            )
            guard clippedURange.lower <= clippedURange.upper,
                  clippedVRange.lower <= clippedVRange.upper else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "Certified rational surface flux directional jet does not overlap its Bezier patch."
                )
            }
            var patchU = u
            var patchV = v
            patchU.coefficients[0] = clippedURange
            patchV.coefficients[0] = clippedVRange
            let uWidth = Interval.exact(source.uUpper) - .exact(source.uLower)
            let vWidth = Interval.exact(source.vUpper) - .exact(source.vLower)
            let normalizedU = try (patchU - .constant(source.uLower)).divided(
                by: .constant(CertifiedUnivariateTaylorJet.Interval(
                    lower: uWidth.lower,
                    upper: uWidth.upper
                )),
                tolerance: tolerance
            )
            let normalizedV = try (patchV - .constant(source.vLower)).divided(
                by: .constant(CertifiedUnivariateTaylorJet.Interval(
                    lower: vWidth.lower,
                    upper: vWidth.upper
                )),
                tolerance: tolerance
            )
            // A directional jet is already evaluated over its certified value
            // box. Reparameterizing a trimmed patch scales its derivatives by
            // inverse powers of a small restriction width; although those
            // factors cancel algebraically, interval arithmetic loses the
            // correlation and can inflate higher derivatives by many orders
            // of magnitude. Positive Bernstein weights certify the original
            // patch denominator directly, so evaluate the original patch and
            // apply only the source-domain scale.
            let localFlux = try source.patch.directionalFluxJet(
                u: normalizedU,
                v: normalizedV,
                tolerance: tolerance
            )
            return try localFlux.divided(
                by: .constant(CertifiedUnivariateTaylorJet.Interval(
                    lower: (uWidth * vWidth).lower,
                    upper: (uWidth * vWidth).upper
                )),
                tolerance: tolerance
            )
        }

        func secondOrderBounds(
            u: CertifiedUnivariateTaylorJet.Interval,
            v: CertifiedUnivariateTaylorJet.Interval,
            uSpan: ParameterSpan,
            vSpan: ParameterSpan
        ) throws -> SecondOrderBounds {
            typealias TaylorInterval = CertifiedUnivariateTaylorJet.Interval
            func evaluate(
                u localU: TaylorInterval,
                v localV: TaylorInterval
            ) throws -> SecondOrderBounds {
                let one = TaylorInterval.exact(1.0)
                let uVariable = CertifiedUnivariateTaylorJet.series([localU, one])
                let vVariable = CertifiedUnivariateTaylorJet.series([localV, one])
                let constantU = CertifiedUnivariateTaylorJet.constant(localU)
                let constantV = CertifiedUnivariateTaylorJet.constant(localV)
                let alongU = try directionalFluxJet(
                    u: uVariable,
                    v: constantV,
                    uSpan: uSpan,
                    vSpan: vSpan
                )
                let alongV = try directionalFluxJet(
                    u: constantU,
                    v: vVariable,
                    uSpan: uSpan,
                    vSpan: vSpan
                )
                let alongDiagonal = try directionalFluxJet(
                    u: uVariable,
                    v: vVariable,
                    uSpan: uSpan,
                    vSpan: vSpan
                )
                let two = TaylorInterval.exact(2.0)
                return SecondOrderBounds(
                    value: alongDiagonal.coefficients[0],
                    derivativeU: alongU.coefficients[1],
                    derivativeV: alongV.coefficients[1],
                    secondDerivativeUU: alongU.coefficients[2] * two,
                    secondDerivativeUV: alongDiagonal.coefficients[2]
                        - alongU.coefficients[2]
                        - alongV.coefficients[2],
                    secondDerivativeVV: alongV.coefficients[2] * two
                )
            }
            let subdivisionCount = 4
            let uBoundaries = (0...subdivisionCount).map { index in
                u.lower + (u.upper - u.lower)
                    * Double(index) / Double(subdivisionCount)
            }
            let vBoundaries = (0...subdivisionCount).map { index in
                v.lower + (v.upper - v.lower)
                    * Double(index) / Double(subdivisionCount)
            }
            var localBounds: [SecondOrderBounds] = []
            localBounds.reserveCapacity(subdivisionCount * subdivisionCount)
            for vIndex in 0..<subdivisionCount {
                for uIndex in 0..<subdivisionCount {
                    localBounds.append(try evaluate(
                        u: TaylorInterval(
                            lower: uBoundaries[uIndex],
                            upper: uBoundaries[uIndex + 1]
                        ),
                        v: TaylorInterval(
                            lower: vBoundaries[vIndex],
                            upper: vBoundaries[vIndex + 1]
                        )
                    ))
                }
            }
            return SecondOrderBounds(
                value: TaylorInterval(
                    lower: localBounds.map(\.value.lower).min() ?? -.infinity,
                    upper: localBounds.map(\.value.upper).max() ?? .infinity
                ),
                derivativeU: TaylorInterval(
                    lower: localBounds.map(\.derivativeU.lower).min() ?? -.infinity,
                    upper: localBounds.map(\.derivativeU.upper).max() ?? .infinity
                ),
                derivativeV: TaylorInterval(
                    lower: localBounds.map(\.derivativeV.lower).min() ?? -.infinity,
                    upper: localBounds.map(\.derivativeV.upper).max() ?? .infinity
                ),
                secondDerivativeUU: TaylorInterval(
                    lower: localBounds.map(\.secondDerivativeUU.lower).min()
                        ?? -.infinity,
                    upper: localBounds.map(\.secondDerivativeUU.upper).max()
                        ?? .infinity
                ),
                secondDerivativeUV: TaylorInterval(
                    lower: localBounds.map(\.secondDerivativeUV.lower).min()
                        ?? -.infinity,
                    upper: localBounds.map(\.secondDerivativeUV.upper).max()
                        ?? .infinity
                ),
                secondDerivativeVV: TaylorInterval(
                    lower: localBounds.map(\.secondDerivativeVV.lower).min()
                        ?? -.infinity,
                    upper: localBounds.map(\.secondDerivativeVV.upper).max()
                        ?? .infinity
                )
            )
        }

        func projectedBoundaryAreaJet(
            u: CertifiedUnivariateTaylorJet,
            v: CertifiedUnivariateTaylorJet,
            projection: AxisAlignedProjection,
            uSpan: ParameterSpan,
            vSpan: ParameterSpan
        ) throws -> CertifiedUnivariateTaylorJet {
            guard let source = patches.first(where: {
                $0.uLower == uSpan.lower
                    && $0.uUpper == uSpan.upper
                    && $0.vLower == vSpan.lower
                    && $0.vUpper == vSpan.upper
            }) else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "Certified rational planar area could not bind a curve jet to its Bezier patch."
                )
            }
            let clippedURange = CertifiedUnivariateTaylorJet.Interval(
                lower: max(u.value.lower, uSpan.lower),
                upper: min(u.value.upper, uSpan.upper)
            )
            let clippedVRange = CertifiedUnivariateTaylorJet.Interval(
                lower: max(v.value.lower, vSpan.lower),
                upper: min(v.value.upper, vSpan.upper)
            )
            guard clippedURange.lower <= clippedURange.upper,
                  clippedVRange.lower <= clippedVRange.upper else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "Certified rational planar area curve jet does not overlap its Bezier patch."
                )
            }
            var patchU = u
            var patchV = v
            patchU.coefficients[0] = clippedURange
            patchV.coefficients[0] = clippedVRange
            let uWidth = Interval.exact(source.uUpper) - .exact(source.uLower)
            let vWidth = Interval.exact(source.vUpper) - .exact(source.vLower)
            let normalizedU = try (patchU - .constant(source.uLower)).divided(
                by: .constant(CertifiedUnivariateTaylorJet.Interval(
                    lower: uWidth.lower,
                    upper: uWidth.upper
                )),
                tolerance: tolerance
            )
            let normalizedV = try (patchV - .constant(source.vLower)).divided(
                by: .constant(CertifiedUnivariateTaylorJet.Interval(
                    lower: vWidth.lower,
                    upper: vWidth.upper
                )),
                tolerance: tolerance
            )
            let uRestriction = Self.positiveRestriction(
                containing: normalizedU.value
            )
            let vRestriction = Self.positiveRestriction(
                containing: normalizedV.value
            )
            let restrictedPatch = try source.patch.trimmed(
                uLower: uRestriction.lower,
                uUpper: uRestriction.upper,
                vLower: vRestriction.lower,
                vUpper: vRestriction.upper,
                sourceUDomain: .closed(0.0, 1.0),
                sourceVDomain: .closed(0.0, 1.0),
                includeFluxNumerator: false,
                tolerance: tolerance
            )
            let restrictedU = try (
                normalizedU - .constant(uRestriction.lower)
            ).divided(
                by: .constant(uRestriction.upper - uRestriction.lower),
                tolerance: tolerance
            )
            let restrictedV = try (
                normalizedV - .constant(vRestriction.lower)
            ).divided(
                by: .constant(vRestriction.upper - vRestriction.lower),
                tolerance: tolerance
            )
            return try restrictedPatch.projectedBoundaryAreaJet(
                u: restrictedU,
                v: restrictedV,
                projection: projection,
                tolerance: tolerance
            )
        }

        func projectedBoundaryAreaRange(
            u: CertifiedUnivariateTaylorJet,
            v: CertifiedUnivariateTaylorJet,
            projection: AxisAlignedProjection
        ) throws -> CertifiedUnivariateTaylorJet.Interval {
            let candidateUSpans = overlappingSpans(u.value, candidates: uSpans)
            let candidateVSpans = overlappingSpans(v.value, candidates: vSpans)
            guard !candidateUSpans.isEmpty, !candidateVSpans.isEmpty else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "Certified rational planar area does not overlap an extracted Bezier patch."
                )
            }
            var ranges: [CertifiedUnivariateTaylorJet.Interval] = []
            ranges.reserveCapacity(candidateUSpans.count * candidateVSpans.count)
            for uSpan in candidateUSpans {
                for vSpan in candidateVSpans {
                    ranges.append(try projectedBoundaryAreaJet(
                        u: u,
                        v: v,
                        projection: projection,
                        uSpan: uSpan,
                        vSpan: vSpan
                    ).coefficients[0])
                }
            }
            return CertifiedUnivariateTaylorJet.Interval(
                lower: (ranges.map(\.lower).min() ?? -.infinity).nextDown,
                upper: (ranges.map(\.upper).max() ?? .infinity).nextUp
            )
        }

        private static func positiveRestriction(
            containing range: CertifiedUnivariateTaylorJet.Interval
        ) -> (lower: Double, upper: Double) {
            var lower = max(0.0, range.lower)
            var upper = min(1.0, range.upper)
            let minimumWidth = 1.0 / 16.0
            if upper - lower >= minimumWidth {
                return (lower, upper)
            }
            let center = min(1.0, max(0.0, (lower + upper) * 0.5))
            lower = max(0.0, center - minimumWidth * 0.5)
            upper = min(1.0, lower + minimumWidth)
            lower = max(0.0, upper - minimumWidth)
            return (lower, upper)
        }

        private func containingSpan(
            _ range: TrimmedAnalyticSurfaceVolumeEvaluator.Interval,
            candidates: [ParameterSpan]
        ) -> ParameterSpan? {
            if let exact = candidates.first(where: {
                range.lower >= $0.lower && range.upper <= $0.upper
            }) {
                return exact
            }
            return candidates.first(where: { candidate in
                let scale = max(1.0, abs(candidate.lower), abs(candidate.upper))
                let slack = Double.ulpOfOne * scale * 512.0
                return range.lower >= candidate.lower - slack
                    && range.upper <= candidate.upper + slack
            })
        }

        private func overlappingSpans(
            _ range: TrimmedAnalyticSurfaceVolumeEvaluator.Interval,
            candidates: [ParameterSpan]
        ) -> [ParameterSpan] {
            candidates.filter { candidate in
                let scale = max(1.0, abs(candidate.lower), abs(candidate.upper))
                let slack = Double.ulpOfOne * scale * 512.0
                return range.upper >= candidate.lower - slack
                    && range.lower <= candidate.upper + slack
            }
        }

        private static func distinctSpans(
            _ spans: [ParameterSpan]
        ) -> [ParameterSpan] {
            spans.sorted {
                $0.lower == $1.lower
                    ? $0.upper < $1.upper
                    : $0.lower < $1.lower
            }.reduce(into: []) { result, span in
                if result.last != span {
                    result.append(span)
                }
            }
        }
    }

    private let maximumSubdivisionDepth: Int
    private let maximumCellCount: Int
    private let maximumExtractionControlOperations: Int

    init(
        maximumSubdivisionDepth: Int = 10,
        maximumCellCount: Int = 1_000_000,
        maximumExtractionControlOperations: Int = 4_000_000
    ) {
        self.maximumSubdivisionDepth = maximumSubdivisionDepth
        self.maximumCellCount = maximumCellCount
        self.maximumExtractionControlOperations = maximumExtractionControlOperations
    }

    func preparedField(
        surface: BSplineSurface3D,
        reference: Point3D,
        includeFluxNumerator: Bool = true,
        tolerance: ModelingTolerance
    ) throws -> PreparedField? {
        try tolerance.validate()
        guard let extracted = try CertifiedBSplineSurfaceBezierExtractor(
            maximumControlOperations: maximumExtractionControlOperations
        ).patches(surface: surface, tolerance: tolerance) else {
            return nil
        }
        guard !extracted.isEmpty else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Certified rational surface flux field extracted no active Bezier patch."
            )
        }
        return try PreparedField(
            certifiedPatches: extracted,
            sourceSurface: surface,
            reference: reference,
            includeFluxNumerator: includeFluxNumerator,
            tolerance: tolerance
        )
    }

    func integrate(
        surface: BSplineSurface3D,
        uLower: Double,
        uUpper: Double,
        vLower: Double,
        vUpper: Double,
        reference: Point3D,
        requestedError: Double,
        tolerance: ModelingTolerance
    ) throws -> Bounds? {
        try tolerance.validate()
        guard requestedError.isFinite, requestedError > 0.0 else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                residual: requestedError,
                tolerance: tolerance,
                message: "Certified rational surface flux requires a positive finite error bound."
            )
        }
        guard case let .closed(sourceULower, sourceUUpper) = surface.uDomain,
              case let .closed(sourceVLower, sourceVUpper) = surface.vDomain,
              uLower.isFinite,
              uUpper.isFinite,
              vLower.isFinite,
              vUpper.isFinite,
              uLower >= sourceULower,
              uUpper <= sourceUUpper,
              vLower >= sourceVLower,
              vUpper <= sourceVUpper,
              uUpper > uLower,
              vUpper > vLower else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Certified rational surface flux requires a positive trim inside the source domain."
            )
        }
        guard let extracted = try CertifiedBSplineSurfaceBezierExtractor(
            maximumControlOperations: maximumExtractionControlOperations
        ).patches(surface: surface, tolerance: tolerance) else {
            return nil
        }
        let activePatches = extracted.compactMap { source -> ActivePatch? in
            let activeULower = max(uLower, source.uLower)
            let activeUUpper = min(uUpper, source.uUpper)
            let activeVLower = max(vLower, source.vLower)
            let activeVUpper = min(vUpper, source.vUpper)
            guard activeUUpper > activeULower,
                  activeVUpper > activeVLower else {
                return nil
            }
            return ActivePatch(
                source: source,
                uLower: activeULower,
                uUpper: activeUUpper,
                vLower: activeVLower,
                vUpper: activeVUpper
            )
        }
        guard !activePatches.isEmpty else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Certified rational surface flux trim did not intersect a Bezier span."
            )
        }
        var budget = CellBudget(limit: maximumCellCount)
        let perPatchError = requestedError * 0.99 / Double(activePatches.count)
        var total = Interval.exact(0.0)
        for active in activePatches {
            let patch = try Patch(
                certified: active.source,
                reference: reference,
                tolerance: tolerance
            ).trimmed(
                uLower: active.uLower,
                uUpper: active.uUpper,
                vLower: active.vLower,
                vUpper: active.vUpper,
                sourceUDomain: .closed(active.source.uLower, active.source.uUpper),
                sourceVDomain: .closed(active.source.vLower, active.source.vUpper),
                tolerance: tolerance
            )
            total = total + (try certifiedIntegral(
                patch: patch,
                reference: reference,
                requestedError: perPatchError,
                depth: 0,
                budget: &budget,
                tolerance: tolerance
            ))
        }
        return Bounds(lower: total.lower, upper: total.upper)
    }

    private func certifiedIntegral(
        patch: Patch,
        reference: Point3D,
        requestedError: Double,
        depth: Int,
        budget: inout CellBudget,
        tolerance: ModelingTolerance
    ) throws -> Interval {
        try budget.consume(tolerance: tolerance)
        let enclosure = try cellEnclosure(
            patch: patch,
            reference: reference,
            tolerance: tolerance
        )
        if enclosure.errorRadius <= requestedError {
            return enclosure
        }
        guard depth < maximumSubdivisionDepth else {
            throw KernelError(
                phase: .topology,
                code: .resourceLimitExceeded,
                residual: enclosure.errorRadius,
                tolerance: tolerance,
                message: "Certified rational surface flux exhausted its subdivision depth."
            )
        }
        let children = try patch.subdivided(tolerance: tolerance)
        var result = Interval.exact(0.0)
        for child in children {
            let childIntegral = try certifiedIntegral(
                patch: child,
                reference: reference,
                requestedError: requestedError * 0.25,
                depth: depth + 1,
                budget: &budget,
                tolerance: tolerance
            )
            result = result + childIntegral
        }
        return result
    }

    private func cellEnclosure(
        patch: Patch,
        reference: Point3D,
        tolerance: ModelingTolerance
    ) throws -> Interval {
        let nodes = try Self.gaussNodes(tolerance: tolerance)
        var quadrature = Interval.exact(0.0)
        for u in nodes {
            for v in nodes {
                let value = try patch.flux(
                    u: u.value,
                    v: v.value,
                    tolerance: tolerance
                )
                quadrature = quadrature + value * u.weight * v.weight
            }
        }
        let sixthU = try patch.sixthFluxDerivativeBound(
            primary: .u,
            reference: reference,
            tolerance: tolerance
        )
        let sixthV = try patch.sixthFluxDerivativeBound(
            primary: .v,
            reference: reference,
            tolerance: tolerance
        )
        let remainder = ((sixthU + sixthV) / Interval.exact(2_016_000.0))
            .maximumAbsolute
            .nextUp
        guard remainder.isFinite else {
            throw KernelError(
                phase: .topology,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "Certified rational surface flux remainder exceeded finite arithmetic."
            )
        }
        return Interval(
            lower: (quadrature.lower - remainder).nextDown,
            upper: (quadrature.upper + remainder).nextUp
        )
    }

    private static func gaussNodes(
        tolerance: ModelingTolerance
    ) throws -> [(value: Interval, weight: Interval)] {
        let displacement = try (
            Interval.exact(3.0) / Interval.exact(5.0)
        ).squareRoot(tolerance: tolerance)
        let half = Interval.exact(0.5)
        return [
            (
                value: half * (Interval.exact(1.0) - displacement),
                weight: Interval.exact(5.0) / Interval.exact(18.0)
            ),
            (
                value: half,
                weight: Interval.exact(4.0) / Interval.exact(9.0)
            ),
            (
                value: half * (Interval.exact(1.0) + displacement),
                weight: Interval.exact(5.0) / Interval.exact(18.0)
            ),
        ]
    }

    private enum Direction: Equatable {
        case u
        case v
    }

    private struct ActivePatch {
        let source: CertifiedHomogeneousBezierSurfacePatch
        let uLower: Double
        let uUpper: Double
        let vLower: Double
        let vUpper: Double
    }

    private struct Patch {
        let controls: [[HomogeneousPoint]]
        let reference: Point3D
        private let fluxNumerator: ScalarPolynomial2D?

        var hasExactConstantWeight: Bool {
            guard let first = controls.first?.first?.weight,
                  first.lower == first.upper else {
                return false
            }
            return controls.allSatisfy { row in
                !row.isEmpty && row.allSatisfy {
                    $0.weight.lower == first.lower
                        && $0.weight.upper == first.upper
                }
            }
        }

        init(
            certified: CertifiedHomogeneousBezierSurfacePatch,
            reference: Point3D,
            includeFluxNumerator: Bool = true,
            tolerance: ModelingTolerance
        ) throws {
            let controls = certified.controls.map { row in
                row.map { point in
                    HomogeneousPoint(
                        x: Interval(lower: point.x.lower, upper: point.x.upper),
                        y: Interval(lower: point.y.lower, upper: point.y.upper),
                        z: Interval(lower: point.z.lower, upper: point.z.upper),
                        weight: Interval(
                            lower: point.weight.lower,
                            upper: point.weight.upper
                        )
                    )
                }
            }
            self.init(
                controls: controls,
                reference: reference,
                fluxNumerator: includeFluxNumerator
                    ? try Self.makeFluxNumerator(
                        controls: controls,
                        reference: reference,
                        tolerance: tolerance
                    )
                    : nil
            )
        }

        private init(
            controls: [[HomogeneousPoint]],
            reference: Point3D,
            fluxNumerator: ScalarPolynomial2D?
        ) {
            self.controls = controls
            self.reference = reference
            self.fluxNumerator = fluxNumerator
        }

        func trimmed(
            uLower: Double,
            uUpper: Double,
            vLower: Double,
            vUpper: Double,
            sourceUDomain: ParameterDomain,
            sourceVDomain: ParameterDomain,
            includeFluxNumerator: Bool = true,
            tolerance: ModelingTolerance
        ) throws -> Patch {
            let uBounds = try Self.normalizedBounds(
                lower: uLower,
                upper: uUpper,
                domain: sourceUDomain,
                tolerance: tolerance
            )
            let vBounds = try Self.normalizedBounds(
                lower: vLower,
                upper: vUpper,
                domain: sourceVDomain,
                tolerance: tolerance
            )
            var net = controls
            net = Self.trimRows(net, bounds: uBounds)
            net = Self.transpose(Self.trimRows(Self.transpose(net), bounds: vBounds))
            let uScale = uBounds.upper - uBounds.lower
            let vScale = vBounds.upper - vBounds.lower
            let trimmedFluxNumerator = includeFluxNumerator
                ? fluxNumerator.map {
                    $0.trimmed(u: uBounds, v: vBounds)
                        .scaled(by: uScale * vScale)
                }
                : nil
            return Patch(
                controls: net,
                reference: reference,
                fluxNumerator: trimmedFluxNumerator
            )
        }

        func subdivided(tolerance: ModelingTolerance) throws -> [Patch] {
            guard let fluxNumerator else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "Certified rational surface flux subdivision requires a prepared determinant polynomial."
                )
            }
            let uHalves = Self.splitRows(controls, parameter: .exact(0.5))
            let lowerV = Self.splitRows(
                Self.transpose(uHalves.lower),
                parameter: .exact(0.5)
            )
            let upperV = Self.splitRows(
                Self.transpose(uHalves.upper),
                parameter: .exact(0.5)
            )
            let lower = BoundsPair(
                lower: .exact(0.0),
                upper: .exact(0.5)
            )
            let upper = BoundsPair(
                lower: .exact(0.5),
                upper: .exact(1.0)
            )
            let scale = Interval.exact(0.25)
            return [
                Patch(
                    controls: Self.transpose(lowerV.lower),
                    reference: reference,
                    fluxNumerator: fluxNumerator
                        .trimmed(u: lower, v: lower)
                        .scaled(by: scale)
                ),
                Patch(
                    controls: Self.transpose(upperV.lower),
                    reference: reference,
                    fluxNumerator: fluxNumerator
                        .trimmed(u: upper, v: lower)
                        .scaled(by: scale)
                ),
                Patch(
                    controls: Self.transpose(lowerV.upper),
                    reference: reference,
                    fluxNumerator: fluxNumerator
                        .trimmed(u: lower, v: upper)
                        .scaled(by: scale)
                ),
                Patch(
                    controls: Self.transpose(upperV.upper),
                    reference: reference,
                    fluxNumerator: fluxNumerator
                        .trimmed(u: upper, v: upper)
                        .scaled(by: scale)
                ),
            ]
        }

        func flux(
            u: Interval,
            v: Interval,
            tolerance: ModelingTolerance
        ) throws -> Interval {
            guard let fluxNumerator else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "Certified rational surface flux evaluation requires a prepared determinant polynomial."
                )
            }
            guard let restrictedU = u.intersection(.unit),
                  let restrictedV = v.intersection(.unit) else {
                throw KernelError(
                    phase: .topology,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "Certified rational surface flux parameters do not overlap the patch domain."
                )
            }
            let evaluatedWeight = try derivativeValue(
                component: \HomogeneousPoint.weight,
                uOrder: 0,
                vOrder: 0,
                u: restrictedU,
                v: restrictedV,
                tolerance: tolerance
            )
            let weight = try certifiedWeightIntersection(
                evaluatedWeight,
                tolerance: tolerance
            )
            let numerator = fluxNumerator.evaluated(
                u: restrictedU,
                v: restrictedV
            )
            return numerator
                / (weight * weight * weight)
                / Interval.exact(3.0)
        }

        func directionalFluxJet(
            u: CertifiedUnivariateTaylorJet,
            v: CertifiedUnivariateTaylorJet,
            tolerance: ModelingTolerance
        ) throws -> CertifiedUnivariateTaylorJet {
            guard let fluxNumerator else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "Certified rational directional flux requires a prepared determinant polynomial."
                )
            }
            var weight = try univariateValue(
                component: \HomogeneousPoint.weight,
                uOrder: 0,
                vOrder: 0,
                u: u,
                v: v,
                tolerance: tolerance
            )
            weight.coefficients[0] = try certifiedWeightIntersection(
                weight.coefficients[0],
                tolerance: tolerance
            )
            let inverseWeight = try weight.reciprocal(tolerance: tolerance)
            let numerator = fluxNumerator.evaluated(u: u, v: v)
            return try (
                numerator * inverseWeight * inverseWeight * inverseWeight
            ).divided(by: .constant(3.0), tolerance: tolerance)
        }

        func projectedBoundaryAreaJet(
            u: CertifiedUnivariateTaylorJet,
            v: CertifiedUnivariateTaylorJet,
            projection: AxisAlignedProjection,
            tolerance: ModelingTolerance
        ) throws -> CertifiedUnivariateTaylorJet {
            let components: (
                first: KeyPath<HomogeneousPoint, Interval>,
                second: KeyPath<HomogeneousPoint, Interval>
            )
            switch projection {
            case .normalX:
                components = (\HomogeneousPoint.y, \HomogeneousPoint.z)
            case .normalY:
                components = (\HomogeneousPoint.z, \HomogeneousPoint.x)
            case .normalZ:
                components = (\HomogeneousPoint.x, \HomogeneousPoint.y)
            }
            let first = try univariateValue(
                component: components.first,
                uOrder: 0,
                vOrder: 0,
                u: u,
                v: v,
                tolerance: tolerance
            )
            let second = try univariateValue(
                component: components.second,
                uOrder: 0,
                vOrder: 0,
                u: u,
                v: v,
                tolerance: tolerance
            )
            var weight = try univariateValue(
                component: \HomogeneousPoint.weight,
                uOrder: 0,
                vOrder: 0,
                u: u,
                v: v,
                tolerance: tolerance
            )
            weight.coefficients[0] = try certifiedWeightIntersection(
                weight.coefficients[0],
                tolerance: tolerance
            )
            let inverseWeight = try weight.reciprocal(tolerance: tolerance)
            return try (
                (first * second.derivative() - second * first.derivative())
                    * inverseWeight * inverseWeight
            ).divided(by: .constant(2.0), tolerance: tolerance)
        }

        private static func makeFluxNumerator(
            controls: [[HomogeneousPoint]],
            reference: Point3D,
            tolerance: ModelingTolerance
        ) throws -> ScalarPolynomial2D {
            let weight = ScalarPolynomial2D(
                controls.map { $0.map(\.weight) }
            )
            let x = try ScalarPolynomial2D(
                controls.map { $0.map(\.x) }
            ).subtracting(
                weight.scaled(by: reference.x),
                tolerance: tolerance
            )
            let y = try ScalarPolynomial2D(
                controls.map { $0.map(\.y) }
            ).subtracting(
                weight.scaled(by: reference.y),
                tolerance: tolerance
            )
            let z = try ScalarPolynomial2D(
                controls.map { $0.map(\.z) }
            ).subtracting(
                weight.scaled(by: reference.z),
                tolerance: tolerance
            )
            let xU = x.derivativeU()
            let yU = y.derivativeU()
            let zU = z.derivativeU()
            let xV = x.derivativeV()
            let yV = y.derivativeV()
            let zV = z.derivativeV()
            let xTerm = try (yU * zV).subtracting(
                zU * yV,
                tolerance: tolerance
            )
            let yTerm = try (zU * xV).subtracting(
                xU * zV,
                tolerance: tolerance
            )
            let zTerm = try (xU * yV).subtracting(
                yU * xV,
                tolerance: tolerance
            )
            return try (x * xTerm).adding(
                y * yTerm,
                tolerance: tolerance
            ).adding(
                z * zTerm,
                tolerance: tolerance
            )
        }

        private struct ScalarPolynomial2D {
            let coefficients: [[Interval]]

            private var uDegree: Int {
                (coefficients.first?.count ?? 1) - 1
            }

            private var vDegree: Int {
                coefficients.count - 1
            }

            init(_ coefficients: [[Interval]]) {
                self.coefficients = coefficients
            }

            func derivativeU() -> Self {
                Self(coefficients.map { row in
                    (0..<uDegree).map { index in
                        (row[index + 1] - row[index])
                            * .exact(Double(uDegree))
                    }
                })
            }

            func derivativeV() -> Self {
                Self((0..<vDegree).map { rowIndex in
                    coefficients[rowIndex].indices.map { columnIndex in
                        (coefficients[rowIndex + 1][columnIndex]
                            - coefficients[rowIndex][columnIndex])
                            * .exact(Double(vDegree))
                    }
                })
            }

            func scaled(by value: Double) -> Self {
                scaled(by: .exact(value))
            }

            func scaled(by scale: Interval) -> Self {
                return Self(coefficients.map { row in
                    row.map { $0 * scale }
                })
            }

            func trimmed(u: BoundsPair, v: BoundsPair) -> Self {
                let uTrimmed = Self.trimLines(coefficients, bounds: u)
                let transposed = Self.transpose(uTrimmed)
                let vTrimmed = Self.trimLines(transposed, bounds: v)
                return Self(Self.transpose(vTrimmed))
            }

            func evaluated(
                u: CertifiedUnivariateTaylorJet,
                v: CertifiedUnivariateTaylorJet
            ) -> CertifiedUnivariateTaylorJet {
                let rows = coefficients.map {
                    Patch.evaluateUnivariate($0, parameter: u)
                }
                return Patch.evaluateUnivariate(rows, parameter: v)
            }

            func evaluated(u: Interval, v: Interval) -> Interval {
                let rows = coefficients.map {
                    Patch.evaluate($0, parameter: u)
                }
                return Patch.evaluate(rows, parameter: v)
            }

            func adding(
                _ other: Self,
                tolerance: ModelingTolerance
            ) throws -> Self {
                try validateMatchingDegree(other, tolerance: tolerance)
                return Self(coefficients.indices.map { row in
                    coefficients[row].indices.map { column in
                        coefficients[row][column]
                            + other.coefficients[row][column]
                    }
                })
            }

            func subtracting(
                _ other: Self,
                tolerance: ModelingTolerance
            ) throws -> Self {
                try validateMatchingDegree(other, tolerance: tolerance)
                return Self(coefficients.indices.map { row in
                    coefficients[row].indices.map { column in
                        coefficients[row][column]
                            - other.coefficients[row][column]
                    }
                })
            }

            private func validateMatchingDegree(
                _ other: Self,
                tolerance: ModelingTolerance
            ) throws {
                guard uDegree == other.uDegree,
                      vDegree == other.vDegree else {
                    throw KernelError(
                        phase: .topology,
                        code: .topologyFailure,
                        tolerance: tolerance,
                        message: "Certified flux polynomial addition requires matching bidegrees."
                    )
                }
            }

            static func * (lhs: Self, rhs: Self) -> Self {
                let outputUDegree = lhs.uDegree + rhs.uDegree
                let outputVDegree = lhs.vDegree + rhs.vDegree
                var output = Array(
                    repeating: Array(
                        repeating: Interval.exact(0.0),
                        count: outputUDegree + 1
                    ),
                    count: outputVDegree + 1
                )
                for outputV in 0...outputVDegree {
                    let lhsVLower = max(0, outputV - rhs.vDegree)
                    let lhsVUpper = min(lhs.vDegree, outputV)
                    for outputU in 0...outputUDegree {
                        let lhsULower = max(0, outputU - rhs.uDegree)
                        let lhsUUpper = min(lhs.uDegree, outputU)
                        var coefficient = Interval.exact(0.0)
                        for lhsV in lhsVLower...lhsVUpper {
                            let rhsV = outputV - lhsV
                            let vWeight = productWeight(
                                lhsDegree: lhs.vDegree,
                                lhsIndex: lhsV,
                                rhsDegree: rhs.vDegree,
                                rhsIndex: rhsV
                            )
                            for lhsU in lhsULower...lhsUUpper {
                                let rhsU = outputU - lhsU
                                let uWeight = productWeight(
                                    lhsDegree: lhs.uDegree,
                                    lhsIndex: lhsU,
                                    rhsDegree: rhs.uDegree,
                                    rhsIndex: rhsU
                                )
                                coefficient = coefficient
                                    + lhs.coefficients[lhsV][lhsU]
                                    * rhs.coefficients[rhsV][rhsU]
                                    * uWeight * vWeight
                            }
                        }
                        output[outputV][outputU] = coefficient
                    }
                }
                return Self(output)
            }

            private static func productWeight(
                lhsDegree: Int,
                lhsIndex: Int,
                rhsDegree: Int,
                rhsIndex: Int
            ) -> Interval {
                binomial(lhsDegree, lhsIndex)
                    * binomial(rhsDegree, rhsIndex)
                    / binomial(
                        lhsDegree + rhsDegree,
                        lhsIndex + rhsIndex
                    )
            }

            private static func binomial(_ degree: Int, _ index: Int) -> Interval {
                let reducedIndex = min(index, degree - index)
                guard reducedIndex > 0 else { return .exact(1.0) }
                var value = Interval.exact(1.0)
                for factor in 1...reducedIndex {
                    value = value
                        * .exact(Double(degree - reducedIndex + factor))
                        / .exact(Double(factor))
                }
                return value
            }

            private static func trimLines(
                _ lines: [[Interval]],
                bounds: BoundsPair
            ) -> [[Interval]] {
                lines.map { line in
                    var current = line
                    if bounds.lower.upper > 0.0 {
                        current = split(current, parameter: bounds.lower).upper
                    }
                    if bounds.upper.lower < 1.0 {
                        let localUpper = (bounds.upper - bounds.lower)
                            / (Interval.exact(1.0) - bounds.lower)
                        current = split(current, parameter: localUpper).lower
                    }
                    return current
                }
            }

            private static func split(
                _ values: [Interval],
                parameter: Interval
            ) -> (lower: [Interval], upper: [Interval]) {
                let complement = Interval.exact(1.0) - parameter
                var levels = [values]
                while let previous = levels.last, previous.count > 1 {
                    levels.append((0..<(previous.count - 1)).map { index in
                        previous[index] * complement
                            + previous[index + 1] * parameter
                    })
                }
                return (
                    levels.map { $0[0] },
                    levels.reversed().map { $0[$0.count - 1] }
                )
            }

            private static func transpose(
                _ values: [[Interval]]
            ) -> [[Interval]] {
                guard let first = values.first else { return [] }
                return first.indices.map { column in
                    values.indices.map { row in values[row][column] }
                }
            }
        }

        private func univariateValue(
            component: KeyPath<HomogeneousPoint, Interval>,
            uOrder: Int,
            vOrder: Int,
            u: CertifiedUnivariateTaylorJet,
            v: CertifiedUnivariateTaylorJet,
            tolerance: ModelingTolerance
        ) throws -> CertifiedUnivariateTaylorJet {
            let net = try derivativeNet(
                component: component,
                uOrder: uOrder,
                vOrder: vOrder,
                tolerance: tolerance
            )
            let rows = net.map {
                Self.evaluateUnivariate($0, parameter: u)
            }
            return Self.evaluateUnivariate(rows, parameter: v)
        }

        private func certifiedWeightIntersection(
            _ evaluated: Interval,
            tolerance: ModelingTolerance
        ) throws -> Interval {
            let controlHull = Interval.hull(
                controls.flatMap { row in row.map(\.weight) }
            )
            guard let certified = evaluated.intersection(controlHull),
                  certified.lower > 0.0 else {
                throw KernelError(
                    phase: .topology,
                    code: .singularSystem,
                    residual: evaluated.lower,
                    tolerance: tolerance,
                    message: "Certified rational surface flux could not prove a positive point weight."
                )
            }
            return certified
        }

        private func certifiedWeightIntersection(
            _ evaluated: CertifiedUnivariateTaylorJet.Interval,
            tolerance: ModelingTolerance
        ) throws -> CertifiedUnivariateTaylorJet.Interval {
            let interval = try certifiedWeightIntersection(
                Interval(lower: evaluated.lower, upper: evaluated.upper),
                tolerance: tolerance
            )
            return CertifiedUnivariateTaylorJet.Interval(
                lower: interval.lower,
                upper: interval.upper
            )
        }

        private static func evaluateUnivariate(
            _ values: [Interval],
            parameter: CertifiedUnivariateTaylorJet
        ) -> CertifiedUnivariateTaylorJet {
            evaluateUnivariate(
                values.map {
                    CertifiedUnivariateTaylorJet.constant(
                        CertifiedUnivariateTaylorJet.Interval(
                            lower: $0.lower,
                            upper: $0.upper
                        )
                    )
                },
                parameter: parameter
            )
        }

        private static func evaluateUnivariate(
            _ values: [CertifiedUnivariateTaylorJet],
            parameter: CertifiedUnivariateTaylorJet
        ) -> CertifiedUnivariateTaylorJet {
            var level = values
            let complement = CertifiedUnivariateTaylorJet.constant(1.0) - parameter
            while level.count > 1 {
                level = (0..<(level.count - 1)).map { index in
                    level[index] * complement + level[index + 1] * parameter
                }
            }
            return level[0]
        }

        func sixthFluxDerivativeBound(
            primary: Direction,
            reference: Point3D,
            tolerance: ModelingTolerance
        ) throws -> Interval {
            let valueX = try coordinateJet(
                component: \HomogeneousPoint.x,
                primary: primary,
                tolerance: tolerance
            )
            let valueY = try coordinateJet(
                component: \HomogeneousPoint.y,
                primary: primary,
                tolerance: tolerance
            )
            let valueZ = try coordinateJet(
                component: \HomogeneousPoint.z,
                primary: primary,
                tolerance: tolerance
            )
            let weight = try coordinateJet(
                component: \HomogeneousPoint.weight,
                primary: primary,
                tolerance: tolerance
            )
            let secondaryWeight = try secondaryCoordinateJet(
                component: \HomogeneousPoint.weight,
                primary: primary,
                tolerance: tolerance
            )
            let reciprocalWeight = try weight.reciprocal(tolerance: tolerance)
            let squaredReciprocal = reciprocalWeight * reciprocalWeight

            let position = IntervalVectorJet(
                x: valueX * reciprocalWeight,
                y: valueY * reciprocalWeight,
                z: valueZ * reciprocalWeight
            ).truncated(to: 6)
            let primaryTangent = positionFromFullJets(
                x: valueX * reciprocalWeight,
                y: valueY * reciprocalWeight,
                z: valueZ * reciprocalWeight
            ).derivative()
            let secondaryX = try secondaryEuclideanJet(
                value: valueX,
                secondary: secondaryCoordinateJet(
                    component: \HomogeneousPoint.x,
                    primary: primary,
                    tolerance: tolerance
                ),
                weight: weight,
                secondaryWeight: secondaryWeight,
                squaredReciprocal: squaredReciprocal
            )
            let secondaryY = try secondaryEuclideanJet(
                value: valueY,
                secondary: secondaryCoordinateJet(
                    component: \HomogeneousPoint.y,
                    primary: primary,
                    tolerance: tolerance
                ),
                weight: weight,
                secondaryWeight: secondaryWeight,
                squaredReciprocal: squaredReciprocal
            )
            let secondaryZ = try secondaryEuclideanJet(
                value: valueZ,
                secondary: secondaryCoordinateJet(
                    component: \HomogeneousPoint.z,
                    primary: primary,
                    tolerance: tolerance
                ),
                weight: weight,
                secondaryWeight: secondaryWeight,
                squaredReciprocal: squaredReciprocal
            )
            let secondaryTangent = IntervalVectorJet(
                x: secondaryX,
                y: secondaryY,
                z: secondaryZ
            )
            let tangentU = primary == .u ? primaryTangent : secondaryTangent
            let tangentV = primary == .u ? secondaryTangent : primaryTangent
            let relative = position.subtracting(reference)
            let flux = relative.dot(tangentU.cross(tangentV))
                .scaled(by: Interval.exact(1.0) / Interval.exact(3.0))
            guard flux.values.count == 7 else {
                throw KernelError(
                    phase: .topology,
                    code: .resourceLimitExceeded,
                    tolerance: tolerance,
                    message: "Certified rational surface flux did not construct a sixth derivative jet."
                )
            }
            return flux.values[6]
        }

        private func secondaryEuclideanJet(
            value: IntervalJet,
            secondary: IntervalJet,
            weight: IntervalJet,
            secondaryWeight: IntervalJet,
            squaredReciprocal: IntervalJet
        ) throws -> IntervalJet {
            (secondary * weight - value * secondaryWeight) * squaredReciprocal
        }

        private func positionFromFullJets(
            x: IntervalJet,
            y: IntervalJet,
            z: IntervalJet
        ) -> IntervalVectorJet {
            IntervalVectorJet(x: x, y: y, z: z)
        }

        private func coordinateJet(
            component: KeyPath<HomogeneousPoint, Interval>,
            primary: Direction,
            tolerance: ModelingTolerance
        ) throws -> IntervalJet {
            let values = try (0...7).map { order in
                try derivativeRange(
                    component: component,
                    uOrder: primary == .u ? order : 0,
                    vOrder: primary == .v ? order : 0,
                    tolerance: tolerance
                )
            }
            return IntervalJet(values)
        }

        private func secondaryCoordinateJet(
            component: KeyPath<HomogeneousPoint, Interval>,
            primary: Direction,
            tolerance: ModelingTolerance
        ) throws -> IntervalJet {
            let values = try (0...6).map { order in
                try derivativeRange(
                    component: component,
                    uOrder: primary == .u ? order : 1,
                    vOrder: primary == .v ? order : 1,
                    tolerance: tolerance
                )
            }
            return IntervalJet(values)
        }

        private func derivativeRange(
            component: KeyPath<HomogeneousPoint, Interval>,
            uOrder: Int,
            vOrder: Int,
            tolerance: ModelingTolerance
        ) throws -> Interval {
            let net = try derivativeNet(
                component: component,
                uOrder: uOrder,
                vOrder: vOrder,
                tolerance: tolerance
            )
            return Interval.hull(net.flatMap { $0 })
        }

        private func pointValue(
            u: Interval,
            v: Interval,
            tolerance: ModelingTolerance
        ) throws -> HomogeneousPoint {
            HomogeneousPoint(
                x: try derivativeValue(
                    component: \HomogeneousPoint.x,
                    uOrder: 0,
                    vOrder: 0,
                    u: u,
                    v: v,
                    tolerance: tolerance
                ),
                y: try derivativeValue(
                    component: \HomogeneousPoint.y,
                    uOrder: 0,
                    vOrder: 0,
                    u: u,
                    v: v,
                    tolerance: tolerance
                ),
                z: try derivativeValue(
                    component: \HomogeneousPoint.z,
                    uOrder: 0,
                    vOrder: 0,
                    u: u,
                    v: v,
                    tolerance: tolerance
                ),
                weight: try derivativeValue(
                    component: \HomogeneousPoint.weight,
                    uOrder: 0,
                    vOrder: 0,
                    u: u,
                    v: v,
                    tolerance: tolerance
                )
            )
        }

        private func derivativeValue(
            uOrder: Int,
            vOrder: Int,
            u: Interval,
            v: Interval,
            tolerance: ModelingTolerance
        ) throws -> HomogeneousPoint {
            HomogeneousPoint(
                x: try derivativeValue(
                    component: \HomogeneousPoint.x,
                    uOrder: uOrder,
                    vOrder: vOrder,
                    u: u,
                    v: v,
                    tolerance: tolerance
                ),
                y: try derivativeValue(
                    component: \HomogeneousPoint.y,
                    uOrder: uOrder,
                    vOrder: vOrder,
                    u: u,
                    v: v,
                    tolerance: tolerance
                ),
                z: try derivativeValue(
                    component: \HomogeneousPoint.z,
                    uOrder: uOrder,
                    vOrder: vOrder,
                    u: u,
                    v: v,
                    tolerance: tolerance
                ),
                weight: try derivativeValue(
                    component: \HomogeneousPoint.weight,
                    uOrder: uOrder,
                    vOrder: vOrder,
                    u: u,
                    v: v,
                    tolerance: tolerance
                )
            )
        }

        private func derivativeValue(
            component: KeyPath<HomogeneousPoint, Interval>,
            uOrder: Int,
            vOrder: Int,
            u: Interval,
            v: Interval,
            tolerance: ModelingTolerance
        ) throws -> Interval {
            let net = try derivativeNet(
                component: component,
                uOrder: uOrder,
                vOrder: vOrder,
                tolerance: tolerance
            )
            let rows = net.map { Self.evaluate($0, parameter: u) }
            return Self.evaluate(rows, parameter: v)
        }

        private func derivativeNet(
            component: KeyPath<HomogeneousPoint, Interval>,
            uOrder: Int,
            vOrder: Int,
            tolerance: ModelingTolerance
        ) throws -> [[Interval]] {
            var net = controls.map { row in row.map { $0[keyPath: component] } }
            if let constant = Self.exactConstant(in: net) {
                return uOrder == 0 && vOrder == 0
                    ? [[constant]]
                    : [[.exact(0.0)]]
            }
            for _ in 0..<uOrder {
                guard let columnCount = net.first?.count,
                      columnCount >= 2 else {
                    return net.map { _ in [Interval.exact(0.0)] }
                }
                let degree = columnCount - 1
                net = net.map { row in
                    (0..<degree).map { index in
                        (row[index + 1] - row[index]) * Interval.exact(Double(degree))
                    }
                }
            }
            for _ in 0..<vOrder {
                guard net.count >= 2 else {
                    return [Array(
                        repeating: Interval.exact(0.0),
                        count: net.first?.count ?? 1
                    )]
                }
                let degree = net.count - 1
                net = (0..<degree).map { rowIndex in
                    net[rowIndex].indices.map { columnIndex in
                        (net[rowIndex + 1][columnIndex] - net[rowIndex][columnIndex])
                            * Interval.exact(Double(degree))
                    }
                }
            }
            guard !net.isEmpty, net.allSatisfy({ !$0.isEmpty }) else {
                throw KernelError(
                    phase: .topology,
                    code: .resourceLimitExceeded,
                    tolerance: tolerance,
                    message: "Certified rational surface flux produced an empty derivative net."
                )
            }
            return net
        }

        private static func exactConstant(
            in net: [[Interval]]
        ) -> Interval? {
            guard let first = net.first?.first,
                  first.lower == first.upper,
                  net.allSatisfy({ row in
                      !row.isEmpty && row.allSatisfy {
                          $0.lower == first.lower && $0.upper == first.upper
                      }
                  }) else {
                return nil
            }
            return first
        }

        private static func evaluate(
            _ values: [Interval],
            parameter: Interval
        ) -> Interval {
            var level = values
            let complement = Interval.exact(1.0) - parameter
            while level.count > 1 {
                level = (0..<(level.count - 1)).map { index in
                    level[index] * complement + level[index + 1] * parameter
                }
            }
            return level[0]
        }

        private static func normalizedBounds(
            lower: Double,
            upper: Double,
            domain: ParameterDomain,
            tolerance: ModelingTolerance
        ) throws -> BoundsPair {
            guard case let .closed(domainLower, domainUpper) = domain,
                  lower >= domainLower,
                  upper <= domainUpper,
                  upper > lower else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "Rational Bezier surface trim lies outside its exact parameter domain."
                )
            }
            let span = Interval.exact(domainUpper) - Interval.exact(domainLower)
            let normalizedLower = lower == domainLower
                ? Interval.exact(0.0)
                : (Interval.exact(lower) - Interval.exact(domainLower)) / span
            let normalizedUpper = upper == domainUpper
                ? Interval.exact(1.0)
                : (Interval.exact(upper) - Interval.exact(domainLower)) / span
            guard let clampedLower = normalizedLower.intersection(.unit),
                  let clampedUpper = normalizedUpper.intersection(.unit) else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "Rational Bezier surface trim normalization is empty."
                )
            }
            return BoundsPair(lower: clampedLower, upper: clampedUpper)
        }

        private static func trimRows(
            _ rows: [[HomogeneousPoint]],
            bounds: BoundsPair
        ) -> [[HomogeneousPoint]] {
            rows.map { row in
                var current = row
                if bounds.lower.upper > 0.0 {
                    current = split(row, parameter: bounds.lower).upper
                }
                if bounds.upper.lower < 1.0 {
                    let localUpper = (bounds.upper - bounds.lower)
                        / (Interval.exact(1.0) - bounds.lower)
                    current = split(current, parameter: localUpper).lower
                }
                return current
            }
        }

        private static func splitRows(
            _ rows: [[HomogeneousPoint]],
            parameter: Interval
        ) -> (lower: [[HomogeneousPoint]], upper: [[HomogeneousPoint]]) {
            var lower: [[HomogeneousPoint]] = []
            var upper: [[HomogeneousPoint]] = []
            for row in rows {
                let halves = split(row, parameter: parameter)
                lower.append(halves.lower)
                upper.append(halves.upper)
            }
            return (lower, upper)
        }

        private static func split(
            _ values: [HomogeneousPoint],
            parameter: Interval
        ) -> (lower: [HomogeneousPoint], upper: [HomogeneousPoint]) {
            var levels = [values]
            while let previous = levels.last, previous.count > 1 {
                levels.append((0..<(previous.count - 1)).map { index in
                    previous[index].interpolated(
                        to: previous[index + 1],
                        parameter: parameter
                    )
                })
            }
            return (
                levels.map { $0[0] },
                levels.reversed().map { $0[$0.count - 1] }
            )
        }

        private static func transpose(
            _ values: [[HomogeneousPoint]]
        ) -> [[HomogeneousPoint]] {
            guard let first = values.first else { return [] }
            return first.indices.map { column in
                values.indices.map { row in values[row][column] }
            }
        }
    }

    private struct BoundsPair {
        let lower: Interval
        let upper: Interval
    }

    private struct HomogeneousPoint {
        let x: Interval
        let y: Interval
        let z: Interval
        let weight: Interval

        func interpolated(
            to other: HomogeneousPoint,
            parameter: Interval
        ) -> HomogeneousPoint {
            let complement = Interval.exact(1.0) - parameter
            return HomogeneousPoint(
                x: x * complement + other.x * parameter,
                y: y * complement + other.y * parameter,
                z: z * complement + other.z * parameter,
                weight: weight * complement + other.weight * parameter
            )
        }

        func euclidean(tolerance: ModelingTolerance) throws -> IntervalVector3 {
            guard weight.lower > 0.0 else {
                throw Self.singularWeight(weight, tolerance: tolerance)
            }
            return IntervalVector3(
                x: x / weight,
                y: y / weight,
                z: z / weight
            )
        }

        static func euclideanDerivative(
            value: HomogeneousPoint,
            derivative: HomogeneousPoint,
            tolerance: ModelingTolerance
        ) throws -> IntervalVector3 {
            guard value.weight.lower > 0.0 else {
                throw Self.singularWeight(value.weight, tolerance: tolerance)
            }
            let denominator = value.weight * value.weight
            return IntervalVector3(
                x: (derivative.x * value.weight - value.x * derivative.weight)
                    / denominator,
                y: (derivative.y * value.weight - value.y * derivative.weight)
                    / denominator,
                z: (derivative.z * value.weight - value.z * derivative.weight)
                    / denominator
            )
        }

        static func singularWeight(
            _ weight: Interval,
            tolerance: ModelingTolerance
        ) -> KernelError {
            KernelError(
                phase: .topology,
                code: .singularSystem,
                residual: weight.lower,
                tolerance: tolerance,
                message: "Certified rational surface flux encountered a non-positive weight enclosure."
            )
        }
    }

    private struct IntervalVector3 {
        let x: Interval
        let y: Interval
        let z: Interval

        init(x: Interval, y: Interval, z: Interval) {
            self.x = x
            self.y = y
            self.z = z
        }

        init(_ point: Point3D) {
            x = .exact(point.x)
            y = .exact(point.y)
            z = .exact(point.z)
        }

        static func - (lhs: IntervalVector3, rhs: IntervalVector3) -> IntervalVector3 {
            IntervalVector3(x: lhs.x - rhs.x, y: lhs.y - rhs.y, z: lhs.z - rhs.z)
        }

        func cross(_ other: IntervalVector3) -> IntervalVector3 {
            IntervalVector3(
                x: y * other.z - z * other.y,
                y: z * other.x - x * other.z,
                z: x * other.y - y * other.x
            )
        }

        func dot(_ other: IntervalVector3) -> Interval {
            x * other.x + y * other.y + z * other.z
        }
    }

    private struct UnivariateVector3 {
        let x: CertifiedUnivariateTaylorJet
        let y: CertifiedUnivariateTaylorJet
        let z: CertifiedUnivariateTaylorJet

        func subtracting(_ point: Point3D) -> UnivariateVector3 {
            UnivariateVector3(
                x: x - .constant(point.x),
                y: y - .constant(point.y),
                z: z - .constant(point.z)
            )
        }

        func cross(_ other: UnivariateVector3) -> UnivariateVector3 {
            UnivariateVector3(
                x: y * other.z - z * other.y,
                y: z * other.x - x * other.z,
                z: x * other.y - y * other.x
            )
        }

        func dot(_ other: UnivariateVector3) -> CertifiedUnivariateTaylorJet {
            x * other.x + y * other.y + z * other.z
        }
    }

    private struct IntervalVectorJet {
        let x: IntervalJet
        let y: IntervalJet
        let z: IntervalJet

        func truncated(to order: Int) -> IntervalVectorJet {
            IntervalVectorJet(
                x: x.truncated(to: order),
                y: y.truncated(to: order),
                z: z.truncated(to: order)
            )
        }

        func derivative() -> IntervalVectorJet {
            IntervalVectorJet(x: x.derivative(), y: y.derivative(), z: z.derivative())
        }

        func subtracting(_ point: Point3D) -> IntervalVectorJet {
            IntervalVectorJet(
                x: x.subtracting(constant: point.x),
                y: y.subtracting(constant: point.y),
                z: z.subtracting(constant: point.z)
            )
        }

        func cross(_ other: IntervalVectorJet) -> IntervalVectorJet {
            IntervalVectorJet(
                x: y * other.z - z * other.y,
                y: z * other.x - x * other.z,
                z: x * other.y - y * other.x
            )
        }

        func dot(_ other: IntervalVectorJet) -> IntervalJet {
            x * other.x + y * other.y + z * other.z
        }
    }

    private struct IntervalJet {
        let values: [Interval]

        init(_ values: [Interval]) {
            self.values = values
        }

        var order: Int {
            values.count - 1
        }

        func truncated(to requestedOrder: Int) -> IntervalJet {
            IntervalJet(Array(values.prefix(requestedOrder + 1)))
        }

        func derivative() -> IntervalJet {
            IntervalJet(Array(values.dropFirst()))
        }

        func subtracting(constant: Double) -> IntervalJet {
            var result = values
            result[0] = result[0] - .exact(constant)
            return IntervalJet(result)
        }

        func scaled(by scale: Interval) -> IntervalJet {
            IntervalJet(values.map { $0 * scale })
        }

        func reciprocal(tolerance: ModelingTolerance) throws -> IntervalJet {
            guard values[0].lower > 0.0 || values[0].upper < 0.0 else {
                throw KernelError(
                    phase: .topology,
                    code: .singularSystem,
                    residual: values[0].minimumAbsolute,
                    tolerance: tolerance,
                    message: "Certified rational surface flux encountered a singular reciprocal jet."
                )
            }
            var result = Array(repeating: Interval.exact(0.0), count: values.count)
            result[0] = Interval.exact(1.0) / values[0]
            if order > 0 {
                for derivativeOrder in 1...order {
                    var sum = Interval.exact(0.0)
                    for index in 1...derivativeOrder {
                        sum = sum + Interval.exact(Double(Self.binomial(derivativeOrder, index)))
                            * values[index] * result[derivativeOrder - index]
                    }
                    result[derivativeOrder] = -(sum / values[0])
                }
            }
            return IntervalJet(result)
        }

        static func + (lhs: IntervalJet, rhs: IntervalJet) -> IntervalJet {
            let order = min(lhs.order, rhs.order)
            return IntervalJet((0...order).map { lhs.values[$0] + rhs.values[$0] })
        }

        static func - (lhs: IntervalJet, rhs: IntervalJet) -> IntervalJet {
            let order = min(lhs.order, rhs.order)
            return IntervalJet((0...order).map { lhs.values[$0] - rhs.values[$0] })
        }

        static func * (lhs: IntervalJet, rhs: IntervalJet) -> IntervalJet {
            let order = min(lhs.order, rhs.order)
            return IntervalJet((0...order).map { derivativeOrder in
                var value = Interval.exact(0.0)
                for index in 0...derivativeOrder {
                    value = value + Interval.exact(Double(Self.binomial(derivativeOrder, index)))
                        * lhs.values[index] * rhs.values[derivativeOrder - index]
                }
                return value
            })
        }

        private static func binomial(_ n: Int, _ k: Int) -> Int {
            let reducedK = min(k, n - k)
            guard reducedK > 0 else { return 1 }
            var result = 1
            for index in 1...reducedK {
                result = result * (n - reducedK + index) / index
            }
            return result
        }
    }

    private struct CellBudget {
        let limit: Int
        var consumed = 0

        mutating func consume(tolerance: ModelingTolerance) throws {
            guard consumed < limit else {
                throw KernelError(
                    phase: .topology,
                    code: .resourceLimitExceeded,
                    residual: Double(consumed),
                    tolerance: tolerance,
                    message: "Certified rational surface flux exhausted its cell budget."
                )
            }
            consumed += 1
        }
    }

    private struct Interval: Sendable, Hashable {
        static let unit = Interval(lower: 0.0, upper: 1.0)

        let lower: Double
        let upper: Double

        init(lower: Double, upper: Double) {
            self.lower = lower
            self.upper = upper
        }

        static func exact(_ value: Double) -> Interval {
            Interval(lower: value, upper: value)
        }

        var errorRadius: Double {
            (upper - lower) * 0.5
        }

        var maximumAbsolute: Double {
            max(abs(lower), abs(upper)).nextUp
        }

        var minimumAbsolute: Double {
            if lower <= 0.0, upper >= 0.0 { return 0.0 }
            return min(abs(lower), abs(upper)).nextDown
        }

        static func hull(_ values: [Interval]) -> Interval {
            Interval(
                lower: (values.map(\.lower).min() ?? -.infinity).nextDown,
                upper: (values.map(\.upper).max() ?? .infinity).nextUp
            )
        }

        func intersection(_ other: Interval) -> Interval? {
            let resultLower = max(lower, other.lower)
            let resultUpper = min(upper, other.upper)
            guard resultLower <= resultUpper else { return nil }
            return Interval(lower: resultLower, upper: resultUpper)
        }

        func squareRoot(
            tolerance: ModelingTolerance
        ) throws -> Interval {
            guard lower >= 0.0, upper.isFinite else {
                throw KernelError(
                    phase: .topology,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "Certified interval square root requires a finite nonnegative interval."
                )
            }
            return Interval(
                lower: sqrt(lower).nextDown,
                upper: sqrt(upper).nextUp
            )
        }

        static prefix func - (value: Interval) -> Interval {
            Interval(lower: (-value.upper).nextDown, upper: (-value.lower).nextUp)
        }

        static func + (lhs: Interval, rhs: Interval) -> Interval {
            Interval(
                lower: (lhs.lower + rhs.lower).nextDown,
                upper: (lhs.upper + rhs.upper).nextUp
            )
        }

        static func - (lhs: Interval, rhs: Interval) -> Interval {
            lhs + (-rhs)
        }

        static func * (lhs: Interval, rhs: Interval) -> Interval {
            let products = [
                lhs.lower * rhs.lower,
                lhs.lower * rhs.upper,
                lhs.upper * rhs.lower,
                lhs.upper * rhs.upper,
            ]
            return Interval(
                lower: (products.min() ?? -.infinity).nextDown,
                upper: (products.max() ?? .infinity).nextUp
            )
        }

        static func / (lhs: Interval, rhs: Interval) -> Interval {
            guard rhs.lower > 0.0 || rhs.upper < 0.0 else {
                // Preserve a conservative enclosure; result publication
                // rejects non-finite certified bounds through a typed error.
                return Interval(lower: -.infinity, upper: .infinity)
            }
            return lhs * Interval(
                lower: (1.0 / rhs.upper).nextDown,
                upper: (1.0 / rhs.lower).nextUp
            )
        }
    }
}
