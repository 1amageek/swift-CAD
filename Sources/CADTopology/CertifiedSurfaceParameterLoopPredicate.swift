import HashTreeCollections
import CADCore
import CADGeometry
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#else
#error("A C math implementation is required.")
#endif

/// Certified planar predicates for one closed surface-parameter curve.
///
/// The exact curve remains the source of truth. Interval enclosures are
/// adaptively refined only where a query could meet the curve. A polygon is
/// used solely after every replacement chord has been proven to lie in a
/// convex enclosure that excludes the query point, so the replacement is a
/// homotopy in the punctured parameter plane and preserves winding.
package struct CertifiedSurfaceParameterLoopPredicate: Hashable, Sendable {
    private struct CurveBox: Hashable, Sendable {
        let curveIndex: Int
        let lowerFraction: Double
        let upperFraction: Double
        let u: ScalarInterval
        let v: ScalarInterval

        var maximumWidth: Double {
            max(u.width, v.width)
        }

        var fractionWidth: Double {
            upperFraction - lowerFraction
        }
    }

    private struct RangeWorkItem: Sendable {
        let curveIndex: Int
        let lowerFraction: Double
        let upperFraction: Double
        let depth: Int
    }

    private struct PairWorkItem: Sendable {
        let first: CurveBox
        let second: CurveBox
        let depth: Int
    }

    private let curves: OriginalParameterLoopCurveView
    private let hostingSurface: Surface3D?
    private let uShift: Double
    private let vShift: Double
    private let uPeriod: Double?
    private let vPeriod: Double?
    private let maximumDepth: Int
    private let maximumAlgebraicDepth: Int
    private let remainingSourceDepth: Int
    private let maximumWorkItemCount = 131_072

    package init(
        curve: SurfaceParameterCurve,
        uShift: Double = 0.0,
        vShift: Double = 0.0,
        uPeriod: Double? = nil,
        vPeriod: Double? = nil,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws {
        try execution.retainStorage(bytes: MemoryLayout<SurfaceParameterCurve>.stride)
        try self.init(
            curves: [curve],
            uShift: uShift,
            vShift: vShift,
            uPeriod: uPeriod,
            vPeriod: vPeriod,
            tolerance: tolerance, using: &execution
        )
    }

    package init(
        curves: [SurfaceParameterCurve],
        maximumAlgebraicDepth: Int = 32,
        uShift: Double = 0.0,
        vShift: Double = 0.0,
        uPeriod: Double? = nil,
        vPeriod: Double? = nil,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws {
        try tolerance.validate()
        guard (0...32).contains(maximumAlgebraicDepth), curves.isEmpty == false,
              uShift.isFinite,
              vShift.isFinite,
              uPeriod.map({ $0.isFinite && $0 > 0.0 }) ?? true,
              vPeriod.map({ $0.isFinite && $0 > 0.0 }) ?? true else {
            throw Self.failure(
                phase: .classification,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A certified surface-parameter loop requires finite chart shifts."
            )
        }
        for curve in curves {
            try execution.consumeWork(1)
            let start = try curve.startParameter(tolerance: tolerance, using: &execution)
            let end = try curve.endParameter(tolerance: tolerance, using: &execution)
            guard start.u.isFinite,
                  start.v.isFinite,
                  end.u.isFinite,
                  end.v.isFinite else {
                throw Self.failure(
                    phase: .classification,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "A certified planar pcurve predicate requires finite curve endpoints."
                )
            }
        }
        self.maximumDepth = 48
        self.remainingSourceDepth = 16
        self.maximumAlgebraicDepth = maximumAlgebraicDepth
        self.curves = OriginalParameterLoopCurveView(curves: curves)
        self.hostingSurface = nil
        self.uShift = uShift
        self.vShift = vShift
        self.uPeriod = uPeriod
        self.vPeriod = vPeriod
    }

    private static func standaloneExecution() throws -> OriginalQueryExecution {
        OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32,
                remainingSourceDepth: 16, maximumSubdivisionDepth: 48))
    }

    package init(curve: SurfaceParameterCurve, uShift: Double = 0, vShift: Double = 0,
        uPeriod: Double? = nil, vPeriod: Double? = nil, tolerance: ModelingTolerance) throws {
        var execution = try Self.standaloneExecution()
        try self.init(curve: curve, uShift: uShift, vShift: vShift, uPeriod: uPeriod,
            vPeriod: vPeriod, tolerance: tolerance, using: &execution)
    }

    package init(curves: [SurfaceParameterCurve], maximumAlgebraicDepth: Int = 32,
        uShift: Double = 0, vShift: Double = 0, uPeriod: Double? = nil, vPeriod: Double? = nil,
        tolerance: ModelingTolerance) throws {
        var execution = try Self.standaloneExecution()
        try self.init(curves: curves, maximumAlgebraicDepth: maximumAlgebraicDepth,
            uShift: uShift, vShift: vShift, uPeriod: uPeriod, vPeriod: vPeriod,
            tolerance: tolerance, using: &execution)
    }

    /// Prepares original endpoint/chart authority under one caller ledger.
    package init(curves: [SurfaceParameterCurve], on surface: Surface3D,
        uShift: Double = 0, vShift: Double = 0, uPeriod: Double? = nil, vPeriod: Double? = nil,
        tolerance: ModelingTolerance, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        maximumAlgebraicDepth: Int = 32, using execution: inout OriginalQueryExecution) throws {
        try tolerance.validate(); try execution.checkpoint(); try execution.consumeWork(1)
        guard (0...32).contains(maximumAlgebraicDepth), !curves.isEmpty, maximumSubdivisionDepth >= 0, remainingSourceDepth > 0,
            uShift.isFinite, vShift.isFinite,
            uPeriod.map({ $0.isFinite && $0 > 0 }) ?? true,
            vPeriod.map({ $0.isFinite && $0 > 0 }) ?? true else {
            throw Self.failure(phase: .classification, code: .invalidInput, tolerance: tolerance,
                message: "Original chart predicate requires finite policy and caller source depths.")
        }
        for curve in curves {
            try execution.checkpoint(); try execution.consumeWork(1)
            let lift = try curve.continuousChartLift(on: surface, tolerance: tolerance,
                maximumSpanCount: 131_072, maximumSubdivisionDepth: maximumSubdivisionDepth,
                remainingSourceDepth: remainingSourceDepth, maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
            guard let boxes = lift.originalSampleBounds, boxes.count == 3,
                boxes.allSatisfy({ $0.u.lower.isFinite && $0.u.upper.isFinite &&
                    $0.v.lower.isFinite && $0.v.upper.isFinite }) else {
                throw Self.failure(phase: .classification, code: .classificationFailure, tolerance: tolerance,
                    message: "Original chart predicate has no complete finite endpoint boxes.")
            }
        }
        self.curves = OriginalParameterLoopCurveView(curves: curves)
        self.hostingSurface = surface
        self.uShift = uShift; self.vShift = vShift; self.uPeriod = uPeriod; self.vPeriod = vPeriod
        self.maximumDepth = min(48, maximumSubdivisionDepth)
        self.remainingSourceDepth = min(16, remainingSourceDepth)
        self.maximumAlgebraicDepth = maximumAlgebraicDepth
    }

    /// Reuses only unchanged pcurves reached through one immutable exact source.
    package init(loopID: LoopID, validatedModel: ValidatedBRepModel,
        uShift: Double = 0,vShift: Double = 0,uPeriod: Double? = nil,vPeriod: Double? = nil,
        maximumSubdivisionDepth: Int, maximumAlgebraicDepth: Int = 32, remainingSourceDepth: Int = 16, using execution: inout OriginalQueryExecution) throws {
        try execution.checkpoint(); try execution.consumeWork(1)
        let tolerance = validatedModel.tolerance
        try tolerance.validate()
        guard remainingSourceDepth >= 0, (0...32).contains(maximumAlgebraicDepth), validatedModel.validationLevel != .modeling,maximumSubdivisionDepth >= 0,
            uShift.isFinite,vShift.isFinite,uPeriod.map({ $0.isFinite && $0 > 0 }) ?? true,
            vPeriod.map({ $0.isFinite && $0 > 0 }) ?? true,
            let loop = validatedModel.model.loops[loopID],!loop.coedges.isEmpty else {
            throw Self.failure(phase: .classification,code: .invalidInput,tolerance: tolerance,
                message: "Original loop preparation requires its immutable exact source and finite chart policy.")
        }
        self.curves = try OriginalParameterLoopCurveView(validatedLoop: loop, using: &execution)
        self.hostingSurface = nil
        self.uShift = uShift; self.vShift = vShift
        self.uPeriod = uPeriod; self.vPeriod = vPeriod
        self.maximumDepth = min(48,maximumSubdivisionDepth)
        self.remainingSourceDepth = min(16, remainingSourceDepth)
        self.maximumAlgebraicDepth = maximumAlgebraicDepth
    }

    package enum WindingClassification: Hashable, Sendable {
        case boundary
        case winding(Int)
    }

    package func signedWinding(_ point: Point2D, tolerance: ModelingTolerance, maximumSubdivisionDepth: Int = 48) throws -> WindingClassification {
        var execution = try Self.standaloneExecution()
        return try signedWinding(point, tolerance: tolerance, maximumSubdivisionDepth: maximumSubdivisionDepth, using: &execution)
    }

    package func classifyStrictlyOriginal(_ point: Point2D, tolerance: ModelingTolerance, maximumSubdivisionDepth: Int = 48) throws -> PlanarPointClassification? {
        var execution = try Self.standaloneExecution()
        return try classifyStrictlyOriginal(point, tolerance: tolerance, maximumSubdivisionDepth: maximumSubdivisionDepth, using: &execution)
    }

    package func classify(_ point: Point2D, tolerance: ModelingTolerance, maximumSubdivisionDepth: Int = 48) throws -> PlanarPointClassification {
        var execution = try Self.standaloneExecution()
        return try classify(point, tolerance: tolerance, maximumSubdivisionDepth: maximumSubdivisionDepth, using: &execution)
    }

    package func containsStrictly(_ point: Point2D, tolerance: ModelingTolerance) throws -> Bool {
        var execution = try Self.standaloneExecution()
        return try containsStrictly(point, tolerance: tolerance, using: &execution)
    }

    package func boundaryIntersectsOrTouches(_ other: CertifiedSurfaceParameterLoopPredicate, otherUShift: Double = 0, otherVShift: Double = 0, tolerance: ModelingTolerance, maximumSubdivisionDepth: Int = 48) throws -> Bool {
        var execution = try Self.standaloneExecution()
        return try boundaryIntersectsOrTouches(other, otherUShift: otherUShift, otherVShift: otherVShift, tolerance: tolerance, maximumSubdivisionDepth: maximumSubdivisionDepth, using: &execution)
    }

    /// Signed winding of the original directed loop, preserved by certified homotopy.
    package func signedWinding(
        _ point: Point2D,
        tolerance: ModelingTolerance,
        maximumSubdivisionDepth: Int = 48, using execution: inout OriginalQueryExecution) throws -> WindingClassification {
        try execution.checkpoint()
        try execution.consumeWork(1)
        try tolerance.validate()
        guard maximumSubdivisionDepth >= 0, point.x.isFinite, point.y.isFinite else {
            throw Self.failure(phase: .classification, code: .invalidInput,
                tolerance: tolerance, message: "Signed original winding requires a finite query and nonnegative depth.")
        }
        return try winding(point, clearance: Self.parameterTolerance(from: tolerance).distance,
            tolerance: tolerance,
            maximumSubdivisionDepth: maximumSubdivisionDepth, using: &execution)
    }

    /// Returns nil when exact authored endpoint closure has no source proof.
    package func classifyStrictlyOriginal(_ point: Point2D, tolerance: ModelingTolerance,
        maximumSubdivisionDepth: Int = 48, using execution: inout OriginalQueryExecution) throws -> PlanarPointClassification? {
        try tolerance.validate(); try execution.checkpoint(); try execution.consumeWork(1)
        guard maximumSubdivisionDepth >= 0, point.x.isFinite, point.y.isFinite else {
            throw Self.failure(phase: .classification, code: .invalidInput, tolerance: tolerance,
                message: "Strict original winding requires a finite query and nonnegative depth.")
        }
        guard uPeriod == nil, vPeriod == nil,
            try exactAuthoredClosure(using: &execution) else { return nil }
        switch try winding(point, clearance: 0, tolerance: tolerance,
            maximumSubdivisionDepth: maximumSubdivisionDepth, unresolvedIsBoundary: true, using: &execution) {
        case .boundary: return .indeterminate
        case .winding(let count): return count % 2 == 0 ? .outside : .inside
        }
    }

    private func winding(_ point: Point2D, clearance: Double, tolerance: ModelingTolerance,
        maximumSubdivisionDepth: Int, unresolvedIsBoundary: Bool = false, using execution: inout OriginalQueryExecution) throws -> WindingClassification {
        guard let boxes = try boxesExcluding(point, clearance: clearance,
            tolerance: tolerance,
            maximumSubdivisionDepth: min(maximumDepth, maximumSubdivisionDepth),
            unresolvedIsBoundary: unresolvedIsBoundary, using: &execution) else {
            return .boundary
        }
        guard boxes.count >= 3 else { return .winding(0) }
        for _ in boxes { try execution.checkpoint(); try execution.consumeWork(1) }
        let polygon = try homotopyPolygon(boxes, tolerance: tolerance, clearance: clearance, using: &execution)
        var winding = 0
        for index in polygon.indices {
            try execution.checkpoint()
            try execution.consumeWork(1)
            let start = polygon[index], end = polygon[(index + 1) % polygon.count]
            let upward = start.y <= point.y && end.y > point.y
            let downward = start.y > point.y && end.y <= point.y
            guard upward || downward else { continue }
            let orientation = try RobustPredicates.orientation2D(start, end,
                relativeTo: point, determinantTolerance: 0, using: &execution)
            guard orientation != .indeterminate else {
                throw Self.failure(phase: .classification, code: .classificationFailure,
                    tolerance: tolerance, message: "Original winding could not resolve a directed homotopy crossing.")
            }
            // A query on an artificial chord would contradict its complete original
            // exclusion corridor; it cannot be published as an original boundary.
            guard orientation != .zero else {
                throw Self.failure(phase: .classification, code: .classificationFailure,
                    tolerance: tolerance, message: "Original winding homotopy chord intersects the excluded query.")
            }
            let increment = upward && orientation == .positive ? 1
                : (downward && orientation == .negative ? -1 : 0)
            let sum = winding.addingReportingOverflow(increment)
            guard !sum.overflow else {
                throw Self.failure(phase: .classification, code: .resourceLimitExceeded,
                    tolerance: tolerance, message: "Original signed winding exceeds integer storage.")
            }
            winding = sum.partialValue
        }
        return .winding(winding)
    }

    private func exactAuthoredClosure(using execution: inout OriginalQueryExecution) throws -> Bool {
        func endpoints(_ curve: SurfaceParameterCurve, depth: Int = 0) throws
            -> (SurfaceParameter, SurfaceParameter)? {
            try execution.checkpoint(); try execution.consumeWork(1)
            guard depth < remainingSourceDepth else { return nil }
            switch curve {
            case .constantU(let u, let start, let end):
                return (SurfaceParameter(u: u, v: start), SurfaceParameter(u: u, v: end))
            case .constantV(let v, let start, let end):
                return (SurfaceParameter(u: start, v: v), SurfaceParameter(u: end, v: v))
            case .polyline(let points):
                guard let first = points.first, let last = points.last else { return nil }
                return (first, last)
            case .bSpline(let spline):
                guard spline.degree >= 1, spline.controlPoints.count > spline.degree,
                    spline.knots.count == spline.controlPoints.count + spline.degree + 1,
                    spline.weights.count == spline.controlPoints.count,
                    case .closed(let lower, let upper) = spline.domain, lower < upper,
                    let first = spline.controlPoints.first, let last = spline.controlPoints.last else { return nil }
                for knot in spline.knots.prefix(spline.degree + 1) {
                    try execution.consumeWork(1); guard knot == lower else { return nil }
                }
                for knot in spline.knots.suffix(spline.degree + 1) {
                    try execution.consumeWork(1); guard knot == upper else { return nil }
                }
                for weight in spline.weights {
                    try execution.consumeWork(1); guard weight.isFinite, weight > 0 else { return nil }
                }
                return (SurfaceParameter(u: first.x, v: first.y), SurfaceParameter(u: last.x, v: last.y))
            case .originalAffineWord(let image):
                guard let values = try endpoints(image.source.parameterCurve, depth: depth + 1) else { return nil }
                if image.startFraction == 0, image.endFraction == 1 { return values }
                if image.startFraction == 1, image.endFraction == 0 { return (values.1, values.0) }
                return nil
            case .periodicTranslation(let source, let u, let v):
                guard u == 0, v == 0 else { return nil }
                return try endpoints(source, depth: depth + 1)
            default:
                // FIXME(INCOMPLETE_IMPLEMENTATION): Strict distance trim admission
                // needs original endpoint-relation receipts for other chart families.
                // A numeric endpoint or overlapping interval cannot prove exact closure.
                return nil
            }
        }
        var first: SurfaceParameter?, previous: SurfaceParameter?
        for curve in curves {
            try execution.consumeWork(1)
            guard let pair = try endpoints(curve), pair.0.u.isFinite, pair.0.v.isFinite,
                pair.1.u.isFinite, pair.1.v.isFinite else { return false }
            if let previous, previous != pair.0 { return false }
            if first == nil { first = pair.0 }
            previous = pair.1
        }
        return first != nil && first == previous
    }

    package func containsStrictly(
        _ point: Point2D,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> Bool {
        try classify(point, tolerance: tolerance, using: &execution) == .inside
    }

    package func classify(
        _ point: Point2D,
        tolerance: ModelingTolerance,
        maximumSubdivisionDepth: Int = 48, using execution: inout OriginalQueryExecution) throws -> PlanarPointClassification {
        try execution.consumeWork(1)
        try tolerance.validate()
        guard maximumSubdivisionDepth >= 0 else {
            throw Self.failure(phase: .classification, code: .invalidInput,
                tolerance: tolerance, message: "Loop containment requires a nonnegative proof depth.")
        }
        guard point.x.isFinite, point.y.isFinite else {
            throw Self.failure(
                phase: .classification,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Certified pcurve containment requires a finite query point."
            )
        }
        let parameterTolerance = Self.parameterTolerance(from: tolerance)
        guard let boxes = try boxesExcluding(
            point,
            clearance: parameterTolerance.distance,
            tolerance: tolerance,
            maximumSubdivisionDepth: min(maximumDepth, maximumSubdivisionDepth), using: &execution) else {
            return .boundary
        }
        guard boxes.count >= 3 else {
            // A complete closed curve enclosed by fewer than three convex
            // boxes, all excluding the query, has zero winding around it.
            return .outside
        }
        for _ in boxes { try execution.consumeWork(1) }
        let polygon = try homotopyPolygon(boxes, tolerance: tolerance, using: &execution)
        switch try AdaptivePlanarPredicateEvaluator().classify(
            point,
            in: polygon,
            tolerance: parameterTolerance, using: &execution
        ) {
        case .inside:
            return .inside
        case .outside:
            return .outside
        case .boundary:
            return .boundary
        case .indeterminate:
            throw Self.failure(
                phase: .classification,
                code: .classificationFailure,
                tolerance: tolerance,
                message: "Certified pcurve containment produced an indeterminate homotopy polygon."
            )
        }
    }

    package func boundaryIntersectsOrTouches(
        _ other: CertifiedSurfaceParameterLoopPredicate,
        otherUShift: Double = 0.0,
        otherVShift: Double = 0.0,
        tolerance: ModelingTolerance,
        maximumSubdivisionDepth: Int = 48, using execution: inout OriginalQueryExecution) throws -> Bool {
        try tolerance.validate(); try execution.checkpoint(); try execution.consumeWork(1)
        guard maximumSubdivisionDepth >= 0 else {
            throw Self.failure(phase: .classification, code: .invalidInput, tolerance: tolerance,
                message: "Original boundary comparison requires a nonnegative caller depth.")
        }
        let depthLimit = min(maximumDepth, other.maximumDepth, maximumSubdivisionDepth)
        guard otherUShift.isFinite, otherVShift.isFinite else {
            throw Self.failure(
                phase: .classification,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Certified pcurve boundary comparison requires finite chart shifts."
            )
        }
        let clearance = Self.parameterTolerance(from: tolerance).distance
        let firstBoxes = try initialBoxes(tolerance: tolerance, maximumSubdivisionDepth: depthLimit, using: &execution)
        let secondBoxes = try other.initialBoxes(
            additionalUShift: otherUShift,
            additionalVShift: otherVShift,
            tolerance: tolerance,
            maximumSubdivisionDepth: depthLimit, using: &execution)
        var pending: [PairWorkItem] = []
        for first in firstBoxes {
            try execution.consumeWork(1)
            for second in secondBoxes {
                try execution.checkpoint(); try execution.consumeWork(1)
                guard Self.intersects(first, second, clearance: clearance) else { continue }
                try OriginalParameterQueryStorage.append(PairWorkItem(first: first, second: second, depth: 0),
                    to: &pending, using: &execution)
            }
        }
        var processedCount = 0
        while let item = pending.popLast() {
            try execution.checkpoint(); try execution.visitGeometricCell(depth: item.depth)
            processedCount += 1
            guard processedCount <= maximumWorkItemCount else {
                throw Self.failure(
                    phase: .classification,
                    code: .resourceLimitExceeded,
                    residual: Double(processedCount),
                    tolerance: tolerance,
                    message: "Certified pcurve boundary comparison exceeded its adaptive work budget."
                )
            }
            guard Self.intersects(item.first, item.second, clearance: clearance) else {
                continue
            }
            if item.first.maximumWidth <= clearance,
               item.second.maximumWidth <= clearance {
                return true
            }
            guard item.depth < depthLimit else {
                throw Self.failure(
                    phase: .classification,
                    code: .resourceLimitExceeded,
                    residual: max(item.first.maximumWidth, item.second.maximumWidth),
                    tolerance: tolerance,
                    message: "Certified pcurve boundary comparison reached its subdivision depth before separation."
                )
            }
            let splitFirst = item.first.maximumWidth >= item.second.maximumWidth
            let selected = splitFirst ? item.first : item.second
            guard selected.fractionWidth > tolerance.relative * 4.0 else {
                throw Self.failure(
                    phase: .classification,
                    code: .classificationFailure,
                    residual: selected.maximumWidth,
                    tolerance: tolerance,
                    message: "Certified pcurve boundary comparison reached parameter resolution before separation."
                )
            }
            let middle = selected.lowerFraction
                + selected.fractionWidth * 0.5
            let lower = RangeWorkItem(
                curveIndex: selected.curveIndex,
                lowerFraction: selected.lowerFraction,
                upperFraction: middle,
                depth: item.depth + 1
            )
            let upper = RangeWorkItem(
                curveIndex: selected.curveIndex,
                lowerFraction: middle,
                upperFraction: selected.upperFraction,
                depth: item.depth + 1
            )
            func enqueue(_ range: RangeWorkItem, _ pending: inout [PairWorkItem]) throws {
                let refined: [CurveBox]
                if splitFirst {
                    refined = try boxes(for: range, tolerance: tolerance,
                        maximumSubdivisionDepth: depthLimit, using: &execution)
                } else {
                    refined = try other.boxes(for: range, additionalUShift: otherUShift,
                        additionalVShift: otherVShift, tolerance: tolerance,
                        maximumSubdivisionDepth: depthLimit, using: &execution)
                }
                for box in refined {
            try execution.consumeWork(1)
                    try execution.visitGeometricCell(depth: item.depth + 1)
                    let pair = splitFirst
                        ? PairWorkItem(first: box, second: item.second, depth: item.depth + 1)
                        : PairWorkItem(first: item.first, second: box, depth: item.depth + 1)
                    if Self.intersects(pair.first, pair.second, clearance: clearance) {
                        try OriginalParameterQueryStorage.append(pair, to: &pending, using: &execution)
                    }
                }
            }
            try enqueue(lower, &pending)
            try enqueue(upper, &pending)
        }
        return false
    }

    private func boxesExcluding(
        _ point: Point2D,
        clearance: Double,
        tolerance: ModelingTolerance,
        maximumSubdivisionDepth: Int = 48,
        unresolvedIsBoundary: Bool = false, using execution: inout OriginalQueryExecution) throws -> [CurveBox]? {
        var pending: [RangeWorkItem] = []
        try OriginalParameterQueryStorage.reserve(curves.count, in: &pending, using: &execution)
        for index in curves.indices {
            try execution.checkpoint(); try execution.consumeWork(1)
            pending.append(RangeWorkItem(curveIndex: index, lowerFraction: 0, upperFraction: 1, depth: 0))
        }
        var accepted: [CurveBox] = []
        var processedCount = 0
        while let item = pending.popLast() {
            try execution.visitGeometricCell(depth: item.depth)
            let candidates = try boxes(for: item, tolerance: tolerance, maximumSubdivisionDepth: maximumSubdivisionDepth, using: &execution)
            for candidate in candidates {
            try execution.consumeWork(1)
                processedCount += 1
                guard processedCount <= maximumWorkItemCount else {
                    throw Self.failure(
                        phase: .classification,
                        code: .resourceLimitExceeded,
                        residual: Double(processedCount),
                        tolerance: tolerance,
                        message: "Certified pcurve containment exceeded its adaptive work budget."
                    )
                }
                guard Self.contains(
                    candidate,
                    point: point,
                    clearance: clearance
                ) else {
                    try OriginalParameterQueryStorage.append(candidate, to: &accepted, using: &execution)
                    continue
                }
                if candidate.maximumWidth <= clearance {
                    return nil
                }
                guard item.depth < maximumSubdivisionDepth,
                      candidate.fractionWidth > tolerance.relative * 4.0 else {
                    if unresolvedIsBoundary { return nil }
                    throw Self.failure(
                        phase: .classification,
                        code: .classificationFailure,
                        residual: candidate.maximumWidth,
                        tolerance: tolerance,
                        message: "Certified pcurve containment reached numeric resolution at the query boundary."
                    )
                }
                let middle = candidate.lowerFraction
                    + candidate.fractionWidth * 0.5
                try OriginalParameterQueryStorage.append(RangeWorkItem(
                    curveIndex: candidate.curveIndex,
                    lowerFraction: middle,
                    upperFraction: candidate.upperFraction,
                    depth: item.depth + 1
                ), to: &pending, using: &execution)
                try OriginalParameterQueryStorage.append(RangeWorkItem(
                    curveIndex: candidate.curveIndex,
                    lowerFraction: candidate.lowerFraction,
                    upperFraction: middle,
                    depth: item.depth + 1
                ), to: &pending, using: &execution)
            }
        }
        return try aligned(accepted, start: try chartReference(curveIndex: 0, fraction: 0, tolerance: tolerance, using: &execution),
            additionalUShift: 0, additionalVShift: 0, using: &execution)
    }

    private func homotopyPolygon(
        _ boxes: [CurveBox],
        tolerance: ModelingTolerance,
        clearance requestedClearance: Double? = nil, using execution: inout OriginalQueryExecution) throws -> [Point2D] {
        let clearance = requestedClearance ?? Self.parameterTolerance(from: tolerance).distance
        var result: [Point2D] = []
        try OriginalParameterQueryStorage.reserve(boxes.count, in: &result, using: &execution)
        for index in boxes.indices {
            try execution.checkpoint(); try execution.consumeWork(1)
            let current = boxes[index]
            let next = boxes[(index + 1) % boxes.count]
            // The strict route uses actual box intersections after exact endpoint
            // closure. The historical route uses the same expanded corridor that
            // excluded the query. In either route every chosen polygon vertex
            // stays in the certified convex intersection; it is not a source
            // boundary point or a replacement geometry authority.
            let lowerU = max(
                current.u.lower - clearance,
                next.u.lower - clearance
            )
            let upperU = min(
                current.u.upper + clearance,
                next.u.upper + clearance
            )
            let lowerV = max(
                current.v.lower - clearance,
                next.v.lower - clearance
            )
            let upperV = min(
                current.v.upper + clearance,
                next.v.upper + clearance
            )
            guard lowerU <= upperU, lowerV <= upperV else {
                throw Self.failure(
                    phase: .classification,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "Consecutive certified pcurve enclosures \(index) (curve \(current.curveIndex), fraction \(current.upperFraction)) and \((index + 1) % boxes.count) (curve \(next.curveIndex), fraction \(next.lowerFraction)) do not share their exact endpoint: first u=[\(current.u.lower), \(current.u.upper)] v=[\(current.v.lower), \(current.v.upper)], second u=[\(next.u.lower), \(next.u.upper)] v=[\(next.v.lower), \(next.v.upper)]."
                )
            }
            result.append(Point2D(
                x: min(upperU, max(lowerU, lowerU * 0.5 + upperU * 0.5)),
                y: min(upperV, max(lowerV, lowerV * 0.5 + upperV * 0.5))
            ))
        }
        return result
    }

    private func boxes(
        for item: RangeWorkItem,
        additionalUShift: Double = 0.0,
        additionalVShift: Double = 0.0,
        tolerance: ModelingTolerance,
        maximumSubdivisionDepth: Int = 48, using execution: inout OriginalQueryExecution) throws -> [CurveBox] {
        let curve = curves[item.curveIndex]
        let enclosures = try execution.withGeometricDepthOffset(item.depth) { execution in
            try CertifiedSurfaceParameterCurveEncloser(
            maximumSubdivisionDepth: maximumSubdivisionDepth - item.depth,
            maximumAlgebraicDepth: maximumAlgebraicDepth, remainingSourceDepth: remainingSourceDepth).enclosures(
            for: curve,
            on: hostingSurface,
            fromNormalizedFraction: item.lowerFraction,
            toNormalizedFraction: item.upperFraction,
            maximumWidth: Double.greatestFiniteMagnitude.squareRoot(),
            tolerance: tolerance, using: &execution
        )
        }
        var mapped: [CurveBox] = []
        try OriginalParameterQueryStorage.reserve(enclosures.count, in: &mapped, using: &execution)
        for enclosure in enclosures {
            try execution.checkpoint(); try execution.visitGeometricCell(depth: item.depth)
            mapped.append(CurveBox(
                curveIndex: item.curveIndex,
                lowerFraction: enclosure.lowerFraction,
                upperFraction: enclosure.upperFraction,
                u: try ScalarInterval(
                    lower: (enclosure.u.lower + uShift + additionalUShift).nextDown,
                    upper: (enclosure.u.upper + uShift + additionalUShift).nextUp
                ),
                v: try ScalarInterval(
                    lower: (enclosure.v.lower + vShift + additionalVShift).nextDown,
                    upper: (enclosure.v.upper + vShift + additionalVShift).nextUp
                )
            ))
        }
        return try aligned(
            mapped,
            start: try chartReference(curveIndex: item.curveIndex, fraction: item.lowerFraction, tolerance: tolerance, using: &execution),
            additionalUShift: additionalUShift,
            additionalVShift: additionalVShift, using: &execution)
    }

    private func aligned(
        _ boxes: [CurveBox],
        start: SurfaceParameter,
        additionalUShift: Double,
        additionalVShift: Double, using execution: inout OriginalQueryExecution) throws -> [CurveBox] {
        var referenceU = start.u + uShift + additionalUShift
        var referenceV = start.v + vShift + additionalVShift
        var result: [CurveBox] = []
        let ordered = try orderedBoxes(boxes, using: &execution)
        try OriginalParameterQueryStorage.reserve(ordered.count, in: &result, using: &execution)
        for box in ordered {
            try execution.checkpoint(); try execution.consumeWork(1)
            let boxUShift = Self.periodicShift(
                box.u.midpoint,
                nearest: referenceU,
                period: uPeriod
            )
            let boxVShift = Self.periodicShift(
                box.v.midpoint,
                nearest: referenceV,
                period: vPeriod
            )
            let aligned = CurveBox(
                curveIndex: box.curveIndex,
                lowerFraction: box.lowerFraction,
                upperFraction: box.upperFraction,
                u: try ScalarInterval(
                    lower: (box.u.lower + boxUShift).nextDown,
                    upper: (box.u.upper + boxUShift).nextUp
                ),
                v: try ScalarInterval(
                    lower: (box.v.lower + boxVShift).nextDown,
                    upper: (box.v.upper + boxVShift).nextUp
                )
            )
            result.append(aligned)
            referenceU = aligned.u.midpoint
            referenceV = aligned.v.midpoint
        }
        return result
    }

    private func chartReference(curveIndex: Int, fraction: Double,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> SurfaceParameter {
        // Neither coordinate uses a reference without a periodic shift law.
        if uPeriod == nil, vPeriod == nil { return SurfaceParameter(u: 0, v: 0) }
        // FIXME(INCOMPLETE_IMPLEMENTATION): Periodic winding/boundary queries
        // still reach the legacy source parameter reference here. Complete
        // bounded chart admission requires the original endpoint/period receipt
        // and its caller work/byte ports; a numeric branch proposal alone is not
        // that receipt. Nonperiodic queries bypass this evaluation entirely.
        return try curves[curveIndex].parameter(atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
    }

    private func orderedBoxes(_ boxes: [CurveBox], using execution: inout OriginalQueryExecution) throws -> [CurveBox] {
        var result: [CurveBox] = []
        try OriginalParameterQueryStorage.reserve(boxes.count, in: &result, using: &execution)
        for box in boxes { try execution.consumeWork(1); result.append(box) }
        try OriginalParameterQueryStorage.sort(&result, using: &execution) { a, b in
            if a.curveIndex != b.curveIndex { return a.curveIndex < b.curveIndex }
            if a.lowerFraction != b.lowerFraction { return a.lowerFraction < b.lowerFraction }
            return a.upperFraction < b.upperFraction
        }
        return result
    }

    private static func periodicShift(
        _ value: Double,
        nearest reference: Double,
        period: Double?
    ) -> Double {
        guard let period else { return 0.0 }
        return round((reference - value) / period) * period
    }

    private func initialBoxes(
        additionalUShift: Double = 0, additionalVShift: Double = 0,
        tolerance: ModelingTolerance,
        maximumSubdivisionDepth: Int = 48, using execution: inout OriginalQueryExecution) throws -> [CurveBox] {
        var result: [CurveBox] = []
        for curveIndex in curves.indices {
            try execution.checkpoint(); try execution.consumeWork(1)
            let originalBoxes = try boxes(for: RangeWorkItem(curveIndex: curveIndex,
                lowerFraction: 0, upperFraction: 1, depth: 0),
                additionalUShift: additionalUShift, additionalVShift: additionalVShift,
                tolerance: tolerance,
                maximumSubdivisionDepth: maximumSubdivisionDepth, using: &execution)
            for box in originalBoxes {
                try execution.consumeWork(1)
                try OriginalParameterQueryStorage.append(box, to: &result, using: &execution)
            }
        }
        return result
    }

    private static func contains(
        _ box: CurveBox,
        point: Point2D,
        clearance: Double
    ) -> Bool {
        point.x >= box.u.lower - clearance
            && point.x <= box.u.upper + clearance
            && point.y >= box.v.lower - clearance
            && point.y <= box.v.upper + clearance
    }

    private static func intersects(
        _ first: CurveBox,
        _ second: CurveBox,
        clearance: Double
    ) -> Bool {
        first.u.lower - clearance <= second.u.upper
            && second.u.lower - clearance <= first.u.upper
            && first.v.lower - clearance <= second.v.upper
            && second.v.lower - clearance <= first.v.upper
    }

    private static func parameterTolerance(
        from tolerance: ModelingTolerance
    ) -> ModelingTolerance {
        ModelingTolerance(
            distance: max(tolerance.distance, tolerance.angle),
            angle: tolerance.angle,
            relative: tolerance.relative
        )
    }

    private static func failure(
        phase: KernelPhase,
        code: KernelErrorCode,
        residual: Double? = nil,
        tolerance: ModelingTolerance,
        message: String
    ) -> KernelError {
        KernelError(
            phase: phase,
            code: code,
            residual: residual,
            tolerance: tolerance,
            message: message
        )
    }
}
