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

struct QuadraticHeightFieldTangencyCertificate: Sendable {
    typealias Witness = ExactPlaneHeightFieldContext.Witness

    struct Segment: Sendable {
        let lowerWitness: Witness
        let midpointWitness: Witness
        let upperWitness: Witness

        var lower: Point3D { lowerWitness.point }
        var midpoint: Point3D { midpointWitness.point }
        var upper: Point3D { upperWitness.point }

        var witnesses: [Point3D] {
            [lower, midpoint, upper]
        }
    }

    enum Kind: Sendable {
        case isolated(Witness)
        case contact(Segment)
        case branching([Segment])
    }

    let kind: Kind

    static func certified(
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws -> QuadraticHeightFieldTangencyCertificate? {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try certified(first: first, second: second, tolerance: tolerance, using: &execution)
    }


    static func certified(
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> QuadraticHeightFieldTangencyCertificate? {
        try execution.consumeWork(1)
        try first.validate(tolerance: tolerance, using: &execution)
        try second.validate(tolerance: tolerance, using: &execution)

        if let context = try ExactPlaneHeightFieldContext(surface: first, using: &execution),
           let certificate = try heightCertificate(
               context: context,
               heightSurface: second,
               planeIsFirst: true,
               tolerance: tolerance
           , using: &execution) {
            return certificate
        }
        if let context = try ExactPlaneHeightFieldContext(surface: second, using: &execution),
           let certificate = try heightCertificate(
               context: context,
               heightSurface: first,
               planeIsFirst: false,
               tolerance: tolerance
           , using: &execution) {
            return certificate
        }
        return nil
    }



    private static func heightCertificate(
        context: ExactPlaneHeightFieldContext,
        heightSurface: BSplineSurface3D,
        planeIsFirst: Bool,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> QuadraticHeightFieldTangencyCertificate? {
        try execution.consumeWork(1)

        guard try ExactPlaneHeightFieldContext.isSingleSpan(heightSurface, using: &execution),
              try ExactPlaneHeightFieldContext.hasConstantWeights(heightSurface, using: &execution),
              heightSurface.uDegree <= 2,
              heightSurface.vDegree <= 2,
              heightSurface.uDegree > 0,
              heightSurface.vDegree > 0 else {
            return nil
        }
        guard let heightControls = try context.exactHeightControls(
            for: heightSurface
        , using: &execution), let height = try ExactQuadraticPolynomial2D(
            bernsteinControlExpansions: heightControls,
            uDegree: heightSurface.uDegree,
            vDegree: heightSurface.vDegree
        , using: &execution), let classified = try height.classifiedZeroSet(using: &execution) else {
            return nil
        }
        switch classified {
        case let .isolated(parameter):
            return QuadraticHeightFieldTangencyCertificate(
                kind: .isolated(try context.verifiedWitness(
                    on: heightSurface,
                    normalized: parameter,
                    planeIsFirst: planeIsFirst,
                    certificateName: "quadratic tangency",
                    tolerance: tolerance
                , using: &execution))
            )
        case let .line(line):
            guard let contact = try segment(
                line: line,
                surface: heightSurface,
                context: context,
                planeIsFirst: planeIsFirst,
                tolerance: tolerance
            , using: &execution) else {
                return nil
            }
            return QuadraticHeightFieldTangencyCertificate(
                kind: .contact(contact)
            )
        case let .crossing(firstLine, secondLine):
            guard let firstSegment = try segment(
                line: firstLine,
                surface: heightSurface,
                context: context,
                planeIsFirst: planeIsFirst,
                tolerance: tolerance
            , using: &execution), let secondSegment = try segment(
                line: secondLine,
                surface: heightSurface,
                context: context,
                planeIsFirst: planeIsFirst,
                tolerance: tolerance
            , using: &execution) else {
                return nil
            }
            return QuadraticHeightFieldTangencyCertificate(
                kind: .branching(try CertifiedAnalyticCurveEvaluation.values(firstSegment, secondSegment, using: &execution))
            )
        }
    }



    private static func segment(
        line: ExactQuadraticPolynomial2D.Line,
        surface: BSplineSurface3D,
        context: ExactPlaneHeightFieldContext,
        planeIsFirst: Bool,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> Segment? {
        try execution.consumeWork(1)

        guard let endpoints = try clippedLineEndpoints(
            origin: line.origin,
            direction: line.direction
        , using: &execution) else {
            return nil
        }
        return Segment(
            lowerWitness: try context.verifiedWitness(
                on: surface,
                normalized: endpoints.lower,
                planeIsFirst: planeIsFirst,
                certificateName: "quadratic tangency",
                tolerance: tolerance
            , using: &execution),
            midpointWitness: try context.verifiedWitness(
                on: surface,
                normalized: midpoint(endpoints.lower, endpoints.upper),
                planeIsFirst: planeIsFirst,
                certificateName: "quadratic tangency",
                tolerance: tolerance
            , using: &execution),
            upperWitness: try context.verifiedWitness(
                on: surface,
                normalized: endpoints.upper,
                planeIsFirst: planeIsFirst,
                certificateName: "quadratic tangency",
                tolerance: tolerance
            , using: &execution)
        )
    }



    private static func clippedLineEndpoints(
        origin: Point2D,
        direction: Point2D
    , using execution: inout OriginalQueryExecution) throws -> (lower: Point2D, upper: Point2D)? {
        try execution.consumeWork(1)

        let directionTolerance = Double.ulpOfOne * 4_096.0
        var candidates: [(parameter: Double, point: Point2D)] = []
        var candidateCapacity = 0
        if abs(direction.x) > directionTolerance {
            for boundary in [0.0, 1.0] {
                try execution.consumeWork(1)
                let parameter = (boundary - origin.x) / direction.x
                let point = Point2D(
                    x: boundary,
                    y: origin.y + direction.y * parameter
                )
                if point.y >= -directionTolerance,
                   point.y <= 1.0 + directionTolerance {
                    try CertifiedAnalyticCurveEvaluation.append((parameter, clamped(point)), to: &candidates, using: &execution, capacity: &candidateCapacity)
                }
            }
        }
        if abs(direction.y) > directionTolerance {
            for boundary in [0.0, 1.0] {
                try execution.consumeWork(1)
                let parameter = (boundary - origin.y) / direction.y
                let point = Point2D(
                    x: origin.x + direction.x * parameter,
                    y: boundary
                )
                if point.x >= -directionTolerance,
                   point.x <= 1.0 + directionTolerance {
                    try CertifiedAnalyticCurveEvaluation.append((parameter, clamped(point)), to: &candidates, using: &execution, capacity: &candidateCapacity)
                }
            }
        }
        candidates = try CertifiedAnalyticCurveEvaluation.sorted(candidates, using: &execution) { $0.parameter < $1.parameter }
        var unique: [(parameter: Double, point: Point2D)] = []
        var uniqueCapacity = 0
        for candidate in candidates {
            try execution.consumeWork(1)
            let duplicate = try unique.contains { previous in
                try execution.consumeWork(1)
                return distance(previous.point, candidate.point) <= directionTolerance
            }
            if !duplicate {
                try CertifiedAnalyticCurveEvaluation.append(candidate, to: &unique, using: &execution, capacity: &uniqueCapacity)
            }
        }
        guard let lower = unique.first?.point,
              let upper = unique.last?.point,
              distance(lower, upper) > directionTolerance else {
            return nil
        }
        return (lower, upper)
    }

    private static func midpoint(_ first: Point2D, _ second: Point2D) -> Point2D {
        Point2D(x: (first.x + second.x) * 0.5, y: (first.y + second.y) * 0.5)
    }

    private static func clamped(_ point: Point2D) -> Point2D {
        Point2D(
            x: min(max(point.x, 0.0), 1.0),
            y: min(max(point.y, 0.0), 1.0)
        )
    }

    private static func squaredLength(_ value: Point2D) -> Double {
        value.x * value.x + value.y * value.y
    }

    private static func length(_ value: Point2D) -> Double {
        sqrt(squaredLength(value))
    }

    private static func distance(_ first: Point2D, _ second: Point2D) -> Double {
        length(Point2D(x: first.x - second.x, y: first.y - second.y))
    }
}
