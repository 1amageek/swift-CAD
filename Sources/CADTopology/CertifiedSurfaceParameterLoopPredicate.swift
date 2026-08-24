import CADCore
import CADGeometry
import Foundation

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

    private let curves: [SurfaceParameterCurve]
    private let uShift: Double
    private let vShift: Double
    private let uPeriod: Double?
    private let vPeriod: Double?
    private let maximumDepth = 48
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
        uShift: Double = 0.0,
        vShift: Double = 0.0,
        uPeriod: Double? = nil,
        vPeriod: Double? = nil,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        guard curves.isEmpty == false,
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
        self.curves = curves
        self.uShift = uShift
        self.vShift = vShift
        self.uPeriod = uPeriod
        self.vPeriod = vPeriod
    }

    package func containsStrictly(
        _ point: Point2D,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        try classify(point, tolerance: tolerance) == .inside
    }

    package func classify(
        _ point: Point2D,
        tolerance: ModelingTolerance
    ) throws -> PlanarPointClassification {
        try tolerance.validate()
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
            tolerance: tolerance
        ) else {
            return .boundary
        }
        guard boxes.count >= 3 else {
            // A complete closed curve enclosed by fewer than three convex
            // boxes, all excluding the query, has zero winding around it.
            return .outside
        }
        let polygon = try homotopyPolygon(
            boxes,
            tolerance: tolerance
        )
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
        tolerance: ModelingTolerance
    ) throws -> Bool {
        try tolerance.validate()
        guard otherUShift.isFinite, otherVShift.isFinite else {
            throw Self.failure(
                phase: .classification,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Certified pcurve boundary comparison requires finite chart shifts."
            )
        }
        let clearance = Self.parameterTolerance(from: tolerance).distance
        let firstBoxes = try initialBoxes(tolerance: tolerance)
        let secondBoxes = try other.initialBoxes(
            additionalUShift: otherUShift,
            additionalVShift: otherVShift,
            tolerance: tolerance
        )
        var pending: [PairWorkItem] = []
        for first in firstBoxes {
            for second in secondBoxes where Self.intersects(
                first,
                second,
                clearance: clearance
            ) {
                pending.append(PairWorkItem(first: first, second: second, depth: 0))
            }
        }
        var processedCount = 0
        while let item = pending.popLast() {
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
            guard item.depth < maximumDepth else {
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
            let refined: [CurveBox]
            if splitFirst {
                refined = try boxes(for: lower, tolerance: tolerance)
                    + boxes(for: upper, tolerance: tolerance)
            } else {
                refined = try other.boxes(
                    for: lower,
                    additionalUShift: otherUShift,
                    additionalVShift: otherVShift,
                    tolerance: tolerance
                ) + other.boxes(
                    for: upper,
                    additionalUShift: otherUShift,
                    additionalVShift: otherVShift,
                    tolerance: tolerance
                )
            }
            for box in refined {
                let pair = splitFirst
                    ? PairWorkItem(first: box, second: item.second, depth: item.depth + 1)
                    : PairWorkItem(first: item.first, second: box, depth: item.depth + 1)
                if Self.intersects(pair.first, pair.second, clearance: clearance) {
                    pending.append(pair)
                }
            }
        }
        return false
    }

    private func boxesExcluding(
        _ point: Point2D,
        clearance: Double,
        tolerance: ModelingTolerance
    ) throws -> [CurveBox]? {
        var pending = curves.indices.map {
            RangeWorkItem(
                curveIndex: $0,
                lowerFraction: 0.0,
                upperFraction: 1.0,
                depth: 0
            )
        }
        var accepted: [CurveBox] = []
        var processedCount = 0
        while let item = pending.popLast() {
            let candidates = try boxes(for: item, tolerance: tolerance)
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
                    accepted.append(candidate)
                    continue
                }
                if candidate.maximumWidth <= clearance {
                    return nil
                }
                guard item.depth < maximumDepth,
                      candidate.fractionWidth > tolerance.relative * 4.0 else {
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
                pending.append(RangeWorkItem(
                    curveIndex: candidate.curveIndex,
                    lowerFraction: middle,
                    upperFraction: candidate.upperFraction,
                    depth: item.depth + 1
                ))
                pending.append(RangeWorkItem(
                    curveIndex: candidate.curveIndex,
                    lowerFraction: candidate.lowerFraction,
                    upperFraction: middle,
                    depth: item.depth + 1
                ))
            }
        }
        let sorted = accepted.sorted { lhs, rhs in
            if lhs.curveIndex != rhs.curveIndex {
                return lhs.curveIndex < rhs.curveIndex
            }
            if lhs.lowerFraction != rhs.lowerFraction {
                return lhs.lowerFraction < rhs.lowerFraction
            }
            return lhs.upperFraction < rhs.upperFraction
        }
        return try aligned(
            sorted,
            start: try curves[0].startParameter(tolerance: tolerance),
            additionalUShift: 0.0,
            additionalVShift: 0.0
        )
    }

    private func homotopyPolygon(
        _ boxes: [CurveBox],
        tolerance: ModelingTolerance
    ) throws -> [Point2D] {
        let clearance = Self.parameterTolerance(from: tolerance).distance
        var result: [Point2D] = []
        result.reserveCapacity(boxes.count)
        for index in boxes.indices {
            let current = boxes[index]
            let next = boxes[(index + 1) % boxes.count]
            // A topological vertex permits its two independently evaluated
            // pcurve endpoints to differ by the modeling tolerance. Query
            // exclusion was established against these same expanded boxes,
            // so their intersection remains a valid punctured-plane
            // homotopy corridor without fabricating a geometric edge.
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
                let coverage = boxes.map {
                    "c\($0.curveIndex):[\($0.lowerFraction),\($0.upperFraction)]"
                }.joined(separator: ",")
                throw Self.failure(
                    phase: .classification,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "Consecutive certified pcurve enclosures \(index) (curve \(current.curveIndex), fraction \(current.upperFraction)) and \((index + 1) % boxes.count) (curve \(next.curveIndex), fraction \(next.lowerFraction)) do not share their exact endpoint: first u=[\(current.u.lower), \(current.u.upper)] v=[\(current.v.lower), \(current.v.upper)], second u=[\(next.u.lower), \(next.u.upper)] v=[\(next.v.lower), \(next.v.upper)]. Coverage: \(coverage)."
                )
            }
            result.append(Point2D(
                x: lowerU + (upperU - lowerU) * 0.5,
                y: lowerV + (upperV - lowerV) * 0.5
            ))
        }
        return result
    }

    private func boxes(
        for item: RangeWorkItem,
        additionalUShift: Double = 0.0,
        additionalVShift: Double = 0.0,
        tolerance: ModelingTolerance
    ) throws -> [CurveBox] {
        let curve = curves[item.curveIndex]
        let mapped = try CertifiedSurfaceParameterCurveEncloser().enclosures(
            for: curve,
            fromNormalizedFraction: item.lowerFraction,
            toNormalizedFraction: item.upperFraction,
            maximumWidth: Double.greatestFiniteMagnitude.squareRoot(),
            tolerance: tolerance
        ).map { enclosure in
            CurveBox(
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
            )
        }
        return try aligned(
            mapped,
            start: try curve.parameter(
                atNormalizedFraction: item.lowerFraction,
                tolerance: tolerance
            ),
            additionalUShift: additionalUShift,
            additionalVShift: additionalVShift
        )
    }

    private func aligned(
        _ boxes: [CurveBox],
        start: SurfaceParameter,
        additionalUShift: Double,
        additionalVShift: Double
    ) throws -> [CurveBox] {
        var referenceU = start.u + uShift + additionalUShift
        var referenceV = start.v + vShift + additionalVShift
        var result: [CurveBox] = []
        for box in boxes.sorted(by: { lhs, rhs in
            if lhs.curveIndex != rhs.curveIndex {
                return lhs.curveIndex < rhs.curveIndex
            }
            return lhs.lowerFraction < rhs.lowerFraction
        }) {
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

    private static func periodicShift(
        _ value: Double,
        nearest reference: Double,
        period: Double?
    ) -> Double {
        guard let period else { return 0.0 }
        return round((reference - value) / period) * period
    }

    private func initialBoxes(
        additionalUShift: Double = 0.0,
        additionalVShift: Double = 0.0,
        tolerance: ModelingTolerance
    ) throws -> [CurveBox] {
        try curves.indices.flatMap { curveIndex in
            try boxes(
                for: RangeWorkItem(
                    curveIndex: curveIndex,
                    lowerFraction: 0.0,
                    upperFraction: 1.0,
                    depth: 0
                ),
                additionalUShift: additionalUShift,
                additionalVShift: additionalVShift,
                tolerance: tolerance
            )
        }
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
