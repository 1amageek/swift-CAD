import Foundation
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
        if let context = ExactPlaneHeightFieldContext(surface: first),
           let certificate = try heightCertificate(
               context: context,
               heightSurface: second,
               planeIsFirst: true,
               tolerance: tolerance
           ) {
            return certificate
        }
        if let context = ExactPlaneHeightFieldContext(surface: second),
           let certificate = try heightCertificate(
               context: context,
               heightSurface: first,
               planeIsFirst: false,
               tolerance: tolerance
           ) {
            return certificate
        }
        return nil
    }

    private static func heightCertificate(
        context: ExactPlaneHeightFieldContext,
        heightSurface: BSplineSurface3D,
        planeIsFirst: Bool,
        tolerance: ModelingTolerance
    ) throws -> QuadraticHeightFieldTangencyCertificate? {
        guard ExactPlaneHeightFieldContext.isSingleSpan(heightSurface),
              ExactPlaneHeightFieldContext.hasConstantWeights(heightSurface),
              heightSurface.uDegree <= 2,
              heightSurface.vDegree <= 2,
              heightSurface.uDegree > 0,
              heightSurface.vDegree > 0 else {
            return nil
        }
        guard let heightControls = context.exactHeightControls(
            for: heightSurface
        ), let height = ExactQuadraticPolynomial2D(
            bernsteinControlExpansions: heightControls,
            uDegree: heightSurface.uDegree,
            vDegree: heightSurface.vDegree
        ), let classified = height.classifiedZeroSet() else {
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
                ))
            )
        case let .line(line):
            guard let contact = try segment(
                line: line,
                surface: heightSurface,
                context: context,
                planeIsFirst: planeIsFirst,
                tolerance: tolerance
            ) else {
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
            ), let secondSegment = try segment(
                line: secondLine,
                surface: heightSurface,
                context: context,
                planeIsFirst: planeIsFirst,
                tolerance: tolerance
            ) else {
                return nil
            }
            return QuadraticHeightFieldTangencyCertificate(
                kind: .branching([firstSegment, secondSegment])
            )
        }
    }

    private static func segment(
        line: ExactQuadraticPolynomial2D.Line,
        surface: BSplineSurface3D,
        context: ExactPlaneHeightFieldContext,
        planeIsFirst: Bool,
        tolerance: ModelingTolerance
    ) throws -> Segment? {
        guard let endpoints = clippedLineEndpoints(
            origin: line.origin,
            direction: line.direction
        ) else {
            return nil
        }
        return Segment(
            lowerWitness: try context.verifiedWitness(
                on: surface,
                normalized: endpoints.lower,
                planeIsFirst: planeIsFirst,
                certificateName: "quadratic tangency",
                tolerance: tolerance
            ),
            midpointWitness: try context.verifiedWitness(
                on: surface,
                normalized: midpoint(endpoints.lower, endpoints.upper),
                planeIsFirst: planeIsFirst,
                certificateName: "quadratic tangency",
                tolerance: tolerance
            ),
            upperWitness: try context.verifiedWitness(
                on: surface,
                normalized: endpoints.upper,
                planeIsFirst: planeIsFirst,
                certificateName: "quadratic tangency",
                tolerance: tolerance
            )
        )
    }

    private static func clippedLineEndpoints(
        origin: Point2D,
        direction: Point2D
    ) -> (lower: Point2D, upper: Point2D)? {
        let directionTolerance = Double.ulpOfOne * 4_096.0
        var candidates: [(parameter: Double, point: Point2D)] = []
        if abs(direction.x) > directionTolerance {
            for boundary in [0.0, 1.0] {
                let parameter = (boundary - origin.x) / direction.x
                let point = Point2D(
                    x: boundary,
                    y: origin.y + direction.y * parameter
                )
                if point.y >= -directionTolerance,
                   point.y <= 1.0 + directionTolerance {
                    candidates.append((parameter, clamped(point)))
                }
            }
        }
        if abs(direction.y) > directionTolerance {
            for boundary in [0.0, 1.0] {
                let parameter = (boundary - origin.y) / direction.y
                let point = Point2D(
                    x: origin.x + direction.x * parameter,
                    y: boundary
                )
                if point.x >= -directionTolerance,
                   point.x <= 1.0 + directionTolerance {
                    candidates.append((parameter, clamped(point)))
                }
            }
        }
        candidates.sort { $0.parameter < $1.parameter }
        var unique: [(parameter: Double, point: Point2D)] = []
        for candidate in candidates where unique.contains(where: {
            distance($0.point, candidate.point) <= directionTolerance
        }) == false {
            unique.append(candidate)
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
