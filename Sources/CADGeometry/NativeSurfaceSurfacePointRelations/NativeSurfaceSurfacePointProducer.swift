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

/// Complete original four-coordinate native point publication before legacy dispatch.
struct NativeSurfaceSurfacePointProducer {
    func resolve(first: Surface3D, second: Surface3D,
        firstBox: SurfaceParameterBox? = nil, secondBox: SurfaceParameterBox? = nil,
        options: SurfaceSurfaceIntersectionOptions, tolerance: ModelingTolerance,
        includeRelations: Bool = false, admission: SurfaceSurfaceQueryAdmission = .legacy) throws -> SurfaceSurfaceIntersectionResult? {
        guard case .bSpline(let source) = first, case .bSpline(let target) = second,
            !source.isUPeriodic, !source.isVPeriodic, !target.isUPeriodic, !target.isVPeriodic,
            source.uDegree >= 0, source.uDegree < Int.max - 1,
            source.vDegree >= 0, source.vDegree < Int.max - 1,
            target.uDegree >= 0, target.uDegree < Int.max - 1,
            target.vDegree >= 0, target.vDegree < Int.max - 1,
            source.uControlPointCount == source.uDegree + 1,
            source.vControlPointCount == source.vDegree + 1,
            target.uControlPointCount == target.uDegree + 1,
            target.vControlPointCount == target.vDegree + 1 else { return nil }
        try options.validate(tolerance: tolerance)
        var usage = try NativeSurfaceSurfacePointAllowance(options: options, admission: admission)
        guard try singleSpan(source.uKnots, degree: source.uDegree, usage: &usage),
            try singleSpan(source.vKnots, degree: source.vDegree, usage: &usage),
            try singleSpan(target.uKnots, degree: target.uDegree, usage: &usage),
            try singleSpan(target.vKnots, degree: target.vDegree, usage: &usage) else { return nil }
        try usage.consumeExactWork(1)
        guard admission.remainingSourceDepth > 0 else {
            throw failure(.resourceLimitExceeded, "Native SSI preparation exhausted original source depth.", tolerance)
        }
        try source.validate(tolerance: tolerance, consumeWork: { try usage.consumeExactWork(1) })
        try target.validate(tolerance: tolerance, consumeWork: { try usage.consumeExactWork(1) })
        let sourceBox = SurfaceParameterBox(
            u: try .init(lower: source.uKnots[source.uDegree], upper: source.uKnots[source.uDegree + 1]),
            v: try .init(lower: source.vKnots[source.vDegree], upper: source.vKnots[source.vDegree + 1]))
        let targetBox = SurfaceParameterBox(
            u: try .init(lower: target.uKnots[target.uDegree], upper: target.uKnots[target.uDegree + 1]),
            v: try .init(lower: target.vKnots[target.vDegree], upper: target.vKnots[target.vDegree + 1]))
        let firstLaw = try prepare(source, box: sourceBox, admission: admission, tolerance: tolerance, usage: &usage)
        let secondLaw = try prepare(target, box: targetBox, admission: admission, tolerance: tolerance, usage: &usage)
        let system = try OriginalRationalIntersectionSystem(first: firstLaw, second: secondLaw, usage: &usage)
        try RationalAlgebraStorage.retain(4, of: ScalarInterval.self, usage: &usage)
        let native = [sourceBox.u, sourceBox.v, targetBox.u, targetBox.v]
        try RationalAlgebraStorage.retain(4, of: ScalarInterval.self, usage: &usage)
        let requested = [firstBox?.u ?? sourceBox.u, firstBox?.v ?? sourceBox.v,
            secondBox?.u ?? targetBox.u, secondBox?.v ?? targetBox.v]
        try RationalAlgebraStorage.retain(4, of: OriginalRationalParameterDomain.self, usage: &usage)
        var domains: [OriginalRationalParameterDomain] = []; domains.reserveCapacity(4)
        for interval in requested { domains.append(try .init(interval, usage: &usage)) }
        let decomposition = try OriginalRationalIntersectionDecomposition.prepare(system: system,
            requestedDomains: domains, pruneExcludedPrefixes: true, normalizeDenominatorFactors: true,
            isolatedOnly: !includeRelations, reducePureEvenPowerZeroSets: true, preferIsolatedCells: includeRelations,
            maximumDepth: usage.maximumAlgebraicDepth, usage: &usage)
        var indices: [Int] = []
        var relations: OriginalNativeSurfaceSurfaceRelations?
        if case .parameterCells(let strata, _, let components) = decomposition.coverage {
            guard components.components.count <= options.maximumSeedCount else {
                throw failure(.resourceLimitExceeded,
                    "Native original parameter component count exceeds the existing SSI component ceiling.", tolerance)
            }
            var hasPositiveDimension = false
            for index in strata.partition.solutionCells {
                try usage.consumeExactWork(1)
                if strata.partition.cells[index].dimension > 0 { hasPositiveDimension = true }
            }
            if hasPositiveDimension {
                guard includeRelations else {
                    throw failure(.nonDiscreteIntersection,
                        "The original requested native surface product contains a positive-dimensional intersection.", tolerance)
                }
                relations = try NativeSurfaceSurfaceRelationPublisher.publish(first: source, second: target,
                    tolerance: tolerance, decomposition: decomposition, maximumDepth: usage.maximumAlgebraicDepth, usage: &usage)
                // Zero-dimensional cells attached to a curve/region are retained by that relation,
                // rather than incorrectly exposed as separate isolated point intersections.
                var isolatedCount = 0
                for component in components.components {
                    try usage.consumeExactWork(component.cellIndexes.count)
                    if component.cellIndexes.allSatisfy({ strata.partition.cells[$0].dimension == 0 }) {
                        isolatedCount = try rationalAlgebraCount(isolatedCount, component.cellIndexes.count)
                    }
                }
                try RationalAlgebraStorage.retain(isolatedCount, of: Int.self, usage: &usage)
                indices.reserveCapacity(isolatedCount)
                for component in components.components {
                    try usage.consumeExactWork(component.cellIndexes.count)
                    if component.cellIndexes.allSatisfy({ strata.partition.cells[$0].dimension == 0 }) {
                        for index in component.cellIndexes { try usage.consumeExactWork(1); indices.append(index) }
                    }
                }
            } else {
                indices = strata.partition.solutionCells
            }
        }
        let parameterCount = try rationalAlgebraCount(indices.count, 4, multiply: true)
        try RationalAlgebraStorage.retain(indices.count, of: SurfaceSurfaceIntersectionPoint.self, usage: &usage)
        try RationalAlgebraStorage.retain(parameterCount, of: OriginalSingularFieldValueIsolation.self, usage: &usage)
        try RationalAlgebraStorage.retain(parameterCount, of: NativeCurveSurfaceScalarLocalization?.self, usage: &usage)
        var points: [SurfaceSurfaceIntersectionPoint] = []; points.reserveCapacity(indices.count)
        var retainedParameters: [OriginalSingularFieldValueIsolation] = []; retainedParameters.reserveCapacity(parameterCount)
        var retainedLocalizations: [NativeCurveSurfaceScalarLocalization?] = []; retainedLocalizations.reserveCapacity(parameterCount)
        if case .parameterCells(let strata, _, _) = decomposition.coverage,
            let effective = decomposition.effectiveDomains {
            for index in indices {
                points.append(try NativeSurfaceSurfacePointPublisher.publish(cell: strata.partition.cells[index], partition: strata.partition,
                    cellIndex: index, effectiveDomains: effective, first: firstLaw, second: secondLaw,
                    options: options, tolerance: tolerance, nativeDomains: native, requestedDomains: requested,
                    retainingParameters: &retainedParameters, retainingLocalizations: &retainedLocalizations, usage: &usage))
            }
        }
        let receipt: OriginalNativeSurfaceSurfacePoints?
        if relations == nil || !indices.isEmpty {
            try RationalAlgebraStorage.retainBytes(2 * MemoryLayout<BSplineSurface3D>.stride
                + MemoryLayout<ModelingTolerance>.stride + 3 * MemoryLayout<[Int]>.stride
                + MemoryLayout<NativeSurfaceSurfaceCoverage>.stride
                + 2 * MemoryLayout<UnsafeRawPointer>.stride, usage: &usage)
            receipt = OriginalNativeSurfaceSurfacePoints(first: source, second: target, tolerance: tolerance,
                decomposition: decomposition, cellIndices: indices, parameterIsolations: retainedParameters,
                parameterLocalizations: retainedLocalizations)
        } else { receipt = nil }
        try RationalAlgebraStorage.retain(indices.count, of: SurfaceSurfaceIntersection.self, usage: &usage)
        var intersections: [SurfaceSurfaceIntersection] = []; intersections.reserveCapacity(indices.count)
        for ordinal in points.indices {
            try usage.consumeExactWork(1)
            let point = points[ordinal]
            guard let receipt else { throw rationalAlgebraFailure("Native isolated component lost its exact point owner.") }
            intersections.append(.point(.init(numerical: point, originalNativePoint: try receipt.point(at: ordinal))))
        }
        try RationalAlgebraStorage.retain(1, of: SurfaceSurfaceIntersectionResult.self, usage: &usage)
        try CurrentTaskCancellationChecker().checkCancellation()
        return .init(intersections: intersections, originalNativePoints: receipt, originalNativeRelations: relations)
    }

    private func prepare(_ surface: BSplineSurface3D, box: SurfaceParameterBox,
        admission: SurfaceSurfaceQueryAdmission, tolerance: ModelingTolerance,
        usage: inout NativeSurfaceSurfacePointAllowance) throws -> OriginalRationalSurfacePolynomial {
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: surface, tolerance: tolerance,
            consumeWork: { try usage.consumeExactWork(1) }, consumeStorage: { try usage.retainBytes($0) })
        let spans = try prepared.originalNativeSpans(over: box, tolerance: tolerance,
            maximumSpanCount: admission.maximumSpanCount, consumeWork: { try usage.consumeExactWork(1) },
            consumeStorage: { try usage.retainBytes($0) })
        guard spans.count == 1, let span = spans.first else {
            throw failure(.intersectionFailure, "Admitted native surface has no unique complete source span.", tolerance)
        }
        return try .init(source: surface, native: span, domain: box, view: .init(x: 0, y: 0, z: 1),
            tolerance: tolerance, usage: &usage)
    }

    private func singleSpan(_ knots: [Double], degree: Int,
        usage: inout NativeSurfaceSurfacePointAllowance) throws -> Bool {
        try usage.consumeExactWork(1)
        guard degree >= 0, degree < Int.max / 2, knots.count == 2 * (degree + 1),
            knots.indices.contains(degree + 1) else { return false }
        let lower = knots[degree], upper = knots[degree + 1]
        guard lower.isFinite, upper.isFinite, lower < upper else { return false }
        return true
    }

    private func failure(_ code: KernelErrorCode, _ message: String, _ tolerance: ModelingTolerance) -> KernelError {
        .init(phase: .geometry, code: code, tolerance: tolerance, message: message)
    }
}
