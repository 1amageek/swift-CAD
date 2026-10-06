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
                points.append(try publish(cell: strata.partition.cells[index], partition: strata.partition,
                    cellIndex: index, effectiveDomains: effective, first: firstLaw, second: secondLaw,
                    options: options, tolerance: tolerance, nativeDomains: native, requestedDomains: requested,
                    retainingParameters: &retainedParameters, retainingLocalizations: &retainedLocalizations, usage: &usage))
            }
        }
        let receipt: OriginalNativeSurfaceSurfacePoints?
        if relations == nil || !indices.isEmpty {
            try RationalAlgebraStorage.retainBytes(2 * MemoryLayout<BSplineSurface3D>.stride
                + MemoryLayout<ModelingTolerance>.stride + 3 * MemoryLayout<[Int]>.stride
                + MemoryLayout<OriginalRationalIntersectionDecomposition>.stride
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

    private func value(_ polynomial: ExactBivariatePolynomial, first: Bool,
        cell: OriginalRationalIntersectionCells.Cell, usage: inout NativeSurfaceSurfacePointAllowance)
        throws -> OriginalSingularFieldElement {
        let embedded = try ExactIntersectionPolynomial.embedding(polynomial, variableCount: 4,
            uCoordinate: first ? 0 : 2, vCoordinate: first ? 1 : 3, usage: &usage)
        return try OriginalIntersectionFieldEvaluation.evaluated(embedded, context: cell.context,
            coordinates: cell.coordinates, maximumDepth: usage.maximumAlgebraicDepth, usage: &usage)
    }

    private func publish(cell: OriginalRationalIntersectionCells.Cell,
        partition: OriginalRationalIntersectionCells, cellIndex: Int,
        effectiveDomains: [OriginalRationalParameterDomain], first: OriginalRationalSurfacePolynomial, second: OriginalRationalSurfacePolynomial,
        options: SurfaceSurfaceIntersectionOptions, tolerance: ModelingTolerance,
        nativeDomains: [ScalarInterval], requestedDomains: [ScalarInterval],
        retainingParameters: inout [OriginalSingularFieldValueIsolation],
        retainingLocalizations: inout [NativeCurveSurfaceScalarLocalization?],
        usage: inout NativeSurfaceSurfacePointAllowance) throws -> SurfaceSurfaceIntersectionPoint {
        let depth = usage.maximumAlgebraicDepth
        let weight = try value(first.homogeneous[3], first: true, cell: cell, usage: &usage)
        try RationalAlgebraStorage.retain(7, of: OriginalSingularFieldValueIsolation.self, usage: &usage)
        var isolations: [OriginalSingularFieldValueIsolation] = []; isolations.reserveCapacity(7)
        for axis in 0..<4 {
            var seed = try OriginalNativeSurfaceSurfacePoints.sectionBounds(partition: partition, cellIndex: cellIndex, axis: axis)
            if let lower = effectiveDomains[axis].lower,
                try seed.lower.subtracting(lower, usage: &usage).isNegative { seed.lower = lower }
            if let upper = effectiveDomains[axis].upper,
                try seed.upper.subtracting(upper, usage: &usage).isPositive { seed.upper = upper }
            for previous in 0..<axis {
                // Exact equality reuses an already retained scalar enclosure;
                // a linear fiber must not discard its parent's original root proof.
                if try cell.coordinates[axis].subtracting(cell.coordinates[previous],
                    maximumDepth: depth, usage: &usage).sign(maximumDepth: depth, usage: &usage) == .zero {
                    if try seed.lower.subtracting(isolations[previous].lower, usage: &usage).isNegative {
                        seed.lower = isolations[previous].lower
                    }
                    if try seed.upper.subtracting(isolations[previous].upper, usage: &usage).isPositive {
                        seed.upper = isolations[previous].upper
                    }
                }
            }
            isolations.append(try .init(original: cell.coordinates[axis], lower: seed.lower, upper: seed.upper,
                inheritedDepth: cell.admissionDepth, maximumDepth: depth, usage: &usage))
        }
        let uBounds = try isolations[0].enclosure(usage: &usage)
        let vBounds = try isolations[1].enclosure(usage: &usage)
        let parameterBox = SurfaceParameterBox(u: try .init(lower: uBounds.lower, upper: uBounds.upper),
            v: try .init(lower: vBounds.lower, upper: vBounds.upper))
        // On the original closed B-spline span, its nonnegative basis sums to
        // one. These original positive weights therefore bound the denominator
        // at the exact root, even if outward parameter endpoints leave the domain.
        var minimumWeight = Double.infinity, maximumWeight = 0.0
        for weight in first.source.weights.joined() {
            try usage.consumeExactWork(1)
            minimumWeight = min(minimumWeight, weight); maximumWeight = max(maximumWeight, weight)
        }
        let intervalWeight = OutwardScalarInterval(lower: minimumWeight, upper: maximumWeight)
        for axis in 0..<3 {
            let position = try value(first.homogeneous[axis], first: true, cell: cell, usage: &usage)
                .divided(by: weight, maximumDepth: depth, usage: &usage)
            guard let box = try first.homogeneous[axis].enclosure(over: parameterBox, usage: &usage)
                .divided(by: intervalWeight), box.isFinite else {
                throw rationalAlgebraFailure("Original surface position seed has no finite positive-denominator enclosure.")
            }
            isolations.append(try .init(original: position,
                lower: .originalDouble(box.lower, usage: &usage),
                upper: .originalDouble(box.upper, usage: &usage),
                inheritedDepth: cell.admissionDepth, maximumDepth: depth, usage: &usage))
        }
        try RationalAlgebraStorage.retain(4, of: NativeCurveSurfaceScalarLocalization?.self, usage: &usage)
        var localizations: [NativeCurveSurfaceScalarLocalization?] = []; localizations.reserveCapacity(4)
        for axis in 0..<4 {
            var localization: NativeCurveSurfaceScalarLocalization?
            if isolations[axis].lower != isolations[axis].upper {
                for prefix in 0...axis {
                    let section = try OriginalNativeSurfaceSurfacePoints.sectionCellIndex(partition: partition,
                        cellIndex: cellIndex, axis: prefix)
                    localization = try NativeCurveSurfaceScalarLocalization.prepare(original: cell.coordinates[axis],
                        sectionCoordinate: partition.cells[section].coordinates[prefix], isolation: isolations[axis],
                        inheritedCoefficientDepth: cell.coefficientAdmissionDepth, maximumDepth: depth,
                        maximumCoefficientDepth: partition.maximumCoefficientDepth, usage: &usage)
                    if let localization {
                        isolations[axis] = try isolations[axis].inheriting(depth: localization.parameterDepth,
                            maximumDepth: depth, usage: &usage)
                        break
                    }
                }
            }
            localizations.append(localization)
        }
        var width = ExactRationalCoefficient.one
        try RationalAlgebraStorage.retain(7, of: OutwardScalarInterval.self, usage: &usage)
        var bounds: [OutwardScalarInterval] = []; bounds.reserveCapacity(7)
        for iteration in 0..<options.maximumIterations {
            try usage.consumeExactWork(1)
            bounds.removeAll(keepingCapacity: true)
            for index in isolations.indices {
                if index < 4, let localization = localizations[index] {
                    var reusable: NativeCurveSurfaceScalarLocalization?
                    for previous in 0..<index {
                        if let proof = localizations[previous],
                            proof.primitiveCoordinate.context === localization.primitiveCoordinate.context { reusable = proof }
                    }
                    let refined = try localization.refined(maximumWidth: width, isolation: isolations[index],
                        reusing: reusable, maximumDepth: depth,
                        maximumCoefficientDepth: partition.maximumCoefficientDepth, usage: &usage)
                    localizations[index] = refined.proof; isolations[index] = refined.isolation
                } else {
                    isolations[index] = try isolations[index].refined(maximumWidth: width,
                        maximumDepth: depth, usage: &usage)
                }
                bounds.append(try isolations[index].enclosure(usage: &usage))
            }
            try RationalAlgebraStorage.retain(4, of: Double.self, usage: &usage)
            var parameters: [Double] = []; parameters.reserveCapacity(4)
            for axis in 0..<4 {
                parameters.append(try parameterRepresentative(bounds[axis], native: nativeDomains[axis],
                    requested: requestedDomains[axis]))
            }
            let point = Point3D(x: try representative(bounds[4]), y: try representative(bounds[5]), z: try representative(bounds[6]))
            let positionError = norm(bounds[4] - .exact(point.x), bounds[5] - .exact(point.y), bounds[6] - .exact(point.z))
            let firstPosition = try rationalPosition(first.homogeneous, u: parameters[0], v: parameters[1], usage: &usage)
            let secondPosition = try rationalPosition(second.homogeneous, u: parameters[2], v: parameters[3], usage: &usage)
            let residual = norm(firstPosition.0 - secondPosition.0, firstPosition.1 - secondPosition.1,
                firstPosition.2 - secondPosition.2)
            let sourceError = norm(firstPosition.0 - .exact(point.x), firstPosition.1 - .exact(point.y), firstPosition.2 - .exact(point.z))
            let targetError = norm(secondPosition.0 - .exact(point.x), secondPosition.1 - .exact(point.y), secondPosition.2 - .exact(point.z))
            if positionError <= tolerance.distance, residual <= tolerance.distance,
                sourceError <= tolerance.distance, targetError <= tolerance.distance,
                bounds[0].upper - bounds[0].lower <= tolerance.distance,
                bounds[1].upper - bounds[1].lower <= tolerance.distance,
                bounds[2].upper - bounds[2].lower <= tolerance.distance,
                bounds[3].upper - bounds[3].lower <= tolerance.distance {
                for axis in 0..<4 {
                    try usage.consumeExactWork(1); retainingParameters.append(isolations[axis])
                    retainingLocalizations.append(localizations[axis])
                }
                return try .init(point: point,
                    firstSurfaceParameter: .init(u: parameters[0], v: parameters[1], point: point,
                        residual: sourceError, iterations: iteration),
                    secondSurfaceParameter: .init(u: parameters[2], v: parameters[3], point: point,
                        residual: targetError, iterations: iteration), residual: residual, tolerance: tolerance)
            }
            width = try width.divided(by: .natural(2, usage: &usage), usage: &usage)
        }
        throw failure(.resourceLimitExceeded, "Native exact-root publication exhausted refinement iterations.", tolerance)
    }

    private func rationalPosition(_ homogeneous: [ExactBivariatePolynomial], u: Double, v: Double,
        usage: inout NativeSurfaceSurfacePointAllowance) throws -> (OutwardScalarInterval, OutwardScalarInterval, OutwardScalarInterval) {
        let a = try ExactRationalCoefficient.originalDouble(u, usage: &usage)
        let b = try ExactRationalCoefficient.originalDouble(v, usage: &usage)
        let weight = try homogeneous[3].evaluated(atU: a, v: b, usage: &usage)
        func axis(_ index: Int) throws -> OutwardScalarInterval {
            try homogeneous[index].evaluated(atU: a, v: b, usage: &usage)
                .divided(by: weight, usage: &usage).outwardInterval(usage: &usage)
        }
        return try (axis(0), axis(1), axis(2))
    }

    private func representative(_ interval: OutwardScalarInterval) throws -> Double {
        let middle = interval.lower * 0.5 + interval.upper * 0.5
        guard interval.isFinite, middle.isFinite, middle >= interval.lower, middle <= interval.upper else {
            throw rationalAlgebraFailure("Native root has no finite contained numerical representative.")
        }
        return middle
    }

    private func parameterRepresentative(_ interval: OutwardScalarInterval,
        native: ScalarInterval, requested: ScalarInterval?) throws -> Double {
        let lower = max(native.lower, requested?.lower ?? native.lower)
        let upper = min(native.upper, requested?.upper ?? native.upper)
        let candidate = max(lower, min(upper, try representative(interval)))
        guard lower <= upper, candidate >= interval.lower, candidate <= interval.upper else {
            throw rationalAlgebraFailure("Native parameter representative escaped its exact requested domain.")
        }
        return candidate
    }

    private func norm(_ x: OutwardScalarInterval, _ y: OutwardScalarInterval, _ z: OutwardScalarInterval) -> Double {
        let a = OutwardScalarInterval.exact(max(abs(x.lower), abs(x.upper)))
        let b = OutwardScalarInterval.exact(max(abs(y.lower), abs(y.upper)))
        let c = OutwardScalarInterval.exact(max(abs(z.lower), abs(z.upper)))
        let squared = a * a + b * b + c * c
        if !squared.isFinite || squared.upper < 0 { return .infinity }
        return sqrt(squared.upper).nextUp
    }

    private func failure(_ code: KernelErrorCode, _ message: String, _ tolerance: ModelingTolerance) -> KernelError {
        .init(phase: .geometry, code: code, tolerance: tolerance, message: message)
    }
}
