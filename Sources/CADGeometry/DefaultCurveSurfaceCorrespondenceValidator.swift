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
import CADCore
import Synchronization

public struct DefaultCurveSurfaceCorrespondenceValidator: CurveSurfaceCorrespondenceValidating {
    private struct Node {
        let fraction: Double
        let curveParameter: Double
    }

    private struct Cell {
        let lower: Node
        let upper: Node
        let depth: Int
    }

    private struct CellCertification {
        let isCertified: Bool
        let curvePoint: Point3D
    }

    private struct ParameterDerivativeBounds {
        let firstU: Double
        let firstV: Double
        let secondU: Double
        let secondV: Double
        let vAbsolute: Double
        let breaks: [Double]
    }

    private struct CurveParameterInterval: Hashable {
        let lower: Double
        let upper: Double
    }

    private struct GeneralConeTorusCorrespondenceCacheKey: Hashable, Sendable {
        let source: CertifiedGeneralConeTorusIntersectionCurve.CertificationIdentity
        let sourceSurface: Surface3D
        let sourceRole: SurfaceIntersectionSurfaceRole
        let sourceStartFraction: Double
        let sourceEndFraction: Double
        let startCurveParameter: Double
        let endCurveParameter: Double
        let targetSurface: Surface3D
        let targetParameterCurve: BSplineCurve2D
        let options: CurveSurfaceCorrespondenceValidationOptions
        let tolerance: ModelingTolerance

        init?(
            curve: Curve3D,
            startCurveParameter: Double,
            endCurveParameter: Double,
            surface: Surface3D,
            parameterCurve: SurfaceParameterCurve,
            options: CurveSurfaceCorrespondenceValidationOptions,
            tolerance: ModelingTolerance
        ) {
            guard case let .surfaceLift(sourceLift) = curve,
                  case let .certifiedAnalyticPair(sourceCurve) =
                    sourceLift.parameterCurve,
                  let source = sourceCurve.intersection
                    .generalConeTorusCurve?.certificationIdentity,
                  case let .bSpline(targetParameterCurve) = parameterCurve else {
                return nil
            }
            self.source = source
            sourceSurface = sourceLift.surface
            sourceRole = sourceCurve.role
            sourceStartFraction = sourceCurve.startFraction
            sourceEndFraction = sourceCurve.endFraction
            self.startCurveParameter = startCurveParameter
            self.endCurveParameter = endCurveParameter
            targetSurface = surface
            self.targetParameterCurve = targetParameterCurve
            self.options = options
            self.tolerance = tolerance
        }
    }

    private final class GeneralConeTorusCorrespondenceCacheEntry: Sendable {
        let key: GeneralConeTorusCorrespondenceCacheKey
        let proof: OriginalQueryPreparationDepth
        let budget: OriginalQueryBudget
        init(key: GeneralConeTorusCorrespondenceCacheKey, proof: OriginalQueryPreparationDepth,
            budget: OriginalQueryBudget) {
            self.key = key; self.proof = proof; self.budget = budget
        }
    }

    // Exact BRep validation revisits shared immutable coedge geometry while
    // constructing and validating intermediate Boolean models. Preserve a
    // successful proof by its complete operational inputs; the procedural
    // source uses a compact deterministic identity so its large certificate
    // never becomes a cache key payload.
    @available(macOS 15.0, iOS 18.0, visionOS 2.0, *)
    private enum GeneralConeTorusCorrespondenceCache {
        static let storage = Mutex<[GeneralConeTorusCorrespondenceCacheKey: GeneralConeTorusCorrespondenceCacheEntry]>([:])
    }

    private struct HomogeneousCurveControl {
        static let zero = HomogeneousCurveControl(
            weightedPoint: .zero,
            weight: 0.0
        )

        let weightedPoint: Vector3D
        let weight: Double

        init(point: Point3D, weight: Double) {
            weightedPoint = Vector3D(
                x: point.x * weight,
                y: point.y * weight,
                z: point.z * weight
            )
            self.weight = weight
        }

        init(weightedPoint: Vector3D, weight: Double) {
            self.weightedPoint = weightedPoint
            self.weight = weight
        }

        func scaled(by scalar: Double) -> HomogeneousCurveControl {
            HomogeneousCurveControl(
                weightedPoint: weightedPoint * scalar,
                weight: weight * scalar
            )
        }

        func adding(_ other: HomogeneousCurveControl) -> HomogeneousCurveControl {
            HomogeneousCurveControl(
                weightedPoint: weightedPoint + other.weightedPoint,
                weight: weight + other.weight
            )
        }
    }

    public init() {}

    public func validate(curve: Curve3D, from startCurveParameter: Double, to endCurveParameter: Double,
        surface: Surface3D, parameterCurve: SurfaceParameterCurve,
        options: CurveSurfaceCorrespondenceValidationOptions, tolerance: ModelingTolerance) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(curve: curve, from: startCurveParameter, to: endCurveParameter,
            surface: surface, parameterCurve: parameterCurve, options: options,
            tolerance: tolerance, using: &execution)
    }

    public func validate(curve: Curve3D, from startCurveParameter: Double, to endCurveParameter: Double,
        surface: Surface3D, parameterCurve: SurfaceParameterCurve,
        options: CurveSurfaceCorrespondenceValidationOptions, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        let prepared = try execution.withPreparationScope { execution in
            try validateDirectBody(curve: curve, from: startCurveParameter, to: endCurveParameter,
                surface: surface, parameterCurve: parameterCurve, options: options,
                tolerance: tolerance, using: &execution)
        }
        if let key = prepared.result {
            try cache(key, proof: prepared.depth, using: &execution)
        }
    }

    private func validateDirectBody(
        curve: Curve3D,
        from startCurveParameter: Double,
        to endCurveParameter: Double,
        surface: Surface3D,
        parameterCurve: SurfaceParameterCurve,
        options: CurveSurfaceCorrespondenceValidationOptions,
        tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution) throws -> GeneralConeTorusCorrespondenceCacheKey? {
        try execution.consumeWork(1)
        try options.validate(tolerance: tolerance)
        try curve.validateOriginalSource(tolerance: tolerance, remainingSourceDepth: execution.limits.remainingSourceDepth, maximumSubdivisionDepth: execution.limits.maximumSubdivisionDepth, using: &execution)
        try surface.validateOriginalSource(tolerance: tolerance, remainingSourceDepth: execution.limits.remainingSourceDepth, maximumSubdivisionDepth: execution.limits.maximumSubdivisionDepth, using: &execution)
        try parameterCurve.validateOriginalSource(on: surface, tolerance: tolerance, remainingSourceDepth: execution.limits.remainingSourceDepth, maximumSubdivisionDepth: execution.limits.maximumSubdivisionDepth, using: &execution)
        if case .originalAffineWord = curve {
            _ = try OriginalBoundedCurveSurfaceCorrespondence.deviationBound(curve: curve,
                from: startCurveParameter, to: endCurveParameter, surface: surface,
                parameterCurve: parameterCurve, options: options, tolerance: tolerance,
                maximumSpanCount: execution.limits.maximumSpans, maximumSubdivisionDepth: execution.limits.maximumSubdivisionDepth,
                remainingSourceDepth: execution.limits.remainingSourceDepth, using: &execution)
            return nil
        }
        if case .originalAffineWord = parameterCurve {
            _ = try OriginalBoundedCurveSurfaceCorrespondence.deviationBound(curve: curve,
                from: startCurveParameter, to: endCurveParameter, surface: surface,
                parameterCurve: parameterCurve, options: options, tolerance: tolerance,
                maximumSpanCount: execution.limits.maximumSpans, maximumSubdivisionDepth: execution.limits.maximumSubdivisionDepth,
                remainingSourceDepth: execution.limits.remainingSourceDepth, using: &execution)
            return nil
        }
        if case let .periodicTranslation(base, _, _) = parameterCurve {
            try validate(
                curve: curve,
                from: startCurveParameter,
                to: endCurveParameter,
                surface: surface,
                parameterCurve: base,
                options: options,
                tolerance: tolerance,
            using: &execution)
            return nil
        }
        guard startCurveParameter.isFinite,
              endCurveParameter.isFinite,
              abs(endCurveParameter - startCurveParameter) > tolerance.relative else {
            throw correspondenceFailure(
                tolerance: tolerance,
                message: "Curve-surface correspondence requires a finite non-degenerate curve span."
            )
        }
        try GeometryStructuralComparisonWork.charge(curve: curve, using: &execution)
        try GeometryStructuralComparisonWork.charge(surface: surface, using: &execution)
        try GeometryStructuralComparisonWork.charge(parameterCurve: parameterCurve, using: &execution)
        let cacheKey = GeneralConeTorusCorrespondenceCacheKey(
            curve: curve,
            startCurveParameter: startCurveParameter,
            endCurveParameter: endCurveParameter,
            surface: surface,
            parameterCurve: parameterCurve,
            options: options,
            tolerance: tolerance
        )
        if let cacheKey, let entry = cached(cacheKey) {
            let proof = entry.proof
            _ = try execution.admitRetainedPreparation(owner: entry, budget: entry.budget,
                work: 1, storageBytes: 0, depth: proof.scalar, sourceDepth: proof.sourceDepth,
                geometricDepth: proof.geometricDepth, transportDepth: proof.transportDepth)
            return nil
        }
        if try validateStructuralCorrespondence(
            curve: curve,
            startCurveParameter: startCurveParameter,
            endCurveParameter: endCurveParameter,
            surface: surface,
            parameterCurve: parameterCurve,
            options: options,
            tolerance: tolerance,
        using: &execution) {
            return nil
        }
        let parameterBounds = try derivativeBounds(
            for: parameterCurve,
            surface: surface,
            tolerance: tolerance,
        using: &execution)
        let parameterRange = try ScalarInterval(
            lower: min(startCurveParameter, endCurveParameter),
            upper: max(startCurveParameter, endCurveParameter)
        )
        let preparedCurve: PreparedCurveDifferentialEncloser?
        if case .implicit = curve {
            preparedCurve = try PreparedCurveDifferentialEncloser(curve: curve, tolerance: tolerance, using: &execution)
        } else {
            preparedCurve = nil
        }
        let curveSecondDerivative = try curveSecondDerivativeUpperBound(
            curve,
            parameterRange: parameterRange,
            tolerance: tolerance,
            preparedCurve: preparedCurve,
        using: &execution)
        let curveDerivativeBoundsAreIntervalInvariant: Bool
        if case let .surfaceLift(lift) = curve {
            curveDerivativeBoundsAreIntervalInvariant = SurfaceLiftDifferentialBounder()
                .derivativeMagnitudeBoundsAreIntervalInvariant(lift: lift)
        } else {
            curveDerivativeBoundsAreIntervalInvariant = false
        }
        let curveFirstDerivativeBoundsAreIntervalInvariant =
            try firstDerivativeBoundsAreIntervalInvariant(
                for: curve,
                parameterRange: parameterRange
            , using: &execution)
        let parameterLift = SurfaceLiftCurve3D(
            surface: surface,
            parameterCurve: parameterCurve
        )
        let completeLiftInterval = try ScalarInterval(lower: 0.0, upper: 1.0)
        let liftSecondDerivative: Double?
        do {
            liftSecondDerivative = try SurfaceLiftDifferentialBounder()
                .secondDerivativeMagnitude(
                    lift: parameterLift,
                    interval: completeLiftInterval,
                    tolerance: tolerance,
                using: &execution) ?? liftSecondDerivativeUpperBound(
                    surface: surface,
                    parameterBounds: parameterBounds,
                    tolerance: tolerance,
                using: &execution)
        } catch let error as KernelError where error.code == .singularSystem {
            // An interval containing zero is not proof of a singular point.
            // The bounded cell loop must refine this inconclusive enclosure.
            liftSecondDerivative = nil
        }
        let projectionOptions = CurveParameterProjectionOptions(
            parameterRange: parameterRange
        )
        let fractionCount = try exactScalarCount(parameterBounds.breaks.count, 2)
        try OriginalCoefficientAllocation.reserve(count: try exactScalarCount(exactScalarCount(fractionCount, 4, multiply: true), 2), of: Double.self, using: &execution)
        let initialFractions = ([0.0] + parameterBounds.breaks + [1.0])
            .filter { $0 >= 0.0 && $0 <= 1.0 }
            .sorted()
        try OriginalCoefficientAllocation.reserve(count: initialFractions.count, of: Node.self, using: &execution)
        var nodes: [Node] = []
        nodes.reserveCapacity(initialFractions.count)
        for (index, fraction) in initialFractions.enumerated() {
            if index == 0 {
                nodes.append(Node(
                    fraction: fraction,
                    curveParameter: startCurveParameter
                ))
            } else if index + 1 == initialFractions.count {
                nodes.append(Node(
                    fraction: fraction,
                    curveParameter: endCurveParameter
                ))
            } else {
                nodes.append(try projectedNode(
                    fraction: fraction,
                    candidateCurveParameter: startCurveParameter
                        + (endCurveParameter - startCurveParameter) * fraction,
                    curve: curve,
                    surface: surface,
                    parameterCurve: parameterCurve,
                    projectionOptions: projectionOptions,
                    acceptanceDeviation: options.maximumDeviation ?? tolerance.distance,
                    tolerance: tolerance,
                using: &execution))
            }
        }
        try validateMonotone(nodes, tolerance: tolerance, using: &execution)
        let stackCapacity = try exactScalarCount(initialFractions.count, min(options.maximumSubdivisionDepth, execution.limits.maximumSubdivisionDepth))
        try OriginalCoefficientAllocation.reserve(count: stackCapacity, of: Cell.self, using: &execution)
        var stack: [Cell] = []
        stack.reserveCapacity(stackCapacity)
        for index in 1..<nodes.count {
            stack.append(Cell(lower: nodes[index - 1], upper: nodes[index], depth: 0))
        }
        // The pcurve basis partitions the lifted curve, but need not partition
        // spatial native derivative jumps. Cache bounds for their owning cells instead
        // of evaluating an unrelated fixed grid across the entire curve.
        // This preserves the proof while making work proportional to cells
        // that the correspondence actually needs to certify.
        var localSecondDerivativeBounds: [CurveParameterInterval: Double?] = [:]
        var invocationNativeSecondDerivativeBound: Double?
        var computedInvocationNativeSecondDerivativeBound = false
        func curveBasisInterval(
            containingLower lower: Double,
            upper: Double
        ) -> CurveParameterInterval {
            if curveSecondDerivative == nil {
                // Pcurve spans do not partition the original spatial curve's
                // derivative jumps. Each adaptive spatial interval owns its bound.
                return CurveParameterInterval(lower: lower, upper: upper)
            }
            for index in 1..<nodes.count {
                let spanLower = min(
                    nodes[index - 1].curveParameter,
                    nodes[index].curveParameter
                )
                let spanUpper = max(
                    nodes[index - 1].curveParameter,
                    nodes[index].curveParameter
                )
                if lower >= spanLower - tolerance.relative,
                   upper <= spanUpper + tolerance.relative {
                    return CurveParameterInterval(
                        lower: spanLower,
                        upper: spanUpper
                    )
                }
            }
            return CurveParameterInterval(lower: lower, upper: upper)
        }
        func localCurveSecondDerivativeBound(
            _ lower: Double,
            _ upper: Double,
        using execution: inout OriginalQueryExecution) throws -> Double? {
        try execution.consumeWork(1)
            if curveDerivativeBoundsAreIntervalInvariant {
                return curveSecondDerivative
            }
            let key = curveBasisInterval(
                containingLower: lower,
                upper: upper
            )
            let childParameterRange = try ScalarInterval(
                lower: key.lower,
                upper: key.upper
            )
            let canReuseNativeBound = try secondDerivativeBoundCanReuse(
                for: curve,
                parameterRange: childParameterRange
            , using: &execution)
            if let cached = localSecondDerivativeBounds[key] {
                return cached
            }
            let bound: Double?
            if canReuseNativeBound {
                if computedInvocationNativeSecondDerivativeBound {
                    bound = invocationNativeSecondDerivativeBound
                } else {
                    let computed = try self.curveSecondDerivativeUpperBound(
                        curve,
                        parameterRange: childParameterRange,
                        tolerance: tolerance,
                        preparedCurve: preparedCurve,
                    using: &execution)
                    invocationNativeSecondDerivativeBound = computed
                    computedInvocationNativeSecondDerivativeBound = true
                    bound = computed
                }
            } else {
                bound = try self.curveSecondDerivativeUpperBound(
                    curve,
                    parameterRange: childParameterRange,
                    tolerance: tolerance,
                    preparedCurve: preparedCurve,
                using: &execution)
            }
            let result = bound.map { local in
                curveSecondDerivative.map { min(local, $0) } ?? local
            }
            try OriginalCoefficientAllocation.reserve(count: 1, of: (CurveParameterInterval, Double?).self, using: &execution)
            localSecondDerivativeBounds[key] = .some(result)
            return result
        }
        var localFirstDerivativeBounds: [CurveParameterInterval: Double?] = [:]
        var intervalInvariantFirstDerivativeBound: Double?
        var computedIntervalInvariantFirstDerivativeBound = false
        func localCurveFirstDerivativeBound(
            _ lower: Double,
            _ upper: Double,
        using execution: inout OriginalQueryExecution) throws -> Double? {
        try execution.consumeWork(1)
            if curveFirstDerivativeBoundsAreIntervalInvariant {
                if computedIntervalInvariantFirstDerivativeBound {
                    return intervalInvariantFirstDerivativeBound
                }
                let bound = try self.curveFirstDerivativeUpperBound(
                    curve,
                    parameterRange: parameterRange,
                    tolerance: tolerance,
                using: &execution)
                intervalInvariantFirstDerivativeBound = bound
                computedIntervalInvariantFirstDerivativeBound = true
                return bound
            }
            let key = curveBasisInterval(
                containingLower: lower,
                upper: upper
            )
            if let cached = localFirstDerivativeBounds[key] {
                return cached
            }
            let bound = try self.curveFirstDerivativeUpperBound(
                curve,
                parameterRange: try ScalarInterval(
                    lower: key.lower,
                    upper: key.upper
                ),
                tolerance: tolerance,
            using: &execution)
            try OriginalCoefficientAllocation.reserve(count: 1, of: (CurveParameterInterval, Double?).self, using: &execution)
            localFirstDerivativeBounds[key] = bound
            return bound
        }
        var localLiftSecondDerivativeBounds:
            [CurveParameterInterval: Double] = [:]
        func liftBasisInterval(
            containingLower lower: Double,
            upper: Double
        ) -> CurveParameterInterval {
            if liftSecondDerivative == nil {
                return CurveParameterInterval(lower: lower, upper: upper)
            }
            for index in 1..<initialFractions.count {
                let spanLower = initialFractions[index - 1]
                let spanUpper = initialFractions[index]
                if lower >= spanLower - tolerance.relative,
                   upper <= spanUpper + tolerance.relative {
                    return CurveParameterInterval(
                        lower: spanLower,
                        upper: spanUpper
                    )
                }
            }
            return CurveParameterInterval(lower: lower, upper: upper)
        }
        func localLiftSecondDerivativeBound(
            _ lower: Double,
            _ upper: Double,
        using execution: inout OriginalQueryExecution) throws -> Double? {
        try execution.consumeWork(1)
            let key = liftBasisInterval(
                containingLower: lower,
                upper: upper
            )
            if let cached = localLiftSecondDerivativeBounds[key] {
                return cached
            }
            let bound: Double?
            do {
                bound = try SurfaceLiftDifferentialBounder()
                    .secondDerivativeMagnitude(
                        lift: parameterLift,
                        interval: try ScalarInterval(
                            lower: key.lower,
                            upper: key.upper
                        ),
                        tolerance: tolerance,
                    using: &execution)
            } catch let error as KernelError where error.code == .singularSystem {
                return nil
            }
            guard let result = bound.map({ local in
                liftSecondDerivative.map { min(local, $0) } ?? local
            }) ?? liftSecondDerivative else { return nil }
            try OriginalCoefficientAllocation.reserve(count: 1, of: (CurveParameterInterval, Double?).self, using: &execution)
            localLiftSecondDerivativeBounds[key] = result
            return result
        }
        var localLiftFirstDerivativeBounds:
            [CurveParameterInterval: Double?] = [:]
        func localLiftFirstDerivativeBound(
            _ lower: Double,
            _ upper: Double,
        using execution: inout OriginalQueryExecution) throws -> Double? {
        try execution.consumeWork(1)
            let key = liftBasisInterval(
                containingLower: lower,
                upper: upper
            )
            if let cached = localLiftFirstDerivativeBounds[key] {
                return cached
            }
            let bound = try SurfaceLiftDifferentialBounder()
                .firstDerivativeMagnitude(
                    lift: parameterLift,
                    interval: try ScalarInterval(
                        lower: key.lower,
                        upper: key.upper
                    ),
                    tolerance: tolerance,
                using: &execution)
            try OriginalCoefficientAllocation.reserve(count: 1, of: (CurveParameterInterval, Double?).self, using: &execution)
            localLiftFirstDerivativeBounds[key] = bound
            return bound
        }
        let acceptanceDeviation = options.maximumDeviation ?? tolerance.distance
        var remainingCells = options.maximumCellCount
        while let cell = stack.popLast() {
            try execution.visitGeometricCell(depth: cell.depth)
            guard remainingCells > 0 else {
                let lift = SurfaceLiftCurve3D(
                    surface: surface,
                    parameterCurve: parameterCurve
                )
                let middleFraction = (cell.lower.fraction + cell.upper.fraction) * 0.5
                let middleParameter = (
                    cell.lower.curveParameter + cell.upper.curveParameter
                ) * 0.5
                let liftedPosition = try lift.differentialGeometryAssumingValid(
                    atNormalizedFraction: middleFraction,
                    tolerance: tolerance,
                using: &execution).position
                let curvePosition = try curve.differentialGeometryAssumingValid(
                    at: middleParameter,
                    tolerance: tolerance,
                using: &execution).position
                let exhaustedLower = min(cell.lower.curveParameter, cell.upper.curveParameter)
                let exhaustedUpper = max(cell.lower.curveParameter, cell.upper.curveParameter)
                let localBound = try localCurveSecondDerivativeBound(
                    exhaustedLower,
                    exhaustedUpper,
                using: &execution)
                let localFirst = try localCurveFirstDerivativeBound(
                    exhaustedLower,
                    exhaustedUpper,
                using: &execution)
                let liftedFirst = try lift.differentialGeometryAssumingValid(
                    atNormalizedFraction: middleFraction,
                    tolerance: tolerance,
                using: &execution).firstDerivative
                let liftedFirstMagnitude = hypot(
                    hypot(liftedFirst.x, liftedFirst.y),
                    liftedFirst.z
                )
                throw resourceFailure(
                    tolerance: tolerance,
                    message: "Curve-surface correspondence validation exceeded its cell budget. Last cell fractions [\(cell.lower.fraction), \(cell.upper.fraction)] depth \(cell.depth) curve parameters [\(cell.lower.curveParameter), \(cell.upper.curveParameter)] midpoint deviation \((liftedPosition - curvePosition).length); curve second-derivative bound \(optionalBoundDescription(curveSecondDerivative)), cell-local bound \(optionalBoundDescription(localBound)), cell-local first-derivative bound \(optionalBoundDescription(localFirst)), lift first derivative at midpoint \(liftedFirstMagnitude), lift second-derivative bound \(optionalBoundDescription(liftSecondDerivative)), parameter breaks \(parameterBounds.breaks.count)."
                )
            }
            remainingCells -= 1
            let certification = try cellIsCertified(
                cell,
                curve: curve,
                surface: surface,
                parameterCurve: parameterCurve,
                curveSecondDerivativeUpperBound: curveSecondDerivative,
                localCurveSecondDerivativeBound: { lower, upper, execution in try localCurveSecondDerivativeBound(lower, upper, using: &execution) },
                localCurveFirstDerivativeBound: { lower, upper, execution in try localCurveFirstDerivativeBound(lower, upper, using: &execution) },
                liftSecondDerivativeUpperBound: liftSecondDerivative,
                localLiftSecondDerivativeBound: { lower, upper, execution in try localLiftSecondDerivativeBound(lower, upper, using: &execution) },
                localLiftFirstDerivativeBound: { lower, upper, execution in try localLiftFirstDerivativeBound(lower, upper, using: &execution) },
                acceptanceDeviation: acceptanceDeviation,
                tolerance: tolerance,
            using: &execution)
            if certification.isCertified {
                continue
            }
            guard cell.depth < options.maximumSubdivisionDepth else {
                throw resourceFailure(
                    tolerance: tolerance,
                    message: "Curve-surface correspondence validation exceeded its subdivision depth."
                )
            }
            let middleFraction = (cell.lower.fraction + cell.upper.fraction) * 0.5
            let middle = try projectedNode(
                fraction: middleFraction,
                candidateCurveParameter: (
                    cell.lower.curveParameter + cell.upper.curveParameter
                ) * 0.5,
                curve: curve,
                surface: surface,
                parameterCurve: parameterCurve,
                candidateCurvePoint: certification.curvePoint,
                projectionOptions: projectionOptions,
                acceptanceDeviation: options.maximumDeviation ?? tolerance.distance,
                tolerance: tolerance,
            using: &execution)
            try validateMonotone(
                [cell.lower, middle, cell.upper],
                tolerance: tolerance,
            using: &execution)
            stack.append(Cell(lower: middle, upper: cell.upper, depth: cell.depth + 1))
            stack.append(Cell(lower: cell.lower, upper: middle, depth: cell.depth + 1))
        }
        return cacheKey
    }

    private func cached(_ key: GeneralConeTorusCorrespondenceCacheKey)
        -> GeneralConeTorusCorrespondenceCacheEntry? {
        guard #available(macOS 15.0, iOS 18.0, visionOS 2.0, *) else { return nil }
        return GeneralConeTorusCorrespondenceCache.storage.withLock { $0[key] }
    }

    private func cache(_ key: GeneralConeTorusCorrespondenceCacheKey,
        proof: OriginalQueryPreparationDepth, using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        guard #available(macOS 15.0, iOS 18.0, visionOS 2.0, *) else { return }
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 1,
            of: (GeneralConeTorusCorrespondenceCacheKey, GeneralConeTorusCorrespondenceCacheEntry).self))
        let payloadBytes = try exactScalarCount(MemoryLayout<GeneralConeTorusCorrespondenceCacheKey>.stride,
            exactScalarCount(MemoryLayout<OriginalQueryPreparationDepth>.stride, MemoryLayout<OriginalQueryBudget>.stride))
        let ownerBytes = try exactScalarCount(payloadBytes,
            exactScalarPayloadBytes(count: 2, of: UnsafeRawPointer.self))
        try execution.retainStorage(bytes: ownerBytes)
        try execution.consumeWork(1)
        let entry = GeneralConeTorusCorrespondenceCacheEntry(key: key, proof: proof, budget: execution.budget)
        GeneralConeTorusCorrespondenceCache.storage.withLock { cache in
            if cache.count >= 256 { cache.removeAll(keepingCapacity: true) }
            cache[key] = entry
        }
        try execution.checkpoint()
    }

    private func validateStructuralCorrespondence(
        curve: Curve3D,
        startCurveParameter: Double,
        endCurveParameter: Double,
        surface: Surface3D,
        parameterCurve: SurfaceParameterCurve,
        options: CurveSurfaceCorrespondenceValidationOptions,
        tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution) throws -> Bool {
        try execution.consumeWork(1)
        if case .procedural(.rollingBall(let blend)) = surface,
           case .constantV(let v, let uStart, let uEnd) = parameterCurve,
           v == 0 || v == 1,
           curve == (v == 0 ? blend.firstContact : blend.secondContact),
           startCurveParameter == uStart, endCurveParameter == uEnd,
           let deviation = try blend.contactBoundaryDeviation(onFirst: v == 0),
           deviation <= (options.maximumDeviation ?? tolerance.distance) {
            return true
        }
        if case .procedural(.rollingBall) = surface,
           case .surfaceLift = curve {
            let builder = AnalyticCurveBSplineBuilder()
            let span = try ScalarInterval(
                lower: min(startCurveParameter, endCurveParameter),
                upper: max(startCurveParameter, endCurveParameter)
            )
            let target = Curve3D.surfaceLift(SurfaceLiftCurve3D(
                surface: surface, parameterCurve: parameterCurve
            ))
            if let sourceSection = try builder.boundedCurve(
                curve: curve, interval: span, maximumSpanCount: 1, tolerance: tolerance,
            using: &execution), let targetSection = try builder.boundedCurve(
                curve: target, interval: ScalarInterval(lower: 0, upper: 1),
                maximumSpanCount: 1, tolerance: tolerance,
            using: &execution) {
                let oriented = try startCurveParameter < endCurveParameter
                    ? sourceSection : sourceSection.reversed(tolerance: tolerance, using: &execution)
                if try bSplineCurvesHaveSameBasisAndBoundedControls(
                    oriented, targetSection, tolerance: tolerance,
                using: &execution) {
                    return true
                }
            }
        }
        if case let .procedural(.ruled(ruled)) = surface,
           try validatesRuledSurfaceBoundary(
               curve: curve,
               startCurveParameter: startCurveParameter,
               endCurveParameter: endCurveParameter,
               ruled: ruled,
               parameterCurve: parameterCurve,
               tolerance: tolerance,
           using: &execution) {
            return true
        }
        if case let .surfaceLift(lift) = curve {
            let lowerParameter = min(startCurveParameter, endCurveParameter)
            let upperParameter = max(startCurveParameter, endCurveParameter)
            guard try curve.parameterDomain.containsSpan(
                from: lowerParameter,
                to: upperParameter,
                tolerance: tolerance
            ) else {
                throw correspondenceFailure(
                    tolerance: tolerance,
                    message: "A surface-lift edge trim is outside its normalized domain."
                )
            }
            let trimmed = try lift.parameterCurve.subcurve(
                fromNormalizedFraction: lowerParameter,
                toNormalizedFraction: upperParameter,
                tolerance: tolerance
            )
            let expectedParameterCurve = if startCurveParameter < endCurveParameter {
                trimmed
            } else {
                try trimmed.reversed(tolerance: tolerance, using: &execution)
            }
            if lift.surface == surface,
               expectedParameterCurve == parameterCurve {
                return true
            }
            if lift.surface == surface,
               case let .bSpline(expected) = expectedParameterCurve,
               case let .bSpline(actual) = parameterCurve,
               try bSplineCurvesHaveSameBasisAndBoundedControls(
                   try embedded(expected, using: &execution),
                   try embedded(actual, using: &execution),
                   tolerance: tolerance,
               using: &execution) {
                return true
            }
        }
        switch parameterCurve {
        case .originalImage, .originalAffineWord: return false

        case let .certifiedImplicit(certified):
            guard curve == .implicit(certified.intersection),
                  abs(startCurveParameter - certified.startFraction) <= tolerance.relative,
                  abs(endCurveParameter - certified.endFraction) <= tolerance.relative else {
                throw correspondenceFailure(
                    tolerance: tolerance,
                    message: "A certified implicit pcurve changed its source curve or trim."
                )
            }
            return true
        case let .certifiedAnalyticImplicit(certified):
            guard curve == .implicit(certified.intersection.implicitCurve),
                  abs(startCurveParameter - certified.startFraction) <= tolerance.relative,
                  abs(endCurveParameter - certified.endFraction) <= tolerance.relative else {
                throw correspondenceFailure(
                    tolerance: tolerance,
                    message: "A certified analytic pcurve changed its source curve or trim."
                )
            }
            return true
        case let .certifiedAnalyticPair(certified):
            let certifiedCurve = certified.intersection.curve
            guard let expectedStart = sourceParameter(
                      forNormalizedFraction: certified.startFraction,
                      domain: certifiedCurve.parameterDomain
                  ),
                  let expectedEnd = sourceParameter(
                      forNormalizedFraction: certified.endFraction,
                      domain: certifiedCurve.parameterDomain
                  ),
                  curve == certifiedCurve,
                  abs(startCurveParameter - expectedStart) <= tolerance.angle,
                  abs(endCurveParameter - expectedEnd) <= tolerance.angle else {
                throw correspondenceFailure(
                    tolerance: tolerance,
                    message: "A certified analytic-pair pcurve changed its source curve or trim."
                )
            }
            return true
        case let .projectedAnalytic(projected):
            guard curve == projected.curve,
                  surface == projected.surface,
                  abs(startCurveParameter - projected.startParameter) <= tolerance.relative,
                  abs(endCurveParameter - projected.endParameter) <= tolerance.relative else {
                throw correspondenceFailure(
                    tolerance: tolerance,
                    message: "An analytic projected pcurve changed its source curve, surface, or trim."
                )
            }
            return true
        case let .rigidImage(image):
            guard case let .rigidImage(curveImage) = curve,
                  curveImage.transform == image.transform,
                  surface == image.targetSurface else {
                throw correspondenceFailure(
                    tolerance: tolerance,
                    message: "A rigid-image pcurve changed its source transform, target surface, or 3D curve image."
                )
            }
            let lower = min(image.startFraction, image.endFraction)
            let upper = max(image.startFraction, image.endFraction)
            let sourceSubcurve = try image.source.parameterCurve.subcurve(
                fromNormalizedFraction: lower,
                toNormalizedFraction: upper,
                tolerance: tolerance
            )
            let orientedSource = if image.startFraction <= image.endFraction {
                sourceSubcurve
            } else {
                try sourceSubcurve.reversed(tolerance: tolerance, using: &execution)
            }
            try validate(
                curve: curveImage.source,
                from: startCurveParameter,
                to: endCurveParameter,
                surface: image.source.surface,
                parameterCurve: orientedSource,
                options: options,
                tolerance: tolerance,
            using: &execution)
            return true
        case .offsetSurfaceImage:
            break
        case .affine, .constantU, .constantV, .harmonic, .sphericalGreatCircle, .polyline, .bSpline, .originalBSplineContinuation:
            break
        case .periodicTranslation:
            return false
        }
        if try validateSphericalGreatCircleCorrespondence(
            curve: curve,
            startCurveParameter: startCurveParameter,
            endCurveParameter: endCurveParameter,
            surface: surface,
            parameterCurve: parameterCurve,
            tolerance: tolerance,
        using: &execution) {
            return true
        }
        if try validateCylinderIsoparametricCorrespondence(
            curve: curve,
            startCurveParameter: startCurveParameter,
            endCurveParameter: endCurveParameter,
            surface: surface,
            parameterCurve: parameterCurve,
            tolerance: tolerance,
        using: &execution) {
            return true
        }
        if try validatePlanarHarmonicCircleCorrespondence(
            curve: curve,
            startCurveParameter: startCurveParameter,
            endCurveParameter: endCurveParameter,
            surface: surface,
            parameterCurve: parameterCurve,
            tolerance: tolerance,
        using: &execution) {
            return true
        }
        if try validateBSplineIsoparametricCorrespondence(
            curve: curve,
            startCurveParameter: startCurveParameter,
            endCurveParameter: endCurveParameter,
            surface: surface,
            parameterCurve: parameterCurve,
            tolerance: tolerance,
        using: &execution) {
            return true
        }
        if try validateBilinearBSplineAffineCorrespondence(
            curve: curve,
            startCurveParameter: startCurveParameter,
            endCurveParameter: endCurveParameter,
            surface: surface,
            parameterCurve: parameterCurve,
            tolerance: tolerance,
        using: &execution) {
            return true
        }
        if try validateAffineBilinearBSplinePcurveCorrespondence(
            curve: curve,
            startCurveParameter: startCurveParameter,
            endCurveParameter: endCurveParameter,
            surface: surface,
            parameterCurve: parameterCurve,
            tolerance: tolerance,
        using: &execution) {
            return true
        }
        return try validatePlanarBSplineCorrespondence(
            curve: curve,
            startCurveParameter: startCurveParameter,
            endCurveParameter: endCurveParameter,
            surface: surface,
            parameterCurve: parameterCurve,
            tolerance: tolerance,
        using: &execution)
    }

    private func validateCylinderIsoparametricCorrespondence(
        curve: Curve3D,
        startCurveParameter: Double,
        endCurveParameter: Double,
        surface: Surface3D,
        parameterCurve: SurfaceParameterCurve,
        tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution) throws -> Bool {
        try execution.consumeWork(1)
        guard case let .cylinder(cylinder) = surface else { return false }
        switch parameterCurve {
        case .originalImage, .originalAffineWord: return false

        case let .constantU(u, vStart, vEnd):
            guard lineDefinition(curve) != nil else { return false }
            let startSurfacePoint = try surface.point(
                u: u,
                v: vStart,
                tolerance: tolerance,
            using: &execution)
            let endSurfacePoint = try surface.point(
                u: u,
                v: vEnd,
                tolerance: tolerance,
            using: &execution)
            let startCurvePoint = try curve.point(
                at: startCurveParameter,
                tolerance: tolerance,
            using: &execution)
            let endCurvePoint = try curve.point(
                at: endCurveParameter,
                tolerance: tolerance,
            using: &execution)
            let curveSpanVector = endCurvePoint - startCurvePoint
            let surfaceSpanVector = endSurfacePoint - startSurfacePoint
            guard startCurvePoint.isApproximatelyEqual(
                      to: startSurfacePoint,
                      tolerance: tolerance.distance
                  ),
                  endCurvePoint.isApproximatelyEqual(
                      to: endSurfacePoint,
                      tolerance: tolerance.distance
                  ),
                  (curveSpanVector - surfaceSpanVector).length
                      <= tolerance.distance,
                  abs(
                      curveSpanVector.cross(cylinder.axis).length
                  ) <= tolerance.distance * max(curveSpanVector.length, 1.0) else {
                throw correspondenceFailure(
                    tolerance: tolerance,
                    message: "A constant-U cylindrical pcurve does not reproduce its exact linear generator."
                )
            }
            return true
        case let .constantV(v, uStart, uEnd):
            guard let circle = circleDefinition(curve) else { return false }
            let expectedCenter = cylinder.origin + cylinder.axis * v
            let normalAlignment = abs(circle.normal.dot(cylinder.axis))
            let curveSpan = endCurveParameter - startCurveParameter
            let parameterSpan = uEnd - uStart
            let middleCurveParameter = (startCurveParameter + endCurveParameter) * 0.5
            let middleSurfaceParameter = (uStart + uEnd) * 0.5
            let startCurvePoint = try curve.point(
                at: startCurveParameter,
                tolerance: tolerance,
            using: &execution)
            let middleCurvePoint = try curve.point(
                at: middleCurveParameter,
                tolerance: tolerance,
            using: &execution)
            let endCurvePoint = try curve.point(
                at: endCurveParameter,
                tolerance: tolerance,
            using: &execution)
            let startSurfacePoint = try surface.point(
                u: uStart,
                v: v,
                tolerance: tolerance,
            using: &execution)
            let middleSurfacePoint = try surface.point(
                u: middleSurfaceParameter,
                v: v,
                tolerance: tolerance,
            using: &execution)
            let endSurfacePoint = try surface.point(
                u: uEnd,
                v: v,
                tolerance: tolerance,
            using: &execution)
            let parameterTolerance = max(
                tolerance.angle,
                tolerance.relative * max(abs(curveSpan), abs(parameterSpan), 1.0)
            )
            guard circle.center.isApproximatelyEqual(
                      to: expectedCenter,
                      tolerance: tolerance.distance
                  ),
                  abs(circle.radius - cylinder.radius) <= tolerance.distance,
                  abs(normalAlignment - 1.0) <= tolerance.angle,
                  abs(abs(curveSpan) - abs(parameterSpan)) <= parameterTolerance,
                  startCurvePoint.isApproximatelyEqual(
                      to: startSurfacePoint,
                      tolerance: tolerance.distance
                  ),
                  middleCurvePoint.isApproximatelyEqual(
                      to: middleSurfacePoint,
                      tolerance: tolerance.distance
                  ),
                  endCurvePoint.isApproximatelyEqual(
                      to: endSurfacePoint,
                      tolerance: tolerance.distance
                  ) else {
                throw correspondenceFailure(
                    tolerance: tolerance,
                    message: "A constant-V cylindrical pcurve does not reproduce its exact circular section."
                )
            }
            return true
        case .affine, .harmonic, .sphericalGreatCircle, .polyline, .bSpline, .originalBSplineContinuation,
             .certifiedImplicit, .certifiedAnalyticImplicit,
             .certifiedAnalyticPair, .projectedAnalytic, .rigidImage,
             .offsetSurfaceImage:
            return false
        case .periodicTranslation:
            return false
        }
    }

    private func validatesRuledSurfaceBoundary(
        curve: Curve3D,
        startCurveParameter: Double,
        endCurveParameter: Double,
        ruled: RuledSurface3D,
        parameterCurve: SurfaceParameterCurve,
        tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution) throws -> Bool {
        try execution.consumeWork(1)
        switch parameterCurve {
        case let .constantV(v, uStart, uEnd):
            let boundary: Curve3D
            if abs(v) <= tolerance.relative {
                boundary = ruled.startBoundary
            } else if abs(v - 1.0) <= tolerance.relative {
                boundary = ruled.endBoundary
            } else {
                return false
            }
            return curve == boundary
                && abs(startCurveParameter - uStart) <= tolerance.relative
                && abs(endCurveParameter - uEnd) <= tolerance.relative
        case let .constantU(u, vStart, vEnd):
            guard case .line = curve,
                  abs(u) <= tolerance.relative
                    || abs(u - 1.0) <= tolerance.relative else {
                return false
            }
            let curveStart = try curve.point(
                at: startCurveParameter,
                tolerance: tolerance,
            using: &execution)
            let curveEnd = try curve.point(
                at: endCurveParameter,
                tolerance: tolerance,
            using: &execution)
            let surfaceStart = try ruled.point(
                u: u,
                v: vStart,
                tolerance: tolerance,
            using: &execution)
            let surfaceEnd = try ruled.point(
                u: u,
                v: vEnd,
                tolerance: tolerance,
            using: &execution)
            return curveStart.isApproximatelyEqual(
                to: surfaceStart,
                tolerance: tolerance.distance
            ) && curveEnd.isApproximatelyEqual(
                to: surfaceEnd,
                tolerance: tolerance.distance
            )
        default:
            return false
        }
    }

    private func validatePlanarHarmonicCircleCorrespondence(
        curve: Curve3D,
        startCurveParameter: Double,
        endCurveParameter: Double,
        surface: Surface3D,
        parameterCurve: SurfaceParameterCurve,
        tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution) throws -> Bool {
        try execution.consumeWork(1)
        guard case let .plane(plane) = surface,
              let circle = circleDefinition(curve),
              case let .harmonic(
                  center,
                  cosine,
                  sine,
                  startParameter,
                  endParameter
              ) = parameterCurve else {
            return false
        }
        let basis = try plane.parameterBasis(tolerance: tolerance)
        let liftedCenter = plane.origin
            + basis.u * center.x
            + basis.v * center.y
        let liftedCosine = basis.u * cosine.x + basis.v * cosine.y
        let liftedSine = basis.u * sine.x + basis.v * sine.y
        let liftedCross = liftedCosine.cross(liftedSine)
        let liftedCrossLength = liftedCross.length
        let radialScale = liftedCosine.length * liftedSine.length
        let nondegenerateThreshold = max(
            tolerance.relative * radialScale,
            Double.ulpOfOne * radialScale * 64.0
        )
        guard liftedCrossLength > nondegenerateThreshold else {
            throw correspondenceFailure(
                tolerance: tolerance,
                message: "A planar harmonic pcurve has a degenerate lifted basis."
            )
        }
        let normalAlignment = abs(liftedCross.dot(circle.normal))
            / liftedCrossLength
        let curveSpan = endCurveParameter - startCurveParameter
        let harmonicSpan = endParameter - startParameter
        let startLiftedRadial = liftedCosine * cos(startParameter)
            + liftedSine * sin(startParameter)
        let startLiftedDerivative = (
            liftedCosine * -sin(startParameter)
                + liftedSine * cos(startParameter)
        ) * harmonicSpan
        let startCurveGeometry = try curve.differentialGeometry(
            at: startCurveParameter,
            tolerance: tolerance,
        using: &execution)
        let startCurveDerivative = startCurveGeometry.firstDerivative * curveSpan
        let derivativeScale = max(
            startLiftedDerivative.length,
            startCurveDerivative.length
        )
        // The start may sit as far round the circle as the distance tolerance allows (the position
        // check below) and the spans differ by up to the angle tolerance: the derivative turns and
        // stretches by as much, which the derivative check allows besides rounding.
        let derivativeTolerance = max(
            tolerance.relative * derivativeScale,
            Double.ulpOfOne * derivativeScale * 64.0,
            derivativeScale * (tolerance.distance / circle.radius + tolerance.angle / max(abs(curveSpan), tolerance.angle))
        )
        let orthogonalityTolerance = max(
            tolerance.angle * radialScale,
            Double.ulpOfOne * radialScale * 64.0
        )
        guard liftedCenter.isApproximatelyEqual(
                  to: circle.center,
                  tolerance: tolerance.distance
              ),
              abs(liftedCosine.length - circle.radius) <= tolerance.distance,
              abs(liftedSine.length - circle.radius) <= tolerance.distance,
              abs(liftedCosine.dot(liftedSine))
                  <= orthogonalityTolerance,
              abs(normalAlignment - 1.0) <= tolerance.angle,
              abs(abs(harmonicSpan) - abs(curveSpan)) <= tolerance.angle,
              startCurveGeometry.position.isApproximatelyEqual(
                  to: liftedCenter + startLiftedRadial,
                  tolerance: tolerance.distance
              ),
              (startCurveDerivative - startLiftedDerivative).length
                  <= derivativeTolerance else {
            throw correspondenceFailure(
                tolerance: tolerance,
                message: "A planar harmonic pcurve does not reproduce its exact circular edge."
            )
        }
        return true
    }

    private func lineDefinition(
        _ curve: Curve3D
    ) -> (origin: Point3D, direction: Vector3D)? {
        switch curve {
        case let .parameterImage(image):
            guard let source = lineDefinition(image.source) else { return nil }
            return (source.origin + source.direction * image.offset, source.direction * image.gain)

        case let .line(line):
            return (line.origin, line.direction)
        case let .analytic(.line(origin, direction)):
            return (origin, direction)
        case let .rigidImage(image):
            guard let source = lineDefinition(image.source) else {
                return nil
            }
            return (
                image.transform.applying(to: source.origin),
                image.transform.applying(to: source.direction)
            )
        case let .affineImage(image):
            guard let source = lineDefinition(image.source) else {
                return nil
            }
            let direction = image.transform.applying(to: source.direction)
            guard direction.length > 0.0 else {
                return nil
            }
            return (
                image.transform.applying(to: source.origin),
                direction
            )
        case .circle, .analytic, .bSpline, .implicit, .surfaceLift,
             .certifiedIntersection, .originalAffineWord, .originalEndpointConnector, .originalConstructionChart, .originalAngularTransport, .originalPlaneDerivative, .originalGuideTraversalChain, .originalGuideEndpointConnector, .originalPolyline, .originalDrafted:
            return nil
        }
    }

    private func circleDefinition(
        _ curve: Curve3D
    ) -> (center: Point3D, normal: Vector3D, radius: Double)? {
        switch curve {
        case let .circle(circle):
            return (circle.center, circle.normal, circle.radius)
        case let .analytic(.circle(center, normal, radius)),
             let .analytic(.arc(center, normal, radius, _, _)):
            return (center, normal, radius)
        case let .rigidImage(image):
            guard let source = circleDefinition(image.source) else {
                return nil
            }
            return (
                image.transform.applying(to: source.center),
                image.transform.applying(to: source.normal),
                source.radius
            )
        case .originalConstructionChart, .originalEndpointConnector, .originalPlaneDerivative, .originalGuideTraversalChain, .originalPolyline, .originalGuideEndpointConnector, .originalDrafted, .originalAngularTransport, .originalAffineWord, .line, .analytic, .bSpline, .implicit, .surfaceLift,
             .certifiedIntersection, .affineImage, .parameterImage:
            return nil
        }
    }

    private func embedded(
        _ curve: BSplineCurve2D
    , using execution: inout OriginalQueryExecution) throws -> BSplineCurve3D {
        try OriginalCoefficientAllocation.reserve(count: curve.controlPoints.count, of: Point3D.self, using: &execution)
        return BSplineCurve3D(
            degree: curve.degree,
            knots: curve.knots,
            controlPoints: curve.controlPoints.map {
                Point3D(x: $0.x, y: $0.y, z: 0.0)
            },
            weights: curve.weights
        )
    }

    private func sourceParameter(
        forNormalizedFraction fraction: Double,
        domain: ParameterDomain
    ) -> Double? {
        switch domain {
        case let .closed(lower, upper):
            return lower + (upper - lower) * fraction
        case let .periodic(period):
            return period * fraction
        case .unbounded:
            return nil
        }
    }

    private func validateSphericalGreatCircleCorrespondence(
        curve: Curve3D,
        startCurveParameter: Double,
        endCurveParameter: Double,
        surface: Surface3D,
        parameterCurve: SurfaceParameterCurve,
        tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution) throws -> Bool {
        try execution.consumeWork(1)
        guard case let .analytic(.sphere(center, radius)) = surface,
              case let .sphericalGreatCircle(
                  cosine,
                  sine,
                  startParameter,
                  endParameter
              ) = parameterCurve else {
            return false
        }
        let definition: (center: Point3D, normal: Vector3D, radius: Double)
        if let exactCircle = circleDefinition(curve) {
            definition = exactCircle
        } else if case let .analytic(.ellipse(
            curveCenter,
            normal,
            _,
            majorRadius,
            minorRadius
        )) = curve,
                  abs(majorRadius - minorRadius) <= tolerance.distance {
            // An equal-radius ellipse carries an explicit parametric axis,
            // allowing a rigid transform to preserve the source parameter
            // exactly while remaining geometrically circular.
            definition = (curveCenter, normal, majorRadius)
        } else {
            throw correspondenceFailure(
                tolerance: tolerance,
                message: "A spherical great-circle pcurve requires an exact circular edge."
            )
        }
        let parameterSpan = endParameter - startParameter
        let radial = cosine * cos(startParameter) + sine * sin(startParameter)
        let radialDerivative = (
            cosine * -sin(startParameter) + sine * cos(startParameter)
        ) * parameterSpan
        let liftedStart = center + radial * radius
        let liftedDerivative = radialDerivative * radius
        let curveStart = try curve.differentialGeometry(
            at: startCurveParameter,
            tolerance: tolerance,
        using: &execution)
        let curveSpan = endCurveParameter - startCurveParameter
        let curveDerivative = curveStart.firstDerivative * curveSpan
        let normal = try definition.normal.normalized(
            tolerance: tolerance.distance
        )
        let greatCircleNormal = try cosine.cross(sine).normalized(
            tolerance: tolerance.distance
        )
        let derivativeScale = max(
            max(liftedDerivative.length, curveDerivative.length),
            1.0
        )
        guard definition.center.isApproximatelyEqual(
                  to: center,
                  tolerance: tolerance.distance
              ),
              abs(definition.radius - radius) <= tolerance.distance,
              abs(abs(normal.dot(greatCircleNormal)) - 1.0) <= tolerance.angle,
              curveStart.position.isApproximatelyEqual(
                  to: liftedStart,
                  tolerance: tolerance.distance
              ),
              (curveDerivative - liftedDerivative).length
                  <= tolerance.relative * derivativeScale else {
            throw correspondenceFailure(
                tolerance: tolerance,
                message: "A spherical great-circle pcurve does not reproduce its circular 3D edge."
            )
        }
        return true
    }

    private func validateAffineBilinearBSplinePcurveCorrespondence(
        curve: Curve3D,
        startCurveParameter: Double,
        endCurveParameter: Double,
        surface: Surface3D,
        parameterCurve: SurfaceParameterCurve,
        tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution) throws -> Bool {
        try execution.consumeWork(1)
        guard case let .bSpline(surfaceValue) = surface,
              case let .bSpline(curveValue) = curve,
              case let .bSpline(parameterValue) = parameterCurve,
              surfaceValue.uDegree == 1,
              surfaceValue.vDegree == 1,
              surfaceValue.uControlPointCount == 2,
              surfaceValue.vControlPointCount == 2,
              try isSingleBezierKnotVector(surfaceValue.uKnots, degree: 1, using: &execution),
              try isSingleBezierKnotVector(surfaceValue.vKnots, degree: 1, using: &execution),
              case let .closed(uLower, uUpper) = surfaceValue.uDomain,
              case let .closed(vLower, vUpper) = surfaceValue.vDomain else {
            return false
        }
        let flatWeights = surfaceValue.weights.flatMap { $0 }
        guard let referenceWeight = flatWeights.first,
              referenceWeight.isFinite,
              referenceWeight > Double.ulpOfOne else {
            return false
        }
        let weightTolerance = max(
            tolerance.relative * abs(referenceWeight) * 16.0,
            Double.ulpOfOne * abs(referenceWeight) * 256.0
        )
        guard flatWeights.allSatisfy({
            abs($0 - referenceWeight) <= weightTolerance
        }) else {
            return false
        }
        let origin = surfaceValue.controlPoints[0][0]
        let uVector = (surfaceValue.controlPoints[0][1] - origin) / (uUpper - uLower)
        let vVector = (surfaceValue.controlPoints[1][0] - origin) / (vUpper - vLower)
        let expectedCorner = origin
            + uVector * (uUpper - uLower)
            + vVector * (vUpper - vLower)
        guard expectedCorner.isApproximatelyEqual(
            to: surfaceValue.controlPoints[1][1],
            tolerance: tolerance.distance
        ) else {
            return false
        }
        let lifted = BSplineCurve3D(
            degree: parameterValue.degree,
            knots: parameterValue.knots,
            controlPoints: parameterValue.controlPoints.map { point in
                origin
                    + uVector * (point.x - uLower)
                    + vVector * (point.y - vLower)
            },
            weights: parameterValue.weights
        )
        try lifted.validate(tolerance: tolerance)
        let orientedCurve = try trimmedAndOriented(
            curveValue,
            from: startCurveParameter,
            to: endCurveParameter,
            tolerance: tolerance,
        using: &execution)
        guard try bSplineCurvesHaveSameBasisAndBoundedControls(
            orientedCurve,
            lifted,
            tolerance: tolerance,
        using: &execution) else {
            return false
        }
        return true
    }

    private func validateBilinearBSplineAffineCorrespondence(
        curve: Curve3D,
        startCurveParameter: Double,
        endCurveParameter: Double,
        surface: Surface3D,
        parameterCurve: SurfaceParameterCurve,
        tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution) throws -> Bool {
        try execution.consumeWork(1)
        guard case let .bSpline(surfaceValue) = surface,
              case let .bSpline(curveValue) = curve,
              case let .affine(
                  origin,
                  direction,
                  startParameter,
                  endParameter
              ) = parameterCurve,
              surfaceValue.uDegree == 1,
              surfaceValue.vDegree == 1,
              surfaceValue.uControlPointCount == 2,
              surfaceValue.vControlPointCount == 2,
              try isSingleBezierKnotVector(surfaceValue.uKnots, degree: 1, using: &execution),
              try isSingleBezierKnotVector(surfaceValue.vKnots, degree: 1, using: &execution) else {
            return false
        }
        let parameterSpan = endParameter - startParameter
        let start = Point2D(
            x: origin.x + direction.x * startParameter,
            y: origin.y + direction.y * startParameter
        )
        let end = Point2D(
            x: origin.x + direction.x * endParameter,
            y: origin.y + direction.y * endParameter
        )
        let middle = Point2D(
            x: origin.x + direction.x * (startParameter + parameterSpan * 0.5),
            y: origin.y + direction.y * (startParameter + parameterSpan * 0.5)
        )
        let startHomogeneous = try bilinearHomogeneousPoint(
            surfaceValue,
            u: start.x,
            v: start.y,
            tolerance: tolerance,
        using: &execution)
        let middleHomogeneous = try bilinearHomogeneousPoint(
            surfaceValue,
            u: middle.x,
            v: middle.y,
            tolerance: tolerance,
        using: &execution)
        let endHomogeneous = try bilinearHomogeneousPoint(
            surfaceValue,
            u: end.x,
            v: end.y,
            tolerance: tolerance,
        using: &execution)
        let middleControl = middleHomogeneous.scaled(by: 2.0)
            .subtracting(startHomogeneous.adding(endHomogeneous).scaled(by: 0.5))
        let homogeneousControls = [
            startHomogeneous,
            middleControl,
            endHomogeneous,
        ]
        guard homogeneousControls.allSatisfy({
            $0.weight.isFinite && $0.weight > Double.ulpOfOne
        }) else {
            throw correspondenceFailure(
                tolerance: tolerance,
                message: "An affine bilinear B-spline lift has a non-positive homogeneous weight."
            )
        }
        let lifted = BSplineCurve3D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: homogeneousControls.map { $0.euclideanPoint },
            weights: homogeneousControls.map({ $0.weight })
        )
        try lifted.validate(tolerance: tolerance)
        let orientedCurve = try trimmedAndOriented(
            curveValue,
            from: startCurveParameter,
            to: endCurveParameter,
            tolerance: tolerance,
        using: &execution)
        guard try bSplineCurvesHaveSameBasisAndBoundedControls(
            orientedCurve,
            lifted,
            tolerance: tolerance,
        using: &execution) else {
            throw correspondenceFailure(
                tolerance: tolerance,
                message: "An affine pcurve on a bilinear B-spline surface does not reproduce its exact 3D edge."
            )
        }
        return true
    }

    private func bilinearHomogeneousPoint(
        _ surface: BSplineSurface3D,
        u: Double,
        v: Double,
        tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution) throws -> HomogeneousCoordinate {
        try execution.consumeWork(1)
        guard case let .closed(uLower, uUpper) = surface.uDomain,
              case let .closed(vLower, vUpper) = surface.vDomain,
              u >= uLower,
              u <= uUpper,
              v >= vLower,
              v <= vUpper else {
            throw correspondenceFailure(
                tolerance: tolerance,
                message: "An affine bilinear B-spline pcurve leaves the surface domain."
            )
        }
        let normalizedU = (u - uLower) / (uUpper - uLower)
        let normalizedV = (v - vLower) / (vUpper - vLower)
        let lower = homogeneousCoordinate(
            point: surface.controlPoints[0][0],
            weight: surface.weights[0][0]
        ).interpolated(
            to: homogeneousCoordinate(
                point: surface.controlPoints[0][1],
                weight: surface.weights[0][1]
            ),
            parameter: normalizedU
        )
        let upper = homogeneousCoordinate(
            point: surface.controlPoints[1][0],
            weight: surface.weights[1][0]
        ).interpolated(
            to: homogeneousCoordinate(
                point: surface.controlPoints[1][1],
                weight: surface.weights[1][1]
            ),
            parameter: normalizedU
        )
        return lower.interpolated(to: upper, parameter: normalizedV)
    }

    private func homogeneousCoordinate(
        point: Point3D,
        weight: Double
    ) -> HomogeneousCoordinate {
        HomogeneousCoordinate(
            x: point.x * weight,
            y: point.y * weight,
            z: point.z * weight,
            weight: weight
        )
    }

    private func isSingleBezierKnotVector(
        _ knots: [Double],
        degree: Int
    , using execution: inout OriginalQueryExecution) throws -> Bool {
        guard knots.count == 2 * (degree + 1),
              let lower = knots.first,
              let upper = knots.last,
              upper > lower else {
            return false
        }
        return knots.prefix(degree + 1).allSatisfy { $0 == lower }
            && knots.suffix(degree + 1).allSatisfy { $0 == upper }
    }

    private func validateBSplineIsoparametricCorrespondence(
        curve: Curve3D,
        startCurveParameter: Double,
        endCurveParameter: Double,
        surface: Surface3D,
        parameterCurve: SurfaceParameterCurve,
        tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution) throws -> Bool {
        try execution.consumeWork(1)
        guard case let .bSpline(surfaceValue) = surface,
              case let .bSpline(curveValue) = curve else {
            return false
        }
        let boundary: BSplineCurve3D
        let parameterStart: Double
        let parameterEnd: Double
        switch parameterCurve {
        case .originalImage, .originalAffineWord: return false

        case let .constantU(u, vStart, vEnd):
            boundary = try surfaceValue.vIsoparametricCurve(
                atU: u,
                tolerance: tolerance,
            using: &execution)
            parameterStart = vStart
            parameterEnd = vEnd
        case let .constantV(v, uStart, uEnd):
            boundary = try surfaceValue.uIsoparametricCurve(
                atV: v,
                tolerance: tolerance,
            using: &execution)
            parameterStart = uStart
            parameterEnd = uEnd
        case .affine, .harmonic, .sphericalGreatCircle, .polyline, .bSpline, .originalBSplineContinuation,
             .certifiedImplicit, .certifiedAnalyticImplicit, .certifiedAnalyticPair,
             .projectedAnalytic, .rigidImage, .offsetSurfaceImage:
            return false
        case .periodicTranslation:
            return false
        }
        let orientedCurve = try trimmedAndOriented(
            curveValue,
            from: startCurveParameter,
            to: endCurveParameter,
            tolerance: tolerance,
        using: &execution)
        let orientedBoundary = try trimmedAndOriented(
            boundary,
            from: parameterStart,
            to: parameterEnd,
            tolerance: tolerance,
        using: &execution)
        guard try bSplineCurvesHaveSameBasisAndBoundedControls(
            orientedCurve,
            orientedBoundary,
            tolerance: tolerance,
        using: &execution) else {
            // Rational B-spline representations are not unique: multiplying
            // numerator and denominator by the same positive polynomial keeps
            // the exact curve but cannot be reduced by knot insertion and
            // degree elevation alone. Let the general interval-certified path
            // prove or reject that correspondence.
            return false
        }
        return true
    }

    private func validatePlanarBSplineCorrespondence(
        curve: Curve3D,
        startCurveParameter: Double,
        endCurveParameter: Double,
        surface: Surface3D,
        parameterCurve: SurfaceParameterCurve,
        tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution) throws -> Bool {
        try execution.consumeWork(1)
        guard isPlane(surface),
              case let .bSpline(curveValue) = curve,
              case let .bSpline(parameterValue) = parameterCurve else {
            return false
        }
        let lifted = BSplineCurve3D(
            degree: parameterValue.degree,
            knots: parameterValue.knots,
            controlPoints: try parameterValue.controlPoints.map { point in
                try surface.point(u: point.x, v: point.y, tolerance: tolerance, using: &execution)
            },
            weights: parameterValue.weights
        )
        let orientedCurve = try trimmedAndOriented(
            curveValue,
            from: startCurveParameter,
            to: endCurveParameter,
            tolerance: tolerance,
        using: &execution)
        guard try bSplineCurvesHaveSameBasisAndBoundedControls(
            orientedCurve,
            lifted,
            tolerance: tolerance,
        using: &execution) else {
            throw correspondenceFailure(
                tolerance: tolerance,
                message: "A planar B-spline pcurve does not lift to its exact 3D edge."
            )
        }
        return true
    }

    private func trimmedAndOriented(
        _ curve: BSplineCurve3D,
        from start: Double,
        to end: Double,
        tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution) throws -> BSplineCurve3D {
        try execution.consumeWork(1)
        if start < end {
            return try curve.trimmed(
                from: start,
                to: end,
                tolerance: tolerance,
            using: &execution)
        }
        return try curve.trimmed(
            from: end,
            to: start,
            tolerance: tolerance,
        using: &execution).reversed(tolerance: tolerance, using: &execution)
    }

    private func bSplineCurvesHaveSameBasisAndBoundedControls(
        _ lhs: BSplineCurve3D,
        _ rhs: BSplineCurve3D,
        tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution) throws -> Bool {
        try execution.consumeWork(1)
        var first = try normalizedCurve(lhs, tolerance: tolerance, using: &execution)
        var second = try normalizedCurve(rhs, tolerance: tolerance, using: &execution)
        if first.degree != second.degree {
            return try degreeElevatedBezierCurvesHaveBoundedControls(
                first,
                second,
                tolerance: tolerance,
            using: &execution)
        }
        let knotTolerance = max(
            tolerance.relative,
            Double.ulpOfOne * 256.0
        )
        let interiorKnots = try canonicalInteriorKnots(
            first.knots + second.knots,
            tolerance: knotTolerance
        , using: &execution)
        guard interiorKnots.count <= 4_096 else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "B-spline correspondence exceeded its common-knot partition budget."
            )
        }
        for knot in interiorKnots {
            let targetMultiplicity = max(
                try multiplicity(of: knot, in: first.knots, tolerance: knotTolerance, using: &execution),
                try multiplicity(of: knot, in: second.knots, tolerance: knotTolerance, using: &execution)
            )
            while try multiplicity(
                of: knot,
                in: first.knots,
                tolerance: knotTolerance
            , using: &execution) < targetMultiplicity {
                first = try first.insertingKnot(knot, tolerance: tolerance, using: &execution)
            }
            while try multiplicity(
                of: knot,
                in: second.knots,
                tolerance: knotTolerance
            , using: &execution) < targetMultiplicity {
                second = try second.insertingKnot(knot, tolerance: tolerance, using: &execution)
            }
        }
        guard first.knots.count == second.knots.count,
              zip(first.knots, second.knots).allSatisfy({
                  abs($0 - $1) <= knotTolerance
              }),
              first.controlPoints.count == second.controlPoints.count else {
            return false
        }
        return try homogeneousControlDistanceBound(first, second, using: &execution) <= tolerance.distance
    }

    private func degreeElevatedBezierCurvesHaveBoundedControls(
        _ first: BSplineCurve3D,
        _ second: BSplineCurve3D,
        tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution) throws -> Bool {
        try execution.consumeWork(1)
        let knotTolerance = max(
            tolerance.relative,
            Double.ulpOfOne * 256.0
        )
        let breakpoints = try canonicalInteriorKnots(
            first.knots + second.knots,
            tolerance: knotTolerance
        , using: &execution)
        guard breakpoints.count <= 4_096 else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "B-spline correspondence exceeded its degree-elevation partition budget."
            )
        }
        let partition = [0.0] + breakpoints + [1.0]
        let firstPatches = try bezierPatches(
            first,
            on: partition,
            tolerance: tolerance,
        using: &execution)
        let secondPatches = try bezierPatches(
            second,
            on: partition,
            tolerance: tolerance,
        using: &execution)
        guard firstPatches.count == secondPatches.count else {
            return false
        }
        let targetDegree = max(first.degree, second.degree)
        for index in firstPatches.indices {
            let firstControls = try elevatedHomogeneousControls(
                firstPatches[index],
                toDegree: targetDegree
            , using: &execution)
            let secondControls = try elevatedHomogeneousControls(
                secondPatches[index],
                toDegree: targetDegree
            , using: &execution)
            guard try homogeneousControlDistanceBound(
                firstControls,
                secondControls
            , using: &execution) <= tolerance.distance else {
                return false
            }
        }
        return true
    }

    private func bezierPatches(
        _ curve: BSplineCurve3D,
        on partition: [Double],
        tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution) throws -> [RationalBezierCurvePatch3D] {
        try execution.consumeWork(1)
        let sourcePatches = try BSplineCurveBezierDecomposer().curvePatches(
            curve: curve,
            tolerance: tolerance,
        using: &execution)
        var result: [RationalBezierCurvePatch3D] = []
        result.reserveCapacity(partition.count - 1)
        // The partition's breaks are the two curves' knots merged within a rounding, so a break
        // may sit a rounding off a patch end: it is that end.
        let knotTolerance = max(tolerance.relative, Double.ulpOfOne * 256.0)
        var sourceIndex = 0
        for index in 1..<partition.count {
            let lower = partition[index - 1]
            let upper = partition[index]
            while sourceIndex + 1 < sourcePatches.count,
                  sourcePatches[sourceIndex].upper <= lower + knotTolerance {
                sourceIndex += 1
            }
            let source = sourcePatches[sourceIndex]
            guard lower >= source.lower - knotTolerance,
                  upper <= source.upper + knotTolerance else {
                throw correspondenceFailure(
                    tolerance: tolerance,
                    message: "B-spline correspondence could not align its exact Bezier partitions."
                )
            }
            let (from, to) = (max(lower, source.lower), min(upper, source.upper))
            if abs(from - source.lower) <= knotTolerance, abs(to - source.upper) <= knotTolerance {
                result.append(source)
            } else {
                result.append(try source.trimmed(
                    from: from,
                    to: to,
                    tolerance: tolerance,
                using: &execution))
            }
        }
        return result
    }

    private func elevatedHomogeneousControls(
        _ patch: RationalBezierCurvePatch3D,
        toDegree targetDegree: Int
    , using execution: inout OriginalQueryExecution) throws -> [HomogeneousCurveControl] {
        try OriginalCoefficientAllocation.reserve(count: patch.controlPoints.count, of: HomogeneousCurveControl.self, using: &execution)
        var result = patch.controlPoints.indices.map {
            HomogeneousCurveControl(
                point: patch.controlPoints[$0],
                weight: patch.weights[$0]
            )
        }
        while result.count - 1 < targetDegree {
            let nextDegree = result.count
            try OriginalCoefficientAllocation.reserve(count: try exactScalarCount(result.count, 1), of: HomogeneousCurveControl.self, using: &execution)
            var elevated = Array(
                repeating: HomogeneousCurveControl.zero,
                count: result.count + 1
            )
            elevated[0] = result[0]
            elevated[elevated.count - 1] = result[result.count - 1]
            if result.count > 1 {
                for index in 1..<result.count {
                    let alpha = Double(index) / Double(nextDegree)
                    elevated[index] = result[index - 1].scaled(by: alpha)
                        .adding(result[index].scaled(by: 1.0 - alpha))
                }
            }
            result = elevated
        }
        return result
    }

    private func normalizedCurve(
        _ curve: BSplineCurve3D,
        tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution) throws -> BSplineCurve3D {
        try execution.consumeWork(1)
        guard case let .closed(lower, upper) = curve.domain,
              upper > lower else {
            throw correspondenceFailure(
                tolerance: tolerance,
                message: "B-spline correspondence requires a bounded nondegenerate domain."
            )
        }
        let span = upper - lower
        try OriginalCoefficientAllocation.reserve(count: curve.knots.count, of: Double.self, using: &execution)
        let normalized = BSplineCurve3D(
            degree: curve.degree,
            knots: curve.knots.map { ($0 - lower) / span },
            controlPoints: curve.controlPoints,
            weights: curve.weights
        )
        try normalized.validate(tolerance: tolerance, using: &execution)
        return normalized
    }

    private func canonicalInteriorKnots(
        _ knots: [Double],
        tolerance: Double
    , using execution: inout OriginalQueryExecution) throws -> [Double] {
        try execution.consumeWork(1)
        var result: [Double] = []
        try OriginalCoefficientAllocation.reserve(count: try exactScalarCount(knots.count, 2, multiply: true), of: Double.self, using: &execution)
        for knot in try knots.sorted(by: { left, right in
            try execution.consumeWork(1); return left < right
        })
            where knot > tolerance && knot < 1.0 - tolerance {
            if let last = result.last, abs(last - knot) <= tolerance {
                continue
            }
            result.append(knot)
        }
        return result
    }

    private func multiplicity(
        of knot: Double,
        in knots: [Double],
        tolerance: Double
    , using execution: inout OriginalQueryExecution) throws -> Int {
        try execution.consumeWork(1)
        return try knots.reduce(0) { count, candidate in
            try execution.consumeWork(1)
            return count + (abs(candidate - knot) <= tolerance ? 1 : 0)
        }
    }

    private func homogeneousControlDistanceBound(
        _ first: BSplineCurve3D,
        _ second: BSplineCurve3D
    , using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        try OriginalCoefficientAllocation.reserve(count: try exactScalarCount(first.controlPoints.count, second.controlPoints.count),
            of: HomogeneousCurveControl.self, using: &execution)
        return try homogeneousControlDistanceBound(
            first.controlPoints.indices.map {
                HomogeneousCurveControl(
                    point: first.controlPoints[$0],
                    weight: first.weights[$0]
                )
            },
            second.controlPoints.indices.map {
                HomogeneousCurveControl(
                    point: second.controlPoints[$0],
                    weight: second.weights[$0]
                )
            }
        , using: &execution)
    }

    private func homogeneousControlDistanceBound(
        _ first: [HomogeneousCurveControl],
        _ second: [HomogeneousCurveControl]
    , using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        guard first.count == second.count,
              first.isEmpty == false,
              let firstScale = first.first?.weight,
              let secondScale = second.first?.weight,
              firstScale > 0.0,
              secondScale > 0.0 else {
            return .infinity
        }
        try OriginalCoefficientAllocation.reserve(count: try exactScalarCount(first.count, second.count), of: Double.self, using: &execution)
        let firstWeights = first.map { $0.weight / firstScale }
        let secondWeights = second.map { $0.weight / secondScale }
        guard let minimumFirstWeight = firstWeights.min(),
              let minimumSecondWeight = secondWeights.min(),
              minimumFirstWeight > 0.0,
              minimumSecondWeight > 0.0 else {
            return .infinity
        }
        var maximumWeightedPointDifference = 0.0
        var maximumWeightDifference = 0.0
        var maximumSecondWeightedPointLength = 0.0
        for index in first.indices {
            let firstWeighted = first[index].weightedPoint / firstScale
            let secondWeighted = second[index].weightedPoint / secondScale
            maximumWeightedPointDifference = max(
                maximumWeightedPointDifference,
                (firstWeighted - secondWeighted).length.nextUp
            )
            maximumWeightDifference = max(
                maximumWeightDifference,
                abs(firstWeights[index] - secondWeights[index]).nextUp
            )
            maximumSecondWeightedPointLength = max(
                maximumSecondWeightedPointLength,
                secondWeighted.length.nextUp
            )
        }
        return (
            maximumWeightedPointDifference / minimumFirstWeight
                + maximumSecondWeightedPointLength * maximumWeightDifference
                    / (minimumFirstWeight * minimumSecondWeight)
        ).nextUp
    }

    private func cellIsCertified(
        _ cell: Cell,
        curve: Curve3D,
        surface: Surface3D,
        parameterCurve: SurfaceParameterCurve,
        curveSecondDerivativeUpperBound: Double?,
        localCurveSecondDerivativeBound: (Double, Double, inout OriginalQueryExecution) throws -> Double?,
        localCurveFirstDerivativeBound: (Double, Double, inout OriginalQueryExecution) throws -> Double?,
        liftSecondDerivativeUpperBound: Double?,
        localLiftSecondDerivativeBound: (Double, Double, inout OriginalQueryExecution) throws -> Double?,
        localLiftFirstDerivativeBound: (Double, Double, inout OriginalQueryExecution) throws -> Double?,
        acceptanceDeviation: Double,
        tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution) throws -> CellCertification {
        try execution.consumeWork(1)
        let width = cell.upper.fraction - cell.lower.fraction
        guard width > 0.0 else {
            throw correspondenceFailure(
                tolerance: tolerance,
                message: "Curve-surface correspondence subdivision collapsed."
            )
        }
        let middleFraction = (cell.lower.fraction + cell.upper.fraction) * 0.5
        let middleCurveParameter = (
            cell.lower.curveParameter + cell.upper.curveParameter
        ) * 0.5
        let lift = SurfaceLiftCurve3D(
            surface: surface,
            parameterCurve: parameterCurve
        )
        let lifted = try lift.differentialGeometryAssumingValid(
            atNormalizedFraction: middleFraction,
            tolerance: tolerance,
        using: &execution)
        let curveGeometry = try curve.differentialGeometryAssumingValid(
            at: middleCurveParameter,
            tolerance: tolerance,
        using: &execution)
        let parameterSlope = (
            cell.upper.curveParameter - cell.lower.curveParameter
        ) / width
        let residual = (lifted.position - curveGeometry.position).length
        let derivativeResidual = (
            lifted.firstDerivative - curveGeometry.firstDerivative * parameterSlope
        ).length
        let halfWidth = width * 0.5
        // A curvature spike anywhere in the validated span inflates the
        // global curve bound for every cell. An exact bound for this
        // adaptive cell keeps smooth spans independent from the spike.
        func certifies(
            curveBound: Double,
            liftBound: Double
        ) -> Bool {
            let bound = upwardSum(
                liftBound,
                upwardProduct(
                    curveBound,
                    upwardProduct(abs(parameterSlope), abs(parameterSlope))
                )
            )
            let localUpperBound = upwardSum(
                residual,
                upwardSum(
                    upwardProduct(derivativeResidual, halfWidth),
                    upwardProduct(
                        0.5,
                        upwardProduct(
                            bound,
                            upwardProduct(halfWidth, halfWidth)
                        )
                    )
                )
            )
            return localUpperBound <= acceptanceDeviation
        }
        if let curveSecondDerivativeUpperBound, let liftSecondDerivativeUpperBound,
           certifies(curveBound: curveSecondDerivativeUpperBound,
                     liftBound: liftSecondDerivativeUpperBound) {
            return CellCertification(isCertified: true, curvePoint: curveGeometry.position)
        }
        let cellLower = min(cell.lower.curveParameter, cell.upper.curveParameter)
        let cellUpper = max(cell.lower.curveParameter, cell.upper.curveParameter)
        let cellCurveBound = try localCurveSecondDerivativeBound(
            cellLower,
            cellUpper
        , &execution)
        guard let cellLiftBound = try localLiftSecondDerivativeBound(
            cell.lower.fraction,
            cell.upper.fraction
        , &execution) else {
            return CellCertification(isCertified: false, curvePoint: curveGeometry.position)
        }
        if let cellCurveBound, certifies(
               curveBound: cellCurveBound,
               liftBound: cellLiftBound
           ) {
            return CellCertification(
                isCertified: true,
                curvePoint: curveGeometry.position
            )
        }
        // The curve's second-derivative certificate can saturate at a fixed
        // partition floor near a curvature spike; a Lipschitz argument over
        // the cell needs only finite first-derivative bounds and converges
        // linearly in the cell width.
        func lipschitzCertifies(
            curveFirst: Double,
            liftFirst: Double?
        ) -> Bool {
            let midpointLiftFirst = upwardSum(
                hypot(
                    hypot(lifted.firstDerivative.x, lifted.firstDerivative.y),
                    lifted.firstDerivative.z
                ),
                upwardProduct(cellLiftBound, halfWidth)
            )
            let liftFirstSupremum = min(
                liftFirst ?? midpointLiftFirst,
                midpointLiftFirst
            )
            let lipschitzUpperBound = upwardSum(
                residual,
                upwardProduct(
                    halfWidth,
                    upwardSum(
                        liftFirstSupremum,
                        upwardProduct(curveFirst, abs(parameterSlope))
                    )
                )
            )
            return lipschitzUpperBound <= acceptanceDeviation
        }
        if let cellFirst = try localCurveFirstDerivativeBound(
            cellLower,
            cellUpper
        , &execution), lipschitzCertifies(
            curveFirst: cellFirst,
            liftFirst: try localLiftFirstDerivativeBound(
                cell.lower.fraction,
                cell.upper.fraction
            , &execution)
        ) {
            return CellCertification(
                isCertified: true,
                curvePoint: curveGeometry.position
            )
        }
        return CellCertification(
            isCertified: false,
            curvePoint: curveGeometry.position
        )
    }

    private func projectedNode(
        fraction: Double,
        candidateCurveParameter: Double,
        curve: Curve3D,
        surface: Surface3D,
        parameterCurve: SurfaceParameterCurve,
        candidateCurvePoint: Point3D? = nil,
        projectionOptions: CurveParameterProjectionOptions,
        acceptanceDeviation: Double,
        tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution) throws -> Node {
        try execution.consumeWork(1)
        let parameter = try parameterAssumingValidated(
            parameterCurve,
            atNormalizedFraction: fraction,
            tolerance: tolerance,
        using: &execution)
        let point = try surface.point(
            u: parameter.u,
            v: parameter.v,
            tolerance: tolerance,
        using: &execution)
        if candidateCurveParameter.isFinite,
           let parameterRange = projectionOptions.parameterRange,
           parameterRange.contains(candidateCurveParameter) {
            let candidatePoint: Point3D
            if let candidateCurvePoint {
                candidatePoint = candidateCurvePoint
            } else {
                candidatePoint = try curve.point(
                    at: candidateCurveParameter,
                    tolerance: tolerance,
                using: &execution)
            }
            if (candidatePoint - point).length <= acceptanceDeviation {
                return Node(
                    fraction: fraction,
                    curveParameter: candidateCurveParameter
                )
            }
        }
        let projection: CurveParameterProjection
        do {
            projection = try curve.parameterProjection(
                of: point,
                options: projectionOptions,
                tolerance: tolerance,
            using: &execution)
        } catch let error as KernelError where
            error.code == .resourceLimitExceeded
                || error.code == .ambiguousSelection
                || error.code == .singularSystem {
            throw KernelError(
                phase: .topology,
                code: error.code,
                residual: error.residual,
                tolerance: tolerance,
                message: "Curve-surface correspondence projection failed: \(error.message)"
            )
        } catch {
            throw correspondenceFailure(
                tolerance: tolerance,
                message: "A pcurve point has no verified projection onto its exact 3D edge."
            )
        }
        guard projection.residual <= tolerance.distance else {
            throw correspondenceFailure(
                residual: projection.residual,
                tolerance: tolerance,
                message: "A pcurve point exceeds the 3D edge tolerance."
            )
        }
        return Node(fraction: fraction, curveParameter: projection.parameter)
    }

    private func parameterAssumingValidated(
        _ parameterCurve: SurfaceParameterCurve,
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution) throws -> SurfaceParameter {
        try execution.consumeWork(1)
        guard case let .bSpline(curve) = parameterCurve,
              case let .closed(lower, upper) = curve.domain else {
            return try parameterCurve.parameter(
                atNormalizedFraction: fraction,
                tolerance: tolerance,
            using: &execution)
        }
        let parameter = lower + (upper - lower) * fraction
        let point = try curve.pointAssumingValid(
            at: parameter,
            tolerance: tolerance,
        using: &execution)
        return SurfaceParameter(u: point.x, v: point.y)
    }

    private func validateMonotone(
        _ nodes: [Node],
        tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        guard nodes.count >= 2 else { return }
        let direction = nodes[nodes.count - 1].curveParameter
            - nodes[0].curveParameter
        guard abs(direction) > tolerance.relative else {
            throw correspondenceFailure(
                tolerance: tolerance,
                message: "Curve-surface correspondence has no oriented parameter span."
            )
        }
        for index in 1..<nodes.count {
            let step = nodes[index].curveParameter - nodes[index - 1].curveParameter
            let orientedStep = direction > 0.0 ? step : -step
            guard orientedStep >= -tolerance.relative else {
                throw correspondenceFailure(
                    tolerance: tolerance,
                    message: "A face pcurve reverses direction along its 3D edge."
                )
            }
        }
    }

    private func derivativeBounds(
        for curve: SurfaceParameterCurve,
        surface: Surface3D,
        tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution) throws -> ParameterDerivativeBounds {
        try execution.consumeWork(1)
        switch curve {
        case .originalAffineWord(let image):
            guard let jet = try image.intervalJet(over: ScalarInterval(lower: 0, upper: 1), tolerance: tolerance, using: &execution) else {
                throw correspondenceFailure(tolerance: tolerance, message: "Original word chart lost complete derivative authority.")
            }
            return ParameterDerivativeBounds(firstU: jet.u.derivativeU.absoluteUpperBound,
                firstV: jet.v.derivativeU.absoluteUpperBound, secondU: jet.u.secondDerivativeUU.absoluteUpperBound,
                secondV: jet.v.secondDerivativeUU.absoluteUpperBound, vAbsolute: jet.v.value.absoluteUpperBound,
                breaks: try SurfaceLiftDifferentialBounder().breakParameters(lift: SurfaceLiftCurve3D(
                    surface: surface, parameterCurve: curve), within: ScalarInterval(lower: 0, upper: 1), tolerance: tolerance, using: &execution))
        case .originalImage(let image):
            guard let jet = try image.intervalJet(over: ScalarInterval(lower: 0, upper: 1), tolerance: tolerance, using: &execution) else {
                throw correspondenceFailure(tolerance: tolerance, message: "Original image chart lost complete derivative authority.")
            }
            return ParameterDerivativeBounds(firstU: jet.u.derivativeU.absoluteUpperBound,
                firstV: jet.v.derivativeU.absoluteUpperBound, secondU: jet.u.secondDerivativeUU.absoluteUpperBound,
                secondV: jet.v.secondDerivativeUU.absoluteUpperBound, vAbsolute: jet.v.value.absoluteUpperBound,
                breaks: try SurfaceLiftDifferentialBounder().breakParameters(lift: SurfaceLiftCurve3D(
                    surface: surface, parameterCurve: curve), within: ScalarInterval(lower: 0, upper: 1), tolerance: tolerance, using: &execution))

        case let .affine(_, direction, start, end):
            let scale = abs(end - start)
            return ParameterDerivativeBounds(
                firstU: upwardProduct(abs(direction.x), scale),
                firstV: upwardProduct(abs(direction.y), scale),
                secondU: 0.0,
                secondV: 0.0,
                vAbsolute: try maximumAbsoluteV(curve, tolerance: tolerance, using: &execution),
                breaks: []
            )
        case let .constantU(_, vStart, vEnd):
            return ParameterDerivativeBounds(
                firstU: 0.0,
                firstV: abs(vEnd - vStart).nextUp,
                secondU: 0.0,
                secondV: 0.0,
                vAbsolute: max(abs(vStart), abs(vEnd)).nextUp,
                breaks: []
            )
        case let .constantV(v, uStart, uEnd):
            return ParameterDerivativeBounds(
                firstU: abs(uEnd - uStart).nextUp,
                firstV: 0.0,
                secondU: 0.0,
                secondV: 0.0,
                vAbsolute: abs(v).nextUp,
                breaks: []
            )
        case let .harmonic(_, cosine, sine, start, end):
            let scale = abs(end - start)
            let scaleSquared = upwardProduct(scale, scale)
            let uAmplitude = hypot(cosine.x, sine.x).nextUp
            let vAmplitude = hypot(cosine.y, sine.y).nextUp
            return ParameterDerivativeBounds(
                firstU: upwardProduct(scale, uAmplitude),
                firstV: upwardProduct(scale, vAmplitude),
                secondU: upwardProduct(scaleSquared, uAmplitude),
                secondV: upwardProduct(scaleSquared, vAmplitude),
                vAbsolute: try maximumAbsoluteV(curve, tolerance: tolerance, using: &execution),
                breaks: []
            )
        case let .polyline(points):
            var totalLength = 0.0
            var lengths: [Double] = []
            for index in 1..<points.count {
                let length = hypot(
                    points[index].u - points[index - 1].u,
                    points[index].v - points[index - 1].v
                )
                lengths.append(length)
                totalLength = upwardSum(totalLength, length)
            }
            guard totalLength > Double.ulpOfOne else {
                throw GeometryError.invalidDistance(totalLength)
            }
            var accumulated = 0.0
            var breaks: [Double] = []
            for length in lengths.dropLast() {
                accumulated += length
                breaks.append(accumulated / totalLength)
            }
            return ParameterDerivativeBounds(
                firstU: totalLength,
                firstV: totalLength,
                secondU: 0.0,
                secondV: 0.0,
                vAbsolute: points.map { abs($0.v) }.max()?.nextUp ?? 0.0,
                breaks: breaks
            )
        case .sphericalGreatCircle:
            throw correspondenceFailure(
                tolerance: tolerance,
                message: "A spherical great-circle pcurve failed its structural circular-edge proof."
            )
        case let .originalBSplineContinuation(value):
            let jet = try value.intervalJet(over: ScalarInterval(lower: 0, upper: 1), tolerance: tolerance, using: &execution)
            let span = value.endParameter - value.startParameter
            let breaks = value.original.knots.map { ($0 - value.startParameter) / span }
                .filter { $0 > 0 && $0 < 1 }.sorted()
            return ParameterDerivativeBounds(firstU: jet.u.derivativeU.absoluteUpperBound,
                firstV: jet.v.derivativeU.absoluteUpperBound, secondU: jet.u.secondDerivativeUU.absoluteUpperBound,
                secondV: jet.v.secondDerivativeUU.absoluteUpperBound, vAbsolute: jet.v.value.absoluteUpperBound,
                breaks: breaks)
        case let .bSpline(curve):
            let patches = try curve.rationalBezierPatches(
                tolerance: tolerance,
            using: &execution)
            guard case let .closed(domainLower, domainUpper) = curve.domain,
                  patches.isEmpty == false else {
                throw correspondenceFailure(
                    tolerance: tolerance,
                    message: "B-spline pcurve correspondence requires a bounded non-empty domain."
                )
            }
            let domainWidth = domainUpper - domainLower
            var firstU = 0.0
            var firstV = 0.0
            var secondU = 0.0
            var secondV = 0.0
            var vAbsolute = 0.0
            var breaks: [Double] = []
            for (index, patch) in patches.enumerated() {
                try execution.consumeWork(1)
                try OriginalCoefficientAllocation.reserve(count: 2, of: [Double].self, using: &execution)
                try OriginalCoefficientAllocation.reserve(count: try exactScalarCount(patch.controlPoints.count, 2, multiply: true), of: Double.self, using: &execution)
                let bound = try RationalBezierCurveDerivativeBound(
                    coordinates: [
                        patch.controlPoints.map({ $0.x }),
                        patch.controlPoints.map({ $0.y }),
                    ],
                    weights: patch.weights,
                    parameterWidth: patch.upper - patch.lower,
                    tolerance: tolerance
                , using: &execution)
                firstU = max(
                    firstU,
                    upwardProduct(bound.first[0], domainWidth)
                )
                firstV = max(
                    firstV,
                    upwardProduct(bound.first[1], domainWidth)
                )
                let domainWidthSquared = upwardProduct(
                    domainWidth,
                    domainWidth
                )
                secondU = max(
                    secondU,
                    upwardProduct(bound.second[0], domainWidthSquared)
                )
                secondV = max(
                    secondV,
                    upwardProduct(bound.second[1], domainWidthSquared)
                )
                vAbsolute = max(
                    vAbsolute,
                    patch.controlPoints.map { abs($0.y) }.max()?.nextUp ?? 0.0
                )
                if index + 1 < patches.count {
                    breaks.append((patch.upper - domainLower) / domainWidth)
                }
            }
            return ParameterDerivativeBounds(
                firstU: firstU,
                firstV: firstV,
                secondU: secondU,
                secondV: secondV,
                vAbsolute: vAbsolute,
                breaks: breaks
            )
        case let .certifiedImplicit(certified):
            let count = certified.intersection.cells.count
            let delta = certified.endFraction - certified.startFraction
            let scale = abs(delta).nextUp
            let scaleSquared = upwardProduct(scale, scale)
            let breaks = (0...(2 * count)).map {
                (Double($0) / Double(count) - certified.startFraction) / delta
            }.filter { $0 > 0 && $0 < 1 }.sorted()
            let jet = try SurfaceLiftDifferentialBounder().implicitParameterBounds(
                certified, tolerance: tolerance, using: &execution)
            func magnitude(_ value: ScalarInterval) -> Double {
                max(abs(value.lower), abs(value.upper)).nextUp
            }
            return ParameterDerivativeBounds(
                firstU: upwardProduct(magnitude(jet.u.firstDerivative), scale),
                firstV: upwardProduct(magnitude(jet.v.firstDerivative), scale),
                secondU: upwardProduct(magnitude(jet.u.secondDerivative), scaleSquared),
                secondV: upwardProduct(magnitude(jet.v.secondDerivative), scaleSquared),
                vAbsolute: magnitude(jet.v.value), breaks: breaks)
        case .certifiedAnalyticImplicit, .certifiedAnalyticPair,
             .projectedAnalytic:
            throw correspondenceFailure(
                tolerance: tolerance,
                message: "A certified pcurve failed its structural source-curve match."
            )
        case .rigidImage:
            throw correspondenceFailure(
                tolerance: tolerance,
                message: "A rigid-image pcurve failed its structural source-transform proof."
            )
        case let .offsetSurfaceImage(image):
            return try derivativeBounds(
                for: image.source,
                surface: image.sourceSurface,
                tolerance: tolerance,
            using: &execution)
        case let .periodicTranslation(base, _, vShift):
            let bounds = try derivativeBounds(
                for: base,
                surface: surface,
                tolerance: tolerance,
            using: &execution)
            return ParameterDerivativeBounds(
                firstU: bounds.firstU,
                firstV: bounds.firstV,
                secondU: bounds.secondU,
                secondV: bounds.secondV,
                vAbsolute: (bounds.vAbsolute + abs(vShift)).nextUp,
                breaks: bounds.breaks
            )
        }
    }

    private func maximumAbsoluteV(
        _ curve: SurfaceParameterCurve,
        tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        let start = try curve.parameter(atNormalizedFraction: 0.0, tolerance: tolerance, using: &execution)
        let end = try curve.parameter(atNormalizedFraction: 1.0, tolerance: tolerance, using: &execution)
        switch curve {
        case let .harmonic(center, cosine, sine, _, _):
            let amplitude = hypot(cosine.y, sine.y).nextUp
            return max(
                abs(center.y - amplitude),
                abs(center.y + amplitude)
            ).nextUp
        default:
            return max(abs(start.v), abs(end.v)).nextUp
        }
    }

    private func liftSecondDerivativeUpperBound(
        surface: Surface3D,
        parameterBounds: ParameterDerivativeBounds,
        tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        let uFirst = parameterBounds.firstU
        let vFirst = parameterBounds.firstV
        let uSecond = parameterBounds.secondU
        let vSecond = parameterBounds.secondV
        switch surface {
        case .procedural(.originalAffineWord), .procedural(.originalAngularTransport):
            // FIXME(INCOMPLETE_IMPLEMENTATION): Legacy scalar lift tightening
            // does not own a flat-word source jet. Word coedges use the original
            // bounded correspondence producer before this specialization.
            throw resourceFailure(tolerance: tolerance,
                message: "Original word support requires its prepared whole-jet correspondence route.")
        case let .procedural(.originalImage(image)):
            let native = ParameterDerivativeBounds(
                firstU: abs(image.uGain) * parameterBounds.firstU,
                firstV: abs(image.vGain) * parameterBounds.firstV,
                secondU: abs(image.uGain) * parameterBounds.secondU,
                secondV: abs(image.vGain) * parameterBounds.secondV,
                vAbsolute: abs(image.vOffset) + abs(image.vGain) * parameterBounds.vAbsolute,
                breaks: parameterBounds.breaks)
            return try liftSecondDerivativeUpperBound(surface: image.source,
                parameterBounds: native, tolerance: tolerance, using: &execution) * image.transform.linearMagnitudeUpperBound

        case .plane, .analytic(.plane):
            return hypot(uSecond, vSecond).nextUp
        case let .cylinder(cylinder):
            return cylinderSecondDerivativeBound(
                radius: cylinder.radius,
                uFirst: uFirst,
                uSecond: uSecond,
                vSecond: vSecond
            )
        case let .analytic(.cylinder(_, _, radius)):
            return cylinderSecondDerivativeBound(
                radius: radius,
                uFirst: uFirst,
                uSecond: uSecond,
                vSecond: vSecond
            )
        case let .analytic(.cone(_, _, halfAngle)):
            let sine = abs(sin(halfAngle)).nextUp
            return upwardSum(
                upwardProduct(
                    upwardProduct(parameterBounds.vAbsolute, sine),
                    upwardProduct(uFirst, uFirst)
                ),
                upwardSum(
                    upwardProduct(
                        2.0,
                        upwardProduct(sine, upwardProduct(uFirst, vFirst))
                    ),
                    upwardSum(
                        upwardProduct(
                            upwardProduct(parameterBounds.vAbsolute, sine),
                            uSecond
                        ),
                        vSecond
                    )
                )
            )
        case let .analytic(.sphere(_, radius)):
            return upwardProduct(
                radius,
                upwardSum(
                    upwardSum(
                        upwardProduct(uFirst, uFirst),
                        upwardProduct(2.0, upwardProduct(uFirst, vFirst))
                    ),
                    upwardSum(
                        upwardProduct(vFirst, vFirst),
                        upwardSum(uSecond, vSecond)
                    )
                )
            )
        case let .analytic(.torus(_, _, majorRadius, minorRadius)):
            return upwardSum(
                upwardProduct(
                    majorRadius + minorRadius,
                    upwardSum(upwardProduct(uFirst, uFirst), uSecond)
                ),
                upwardProduct(
                    minorRadius,
                    upwardSum(
                        upwardProduct(2.0, upwardProduct(uFirst, vFirst)),
                        upwardSum(upwardProduct(vFirst, vFirst), vSecond)
                    )
                )
            )
        case let .bSpline(surface):
            let surfaceBounds = try CubicSurfaceResidualCertifier
                .SurfaceDerivativeBounds(
                    surface: surface,
                    tolerance: tolerance, using: &execution
                )
            let result = upwardSum(
                upwardSum(
                    upwardProduct(
                        surfaceBounds.secondUU,
                        upwardProduct(uFirst, uFirst)
                    ),
                    upwardProduct(
                        2.0,
                        upwardProduct(
                            surfaceBounds.secondUV,
                            upwardProduct(uFirst, vFirst)
                        )
                    )
                ),
                upwardSum(
                    upwardProduct(
                        surfaceBounds.secondVV,
                        upwardProduct(vFirst, vFirst)
                    ),
                    upwardSum(
                        upwardProduct(surfaceBounds.tangentU, uSecond),
                        upwardProduct(surfaceBounds.tangentV, vSecond)
                    )
                )
            )
            guard result.isFinite else {
                throw resourceFailure(
                    tolerance: tolerance,
                    message: "B-spline surface-lift derivative certification exceeded finite arithmetic."
                )
            }
            return result
        case let .procedural(.offset(offset)):
            if let equivalent = try offset.exactChartPreservingSurface(
                tolerance: tolerance
            ) {
                return try liftSecondDerivativeUpperBound(
                    surface: equivalent,
                    parameterBounds: parameterBounds,
                    tolerance: tolerance,
                using: &execution)
            }
            if try DefaultPlanarSurfaceResolver().exactPlane(
                for: surface,
                tolerance: tolerance
            ) != nil {
                return hypot(uSecond, vSecond).nextUp
            }
            throw resourceFailure(
                tolerance: tolerance,
                message: "General procedural surface-lift correspondence requires local parameter-cell differential bounds."
            )
        case .procedural(.ruled), .procedural(.rollingBall), .procedural(.originalRevolution), .procedural(.originalCoons), .procedural(.originalBoundaryCorrected), .procedural(.originalPlaneDerivative), .procedural(.originalDrafted):
            throw resourceFailure(
                tolerance: tolerance,
                message: "General procedural surface-lift correspondence requires local parameter-cell differential bounds."
            )
        }
    }

    private func cylinderSecondDerivativeBound(
        radius: Double,
        uFirst: Double,
        uSecond: Double,
        vSecond: Double
    ) -> Double {
        upwardSum(
            upwardProduct(
                radius,
                upwardSum(upwardProduct(uFirst, uFirst), uSecond)
            ),
            vSecond
        )
    }

    private func curveSecondDerivativeUpperBound(
        _ curve: Curve3D,
        parameterRange: ScalarInterval,
        tolerance: ModelingTolerance,
        preparedCurve: PreparedCurveDifferentialEncloser? = nil,
    using execution: inout OriginalQueryExecution) throws -> Double? {
        try execution.consumeWork(1)
        switch curve {
        case let .parameterImage(image):
            guard let original = try curveSecondDerivativeUpperBound(image.source,
                parameterRange: image.originalInterval(parameterRange, using: &execution), tolerance: tolerance, using: &execution) else { return nil }
            return (original * image.gain * image.gain).nextUp

        case .line, .analytic(.line):
            return 0.0
        case let .circle(circle):
            return circle.radius.nextUp
        case let .analytic(.circle(_, _, radius)),
             let .analytic(.arc(_, _, radius, _, _)):
            return radius.nextUp
        case let .analytic(.ellipse(_, _, _, majorRadius, minorRadius)):
            return max(majorRadius, minorRadius).nextUp
        case let .analytic(.hyperbola(curve)):
            let maximumAbsoluteParameter = max(
                abs(parameterRange.lower),
                abs(parameterRange.upper)
            )
            let hyperbolicCosine = cosh(maximumAbsoluteParameter)
            let hyperbolicSine = sinh(maximumAbsoluteParameter)
            let bound = hypot(
                curve.transverseRadius * hyperbolicCosine,
                curve.conjugateRadius * hyperbolicSine
            )
            guard bound.isFinite else {
                throw resourceFailure(
                    tolerance: tolerance,
                    message: "Hyperbola correspondence derivative certification exceeded finite arithmetic."
                )
            }
            return bound.nextUp
        case let .analytic(.parabola(curve)):
            return (1.0 / (2.0 * curve.focalLength)).nextUp
        case let .bSpline(curve):
            guard try spatialBSplineIntervalHasNativeAuthority(curve, parameterRange: parameterRange, using: &execution),
                  try !spatialBSplineHasInteriorDerivativeJump(curve, parameterRange: parameterRange, using: &execution) else {
                return nil
            }
            let patches = try BSplineCurveBezierDecomposer().curvePatches(
                curve: curve,
                tolerance: tolerance,
            using: &execution)
            guard patches.isEmpty == false else {
                throw correspondenceFailure(
                    tolerance: tolerance,
                    message: "B-spline curve correspondence requires a non-empty Bezier decomposition."
                )
            }
            var maximum = 0.0
            for patch in patches {
                try execution.consumeWork(1)
                try OriginalCoefficientAllocation.reserve(count: 3, of: [Double].self, using: &execution)
                try OriginalCoefficientAllocation.reserve(count: try exactScalarCount(patch.controlPoints.count, 3, multiply: true), of: Double.self, using: &execution)
                let bound = try RationalBezierCurveDerivativeBound(
                    coordinates: [
                        patch.controlPoints.map({ $0.x }),
                        patch.controlPoints.map({ $0.y }),
                        patch.controlPoints.map({ $0.z }),
                    ],
                    weights: patch.weights,
                    parameterWidth: patch.upper - patch.lower,
                    tolerance: tolerance
                , using: &execution)
                maximum = max(
                    maximum,
                    hypot(
                        hypot(bound.second[0], bound.second[1]),
                        bound.second[2]
                    ).nextUp
                )
            }
            return maximum
        case let .surfaceLift(lift):
            guard let bound = try SurfaceLiftDifferentialBounder()
                .secondDerivativeMagnitude(
                    lift: lift,
                    interval: parameterRange,
                    tolerance: tolerance,
                using: &execution) else {
                throw correspondenceFailure(
                    tolerance: tolerance,
                    message: "Surface-lift correspondence could not certify a finite second-derivative bound."
                )
            }
            return bound
        case let .rigidImage(image):
            return try curveSecondDerivativeUpperBound(
                image.source,
                parameterRange: parameterRange,
                tolerance: tolerance,
            using: &execution)
        case let .affineImage(image):
            guard let sourceBound = try curveSecondDerivativeUpperBound(
                image.source,
                parameterRange: parameterRange,
                tolerance: tolerance,
            using: &execution) else { return nil }
            let transformedBound = (
                sourceBound * image.transform.linearMagnitudeUpperBound
            ).nextUp
            guard transformedBound.isFinite else {
                throw resourceFailure(
                    tolerance: tolerance,
                    message: "Affine-image correspondence derivative certification exceeded finite arithmetic."
                )
            }
            return transformedBound
        case .originalAffineWord, .originalEndpointConnector, .originalConstructionChart, .originalAngularTransport, .originalPlaneDerivative, .originalGuideTraversalChain, .originalGuideEndpointConnector, .originalPolyline, .originalDrafted:
            return nil
        case .implicit:
            let prepared = try preparedCurve ?? PreparedCurveDifferentialEncloser(
                curve: curve, tolerance: tolerance, using: &execution)
            let jet = try prepared.thirdOrderIntervalJet(over: parameterRange, tolerance: tolerance, using: &execution)
            let magnitude = hypot(hypot(jet.x.secondDerivativeUU.absoluteUpperBound,
                                        jet.y.secondDerivativeUU.absoluteUpperBound).nextUp,
                                  jet.z.secondDerivativeUU.absoluteUpperBound).nextUp
            guard magnitude.isFinite else {
                throw resourceFailure(tolerance: tolerance,
                    message: "Implicit correspondence has no finite second-derivative bound.")
            }
            return magnitude
        case .analytic(.planeTorus), .certifiedIntersection:
            throw correspondenceFailure(
                tolerance: tolerance,
                message: "The exact 3D curve does not match a required structural curve-surface certificate."
            )
        }
    }

    // Piecewise continuous B-splines retain a first-derivative supremum
    // across C0 knots even though their second-order Taylor proof is unavailable.
    private func curveFirstDerivativeUpperBound(
        _ curve: Curve3D,
        parameterRange: ScalarInterval,
        tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution) throws -> Double? {
        try execution.consumeWork(1)
        switch curve {
        case let .surfaceLift(lift):
            return try SurfaceLiftDifferentialBounder().firstDerivativeMagnitude(
                lift: lift, interval: parameterRange, tolerance: tolerance, using: &execution)
        case let .bSpline(curve):
            guard try spatialBSplineIntervalHasNativeAuthority(curve, parameterRange: parameterRange, using: &execution) else { return nil }
            // Source validation rejects internal multiplicity greater than degree,
            // so these positive-weight pieces form a continuous native curve.
            let patches = try BSplineCurveBezierDecomposer().curvePatches(curve: curve, tolerance: tolerance, using: &execution)
            guard !patches.isEmpty else {
                throw correspondenceFailure(tolerance: tolerance,
                    message: "B-spline correspondence requires a non-empty first-derivative cover.")
            }
            var maximum = 0.0
            for patch in patches {
                try execution.consumeWork(1)
                try OriginalCoefficientAllocation.reserve(count: 3, of: [Double].self, using: &execution)
                try OriginalCoefficientAllocation.reserve(count: try exactScalarCount(patch.controlPoints.count, 3, multiply: true), of: Double.self, using: &execution)
                let bound = try RationalBezierCurveDerivativeBound(
                    coordinates: [patch.controlPoints.map({ $0.x }), patch.controlPoints.map({ $0.y }), patch.controlPoints.map({ $0.z })],
                    weights: patch.weights, parameterWidth: patch.upper - patch.lower, tolerance: tolerance, using: &execution)
                maximum = max(maximum, hypot(hypot(bound.first[0], bound.first[1]), bound.first[2]).nextUp)
            }
            return maximum
        case let .rigidImage(image):
            return try curveFirstDerivativeUpperBound(image.source, parameterRange: parameterRange, tolerance: tolerance, using: &execution)
        case let .affineImage(image):
            guard let source = try curveFirstDerivativeUpperBound(image.source,
                parameterRange: parameterRange, tolerance: tolerance, using: &execution) else { return nil }
            let bound = (source * image.transform.linearMagnitudeUpperBound).nextUp
            guard bound.isFinite else {
                throw resourceFailure(tolerance: tolerance,
                    message: "Affine-image correspondence first-derivative bound exceeded finite arithmetic.")
            }
            return bound
        default: return nil
        }
    }

    private func spatialBSplineIntervalHasNativeAuthority(_ curve: BSplineCurve3D,
        parameterRange: ScalarInterval, using execution: inout OriginalQueryExecution) throws -> Bool {
        try execution.consumeWork(1)
        // Validation precedes this call. Stored native knots, rather than a
        // selectable periodic representative origin, own this derivative cover.
        let lower = curve.knots[curve.degree]
        let upper = curve.knots[curve.controlPointCount]
        guard parameterRange.lower >= lower, parameterRange.upper <= upper else { return false }
        // FIXME(INCOMPLETE_IMPLEMENTATION): Correspondence's scalar native derivative
        // bounds do not own periodic seam or translated-cycle coverage. This production
        // validator may use them only after whole requested wrap intervals have proof.
        if curve.isPeriodic, parameterRange.lower <= lower || parameterRange.upper >= upper { return false }
        return true
    }

    private func firstDerivativeBoundsAreIntervalInvariant(
        for curve: Curve3D,
        parameterRange: ScalarInterval
    , using execution: inout OriginalQueryExecution) throws -> Bool {
        try execution.consumeWork(1)
        switch curve {
        case let .surfaceLift(lift):
            return SurfaceLiftDifferentialBounder()
                .derivativeMagnitudeBoundsAreIntervalInvariant(lift: lift)
        case let .bSpline(curve):
            return try spatialBSplineIntervalHasNativeAuthority(
                curve,
                parameterRange: parameterRange
            , using: &execution)
        case let .rigidImage(image):
            return try firstDerivativeBoundsAreIntervalInvariant(
                for: image.source,
                parameterRange: parameterRange
            , using: &execution)
        case let .affineImage(image):
            return try firstDerivativeBoundsAreIntervalInvariant(
                for: image.source,
                parameterRange: parameterRange
            , using: &execution)
        default:
            return false
        }
    }

    private func secondDerivativeBoundCanReuse(
        for curve: Curve3D,
        parameterRange: ScalarInterval
    , using execution: inout OriginalQueryExecution) throws -> Bool {
        try execution.consumeWork(1)
        switch curve {
        case let .bSpline(curve):
            return try spatialBSplineIntervalHasNativeAuthority(
                curve,
                parameterRange: parameterRange
            , using: &execution) && !spatialBSplineHasInteriorDerivativeJump(
                curve,
                parameterRange: parameterRange
            , using: &execution)
        case let .rigidImage(image):
            return try secondDerivativeBoundCanReuse(
                for: image.source,
                parameterRange: parameterRange
            , using: &execution)
        case let .affineImage(image):
            return try secondDerivativeBoundCanReuse(
                for: image.source,
                parameterRange: parameterRange
            , using: &execution)
        default:
            return false
        }
    }

    private func spatialBSplineHasInteriorDerivativeJump(_ curve: BSplineCurve3D,
        parameterRange: ScalarInterval, using execution: inout OriginalQueryExecution) throws -> Bool {
        try execution.consumeWork(1)
        var start = 0
        while start < curve.knots.count {
            var end = start + 1
            while end < curve.knots.count, curve.knots[end] == curve.knots[start] { end += 1 }
            if curve.knots[start] > parameterRange.lower, curve.knots[start] < parameterRange.upper,
               end - start >= curve.degree { return true }
            start = end
        }
        return false
    }

    private func isPlane(_ surface: Surface3D) -> Bool {
        DefaultPlanarSurfaceResolver().canonicalPlane(for: surface) != nil
    }

    private func upwardSum(_ lhs: Double, _ rhs: Double) -> Double {
        (lhs + rhs).nextUp
    }

    private func upwardProduct(_ lhs: Double, _ rhs: Double) -> Double {
        (lhs * rhs).nextUp
    }

    private func correspondenceFailure(
        residual: Double? = nil,
        tolerance: ModelingTolerance,
        message: String
    ) -> KernelError {
        KernelError(
            phase: .topology,
            code: .topologyFailure,
            residual: residual,
            tolerance: tolerance,
            message: message
        )
    }

    private func optionalBoundDescription(_ value: Double?) -> String {
#if hasFeature(Embedded)
        if let value { return "Optional(\(value))" }
        return "nil"
#else
        return String(describing: value)
#endif
    }

    private func resourceFailure(
        tolerance: ModelingTolerance,
        message: String
    ) -> KernelError {
        KernelError(
            phase: .topology,
            code: .resourceLimitExceeded,
            tolerance: tolerance,
            message: message
        )
    }

    private struct HomogeneousCoordinate {
        let x: Double
        let y: Double
        let z: Double
        let weight: Double

        var euclideanPoint: Point3D {
            Point3D(
                x: x / weight,
                y: y / weight,
                z: z / weight
            )
        }

        func adding(_ other: Self) -> Self {
            Self(
                x: x + other.x,
                y: y + other.y,
                z: z + other.z,
                weight: weight + other.weight
            )
        }

        func subtracting(_ other: Self) -> Self {
            Self(
                x: x - other.x,
                y: y - other.y,
                z: z - other.z,
                weight: weight - other.weight
            )
        }

        func scaled(by scale: Double) -> Self {
            Self(
                x: x * scale,
                y: y * scale,
                z: z * scale,
                weight: weight * scale
            )
        }

        func interpolated(to other: Self, parameter: Double) -> Self {
            scaled(by: 1.0 - parameter).adding(other.scaled(by: parameter))
        }
    }
}
