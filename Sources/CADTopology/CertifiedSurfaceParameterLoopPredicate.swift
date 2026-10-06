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
        tolerance: ModelingTolerance
    ) throws {
        try self.init(
            curves: [curve],
            uShift: uShift,
            vShift: vShift,
            uPeriod: uPeriod,
            vPeriod: vPeriod,
            tolerance: tolerance
        )
    }

    package init(
        curves: [SurfaceParameterCurve],
        maximumAlgebraicDepth: Int = 32,
        uShift: Double = 0.0,
        vShift: Double = 0.0,
        uPeriod: Double? = nil,
        vPeriod: Double? = nil,
        tolerance: ModelingTolerance
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
            let start = try curve.startParameter(tolerance: tolerance)
            let end = try curve.endParameter(tolerance: tolerance)
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

    /// Prepares original endpoint/chart authority under one caller ledger.
    package init(curves: [SurfaceParameterCurve], on surface: Surface3D,
        uShift: Double = 0, vShift: Double = 0, uPeriod: Double? = nil, vPeriod: Double? = nil,
        tolerance: ModelingTolerance, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        maximumAlgebraicDepth: Int = 32,
        consumeWork: @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)? = nil) throws {
        try tolerance.validate(); try Task.checkCancellation(); try consumeWork(0)
        guard (0...32).contains(maximumAlgebraicDepth), !curves.isEmpty, maximumSubdivisionDepth >= 0, remainingSourceDepth > 0,
            uShift.isFinite, vShift.isFinite,
            uPeriod.map({ $0.isFinite && $0 > 0 }) ?? true,
            vPeriod.map({ $0.isFinite && $0 > 0 }) ?? true else {
            throw Self.failure(phase: .classification, code: .invalidInput, tolerance: tolerance,
                message: "Original chart predicate requires finite policy and caller source depths.")
        }
        for curve in curves {
            try Task.checkCancellation(); try consumeWork(0)
            let lift = try curve.continuousChartLift(on: surface, tolerance: tolerance,
                maximumSpanCount: 131_072, maximumSubdivisionDepth: maximumSubdivisionDepth,
                remainingSourceDepth: remainingSourceDepth, consumeWork: { try consumeWork(0) },
                consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth)
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
        maximumSubdivisionDepth: Int, maximumAlgebraicDepth: Int = 32, remainingSourceDepth: Int = 16,
        consumeWork: @Sendable (Int) throws -> Void) throws {
        try Task.checkCancellation(); try consumeWork(0)
        let tolerance = validatedModel.tolerance
        try tolerance.validate()
        guard remainingSourceDepth >= 0, (0...32).contains(maximumAlgebraicDepth), validatedModel.validationLevel != .modeling,maximumSubdivisionDepth >= 0,
            uShift.isFinite,vShift.isFinite,uPeriod.map({ $0.isFinite && $0 > 0 }) ?? true,
            vPeriod.map({ $0.isFinite && $0 > 0 }) ?? true,
            let loop = validatedModel.model.loops[loopID],!loop.coedges.isEmpty else {
            throw Self.failure(phase: .classification,code: .invalidInput,tolerance: tolerance,
                message: "Original loop preparation requires its immutable exact source and finite chart policy.")
        }
        self.curves = try OriginalParameterLoopCurveView(validatedLoop: loop,consumeWork: consumeWork)
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

    /// Signed winding of the original directed loop, preserved by certified homotopy.
    package func signedWinding(
        _ point: Point2D,
        tolerance: ModelingTolerance,
        consumeWork: (@Sendable (Int) throws -> Void)? = nil,
        consumeStorage: (@Sendable (Int) throws -> Void)? = nil,
        maximumSubdivisionDepth: Int = 48
    ) throws -> WindingClassification {
        try Task.checkCancellation()
        try consumeWork?(0)
        try tolerance.validate()
        guard maximumSubdivisionDepth >= 0, point.x.isFinite, point.y.isFinite else {
            throw Self.failure(phase: .classification, code: .invalidInput,
                tolerance: tolerance, message: "Signed original winding requires a finite query and nonnegative depth.")
        }
        return try winding(point, clearance: Self.parameterTolerance(from: tolerance).distance,
            tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage,
            maximumSubdivisionDepth: maximumSubdivisionDepth)
    }

    /// Returns nil when exact authored endpoint closure has no source proof.
    package func classifyStrictlyOriginal(_ point: Point2D, tolerance: ModelingTolerance,
        consumeWork: (@Sendable (Int) throws -> Void)? = nil,
        consumeStorage: (@Sendable (Int) throws -> Void)? = nil,
        maximumSubdivisionDepth: Int = 48) throws -> PlanarPointClassification? {
        try tolerance.validate(); try Task.checkCancellation(); try consumeWork?(0)
        guard maximumSubdivisionDepth >= 0, point.x.isFinite, point.y.isFinite else {
            throw Self.failure(phase: .classification, code: .invalidInput, tolerance: tolerance,
                message: "Strict original winding requires a finite query and nonnegative depth.")
        }
        guard uPeriod == nil, vPeriod == nil,
            try exactAuthoredClosure(consumeWork: consumeWork) else { return nil }
        switch try winding(point, clearance: 0, tolerance: tolerance,
            consumeWork: consumeWork, consumeStorage: consumeStorage,
            maximumSubdivisionDepth: maximumSubdivisionDepth, unresolvedIsBoundary: true) {
        case .boundary: return .indeterminate
        case .winding(let count): return count % 2 == 0 ? .outside : .inside
        }
    }

    private func winding(_ point: Point2D, clearance: Double, tolerance: ModelingTolerance,
        consumeWork: (@Sendable (Int) throws -> Void)?,
        consumeStorage: (@Sendable (Int) throws -> Void)?,
        maximumSubdivisionDepth: Int, unresolvedIsBoundary: Bool = false) throws -> WindingClassification {
        guard let boxes = try boxesExcluding(point, clearance: clearance,
            tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage,
            maximumSubdivisionDepth: min(maximumDepth, maximumSubdivisionDepth),
            unresolvedIsBoundary: unresolvedIsBoundary) else {
            return .boundary
        }
        guard boxes.count >= 3 else { return .winding(0) }
        for _ in boxes { try Task.checkCancellation(); try consumeWork?(0) }
        let polygon = try homotopyPolygon(boxes, tolerance: tolerance, clearance: clearance, consumeWork: consumeWork, consumeStorage: consumeStorage)
        var winding = 0
        for index in polygon.indices {
            try Task.checkCancellation()
            try consumeWork?(0)
            let start = polygon[index], end = polygon[(index + 1) % polygon.count]
            let upward = start.y <= point.y && end.y > point.y
            let downward = start.y > point.y && end.y <= point.y
            guard upward || downward else { continue }
            let orientation = try RobustPredicates.orientation2D(start, end,
                relativeTo: point, determinantTolerance: 0,
                consumeWork: { try consumeWork?(0) }, consumeStorage: consumeStorage)
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

    private func exactAuthoredClosure(consumeWork: (@Sendable (Int) throws -> Void)?) throws -> Bool {
        func endpoints(_ curve: SurfaceParameterCurve, depth: Int = 0) throws
            -> (SurfaceParameter, SurfaceParameter)? {
            try Task.checkCancellation(); try consumeWork?(0)
            guard depth < 16 else { return nil }
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
                    try consumeWork?(0); guard knot == lower else { return nil }
                }
                for knot in spline.knots.suffix(spline.degree + 1) {
                    try consumeWork?(0); guard knot == upper else { return nil }
                }
                for weight in spline.weights {
                    try consumeWork?(0); guard weight.isFinite, weight > 0 else { return nil }
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
        tolerance: ModelingTolerance
    ) throws -> Bool {
        try classify(point, tolerance: tolerance) == .inside
    }

    package func classify(
        _ point: Point2D,
        tolerance: ModelingTolerance,
        consumeWork: (@Sendable (Int) throws -> Void)? = nil,
        consumeStorage: (@Sendable (Int) throws -> Void)? = nil,
        maximumSubdivisionDepth: Int = 48
    ) throws -> PlanarPointClassification {
        try consumeWork?(0)
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
            consumeWork: consumeWork,
            consumeStorage: consumeStorage,
            maximumSubdivisionDepth: min(maximumDepth, maximumSubdivisionDepth)
        ) else {
            return .boundary
        }
        guard boxes.count >= 3 else {
            // A complete closed curve enclosed by fewer than three convex
            // boxes, all excluding the query, has zero winding around it.
            return .outside
        }
        for _ in boxes { try consumeWork?(0) }
        let polygon = try homotopyPolygon(boxes, tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)
        switch try AdaptivePlanarPredicateEvaluator().classify(
            point,
            in: polygon,
            tolerance: parameterTolerance
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
        consumeWork: (@Sendable (Int) throws -> Void)? = nil,
        consumeStorage: (@Sendable (Int) throws -> Void)? = nil,
        maximumSubdivisionDepth: Int = 48
    ) throws -> Bool {
        try tolerance.validate(); try Task.checkCancellation(); try consumeWork?(0)
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
        let firstBoxes = try initialBoxes(tolerance: tolerance, consumeWork: consumeWork,
            consumeStorage: consumeStorage, maximumSubdivisionDepth: depthLimit)
        let secondBoxes = try other.initialBoxes(
            additionalUShift: otherUShift,
            additionalVShift: otherVShift,
            tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage,
            maximumSubdivisionDepth: depthLimit
        )
        var pending: [PairWorkItem] = []
        for first in firstBoxes {
            for second in secondBoxes {
                try Task.checkCancellation(); try consumeWork?(0)
                guard Self.intersects(first, second, clearance: clearance) else { continue }
                try OriginalParameterQueryStorage.append(PairWorkItem(first: first, second: second, depth: 0),
                    to: &pending, consumeStorage: consumeStorage)
            }
        }
        var processedCount = 0
        while let item = pending.popLast() {
            try Task.checkCancellation(); try consumeWork?(item.depth)
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
                        consumeWork: consumeWork, consumeStorage: consumeStorage,
                        maximumSubdivisionDepth: depthLimit)
                } else {
                    refined = try other.boxes(for: range, additionalUShift: otherUShift,
                        additionalVShift: otherVShift, tolerance: tolerance,
                        consumeWork: consumeWork, consumeStorage: consumeStorage,
                        maximumSubdivisionDepth: depthLimit)
                }
                for box in refined {
                    try consumeWork?(item.depth + 1)
                    let pair = splitFirst
                        ? PairWorkItem(first: box, second: item.second, depth: item.depth + 1)
                        : PairWorkItem(first: item.first, second: box, depth: item.depth + 1)
                    if Self.intersects(pair.first, pair.second, clearance: clearance) {
                        try OriginalParameterQueryStorage.append(pair, to: &pending, consumeStorage: consumeStorage)
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
        consumeWork: (@Sendable (Int) throws -> Void)? = nil,
        consumeStorage: (@Sendable (Int) throws -> Void)? = nil,
        maximumSubdivisionDepth: Int = 48,
        unresolvedIsBoundary: Bool = false
    ) throws -> [CurveBox]? {
        var pending: [RangeWorkItem] = []
        try OriginalParameterQueryStorage.reserve(curves.count, in: &pending, consumeStorage: consumeStorage)
        for index in curves.indices {
            try Task.checkCancellation(); try consumeWork?(0)
            pending.append(RangeWorkItem(curveIndex: index, lowerFraction: 0, upperFraction: 1, depth: 0))
        }
        var accepted: [CurveBox] = []
        var processedCount = 0
        while let item = pending.popLast() {
            try consumeWork?(item.depth)
            let candidates = try boxes(for: item, tolerance: tolerance, consumeWork: consumeWork,
                consumeStorage: consumeStorage, maximumSubdivisionDepth: maximumSubdivisionDepth)
            for candidate in candidates {
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
                    try OriginalParameterQueryStorage.append(candidate, to: &accepted, consumeStorage: consumeStorage)
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
                ), to: &pending, consumeStorage: consumeStorage)
                try OriginalParameterQueryStorage.append(RangeWorkItem(
                    curveIndex: candidate.curveIndex,
                    lowerFraction: candidate.lowerFraction,
                    upperFraction: middle,
                    depth: item.depth + 1
                ), to: &pending, consumeStorage: consumeStorage)
            }
        }
        return try aligned(accepted, start: try chartReference(curveIndex: 0, fraction: 0, tolerance: tolerance),
            additionalUShift: 0, additionalVShift: 0,
            consumeWork: consumeWork, consumeStorage: consumeStorage)
    }

    private func homotopyPolygon(
        _ boxes: [CurveBox],
        tolerance: ModelingTolerance,
        clearance requestedClearance: Double? = nil,
        consumeWork: (@Sendable (Int) throws -> Void)? = nil,
        consumeStorage: (@Sendable (Int) throws -> Void)? = nil
    ) throws -> [Point2D] {
        let clearance = requestedClearance ?? Self.parameterTolerance(from: tolerance).distance
        var result: [Point2D] = []
        try OriginalParameterQueryStorage.reserve(boxes.count, in: &result, consumeStorage: consumeStorage)
        for index in boxes.indices {
            try Task.checkCancellation(); try consumeWork?(0)
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
        consumeWork: (@Sendable (Int) throws -> Void)? = nil,
        consumeStorage: (@Sendable (Int) throws -> Void)? = nil,
        maximumSubdivisionDepth: Int = 48
    ) throws -> [CurveBox] {
        let curve = curves[item.curveIndex]
        let enclosures = try CertifiedSurfaceParameterCurveEncloser(
            maximumSubdivisionDepth: maximumSubdivisionDepth - item.depth,
            consumeWork: { try consumeWork?(item.depth + $0) }, consumeStorage: consumeStorage,
            maximumAlgebraicDepth: maximumAlgebraicDepth, remainingSourceDepth: remainingSourceDepth).enclosures(
            for: curve,
            on: hostingSurface,
            fromNormalizedFraction: item.lowerFraction,
            toNormalizedFraction: item.upperFraction,
            maximumWidth: Double.greatestFiniteMagnitude.squareRoot(),
            tolerance: tolerance
        )
        var mapped: [CurveBox] = []
        try OriginalParameterQueryStorage.reserve(enclosures.count, in: &mapped, consumeStorage: consumeStorage)
        for enclosure in enclosures {
            try Task.checkCancellation(); try consumeWork?(item.depth)
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
            start: try chartReference(curveIndex: item.curveIndex, fraction: item.lowerFraction, tolerance: tolerance),
            additionalUShift: additionalUShift,
            additionalVShift: additionalVShift,
            consumeWork: consumeWork, consumeStorage: consumeStorage
        )
    }

    private func aligned(
        _ boxes: [CurveBox],
        start: SurfaceParameter,
        additionalUShift: Double,
        additionalVShift: Double,
        consumeWork: (@Sendable (Int) throws -> Void)? = nil,
        consumeStorage: (@Sendable (Int) throws -> Void)? = nil
    ) throws -> [CurveBox] {
        var referenceU = start.u + uShift + additionalUShift
        var referenceV = start.v + vShift + additionalVShift
        var result: [CurveBox] = []
        let ordered = try orderedBoxes(boxes, consumeWork: consumeWork, consumeStorage: consumeStorage)
        try OriginalParameterQueryStorage.reserve(ordered.count, in: &result, consumeStorage: consumeStorage)
        for box in ordered {
            try Task.checkCancellation(); try consumeWork?(0)
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
        tolerance: ModelingTolerance) throws -> SurfaceParameter {
        // Neither coordinate uses a reference without a periodic shift law.
        if uPeriod == nil, vPeriod == nil { return SurfaceParameter(u: 0, v: 0) }
        // FIXME(INCOMPLETE_IMPLEMENTATION): Periodic winding/boundary queries
        // still reach the legacy source parameter reference here. Complete
        // bounded chart admission requires the original endpoint/period receipt
        // and its caller work/byte ports; a numeric branch proposal alone is not
        // that receipt. Nonperiodic queries bypass this evaluation entirely.
        return try curves[curveIndex].parameter(atNormalizedFraction: fraction, tolerance: tolerance)
    }

    private func orderedBoxes(_ boxes: [CurveBox],
        consumeWork: (@Sendable (Int) throws -> Void)?,
        consumeStorage: (@Sendable (Int) throws -> Void)?) throws -> [CurveBox] {
        var result: [CurveBox] = []
        try OriginalParameterQueryStorage.reserve(boxes.count, in: &result, consumeStorage: consumeStorage)
        for box in boxes { try consumeWork?(0); result.append(box) }
        try OriginalParameterQueryStorage.sort(&result, consumeWork: consumeWork) { a, b in
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
        consumeWork: (@Sendable (Int) throws -> Void)? = nil,
        consumeStorage: (@Sendable (Int) throws -> Void)? = nil,
        maximumSubdivisionDepth: Int = 48
    ) throws -> [CurveBox] {
        var result: [CurveBox] = []
        for curveIndex in curves.indices {
            try Task.checkCancellation(); try consumeWork?(0)
            let originalBoxes = try boxes(for: RangeWorkItem(curveIndex: curveIndex,
                lowerFraction: 0, upperFraction: 1, depth: 0),
                additionalUShift: additionalUShift, additionalVShift: additionalVShift,
                tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage,
                maximumSubdivisionDepth: maximumSubdivisionDepth)
            for box in originalBoxes {
                try consumeWork?(0)
                try OriginalParameterQueryStorage.append(box, to: &result, consumeStorage: consumeStorage)
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
