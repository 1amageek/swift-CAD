import Foundation
import CADCore

struct QuadraticHeightFieldTangencyCertificate: Sendable {
    struct Segment: Sendable {
        let lower: Point3D
        let midpoint: Point3D
        let upper: Point3D

        var witnesses: [Point3D] {
            [lower, midpoint, upper]
        }
    }

    enum Kind: Sendable {
        case isolated(Point3D)
        case contact(Segment)
        case branching([Segment])
    }

    private struct PlaneFrame {
        let origin: Point3D
        let u: Vector3D
        let v: Vector3D
        let normal: Vector3D
        let exactU: ExactVector3
        let exactV: ExactVector3
    }

    private struct ExactVector3 {
        let x: [Double]
        let y: [Double]
        let z: [Double]
    }

    private enum UnitSquareMapping: CaseIterable {
        case identity
        case reverseU
        case reverseV
        case reverseBoth
        case swap
        case swapReverseU
        case swapReverseV
        case swapReverseBoth

        func parameter(u: Double, v: Double) -> Point2D {
            switch self {
            case .identity:
                Point2D(x: u, y: v)
            case .reverseU:
                Point2D(x: 1.0 - u, y: v)
            case .reverseV:
                Point2D(x: u, y: 1.0 - v)
            case .reverseBoth:
                Point2D(x: 1.0 - u, y: 1.0 - v)
            case .swap:
                Point2D(x: v, y: u)
            case .swapReverseU:
                Point2D(x: 1.0 - v, y: u)
            case .swapReverseV:
                Point2D(x: v, y: 1.0 - u)
            case .swapReverseBoth:
                Point2D(x: 1.0 - v, y: 1.0 - u)
            }
        }
    }

    let kind: Kind

    static func certified(
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws -> QuadraticHeightFieldTangencyCertificate? {
        if let frame = planeFrame(surface: first),
           let certificate = try heightCertificate(
               planeFrame: frame,
               heightSurface: second,
               tolerance: tolerance
           ) {
            return certificate
        }
        if let frame = planeFrame(surface: second),
           let certificate = try heightCertificate(
               planeFrame: frame,
               heightSurface: first,
               tolerance: tolerance
           ) {
            return certificate
        }
        return nil
    }

    private static func planeFrame(surface: BSplineSurface3D) -> PlaneFrame? {
        guard isSingleSpan(surface),
              hasConstantWeights(surface),
              surface.uDegree > 0,
              surface.vDegree > 0,
              surface.uDegree <= 2,
              surface.vDegree <= 2,
              let firstRow = surface.controlPoints.first,
              let lastRow = surface.controlPoints.last,
              let origin = firstRow.first,
              let uEnd = firstRow.last,
              let vEnd = lastRow.first else {
            return nil
        }
        let u = uEnd - origin
        let v = vEnd - origin
        let exactU = exactDifference(uEnd, origin)
        let exactV = exactDifference(vEnd, origin)
        let metricDeterminant = exactSubtract(
            exactMultiply(exactDot(exactU, exactU), exactDot(exactV, exactV)),
            exactMultiply(exactDot(exactU, exactV), exactDot(exactU, exactV))
        )
        guard exactSign(metricDeterminant) == .positive else {
            return nil
        }
        let area = u.cross(v)
        let areaLength = area.length
        guard areaLength.isFinite, areaLength > 0.0 else {
            return nil
        }
        let normal = area / areaLength
        let uDegree = surface.uDegree
        let vDegree = surface.vDegree
        for vIndex in surface.controlPoints.indices {
            let vFraction = Double(vIndex) / Double(vDegree)
            for uIndex in surface.controlPoints[vIndex].indices {
                let uFraction = Double(uIndex) / Double(uDegree)
                let offset = exactOffset(
                    surface.controlPoints[vIndex][uIndex],
                    from: origin,
                    exactU: exactU,
                    uFraction: uFraction,
                    exactV: exactV,
                    vFraction: vFraction
                )
                guard exactVectorIsZero(offset) else {
                    return nil
                }
            }
        }
        return PlaneFrame(
            origin: origin,
            u: u,
            v: v,
            normal: normal,
            exactU: exactU,
            exactV: exactV
        )
    }

    private static func heightCertificate(
        planeFrame: PlaneFrame,
        heightSurface: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws -> QuadraticHeightFieldTangencyCertificate? {
        guard isSingleSpan(heightSurface),
              hasConstantWeights(heightSurface),
              heightSurface.uDegree <= 2,
              heightSurface.vDegree <= 2,
              heightSurface.uDegree > 0,
              heightSurface.vDegree > 0 else {
            return nil
        }
        guard let heightControls = exactHeightControls(
            planeFrame: planeFrame,
            surface: heightSurface
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
                kind: .isolated(try verifiedSurfacePoint(
                    heightSurface,
                    normalized: parameter,
                    planeFrame: planeFrame,
                    tolerance: tolerance
                ))
            )
        case let .line(line):
            guard let contact = try segment(
                line: line,
                surface: heightSurface,
                planeFrame: planeFrame,
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
                planeFrame: planeFrame,
                tolerance: tolerance
            ), let secondSegment = try segment(
                line: secondLine,
                surface: heightSurface,
                planeFrame: planeFrame,
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
        planeFrame: PlaneFrame,
        tolerance: ModelingTolerance
    ) throws -> Segment? {
        guard let endpoints = clippedLineEndpoints(
            origin: line.origin,
            direction: line.direction
        ) else {
            return nil
        }
        return Segment(
            lower: try verifiedSurfacePoint(
                surface,
                normalized: endpoints.lower,
                planeFrame: planeFrame,
                tolerance: tolerance
            ),
            midpoint: try verifiedSurfacePoint(
                surface,
                normalized: midpoint(endpoints.lower, endpoints.upper),
                planeFrame: planeFrame,
                tolerance: tolerance
            ),
            upper: try verifiedSurfacePoint(
                surface,
                normalized: endpoints.upper,
                planeFrame: planeFrame,
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

    private static func exactHeightControls(
        planeFrame: PlaneFrame,
        surface: BSplineSurface3D
    ) -> [[[Double]]]? {
        for mapping in UnitSquareMapping.allCases {
            var result: [[[Double]]] = []
            var isValid = true
            for vIndex in surface.controlPoints.indices {
                let vFraction = Double(vIndex) / Double(surface.vDegree)
                var row: [[Double]] = []
                for uIndex in surface.controlPoints[vIndex].indices {
                    let uFraction = Double(uIndex) / Double(surface.uDegree)
                    let mapped = mapping.parameter(u: uFraction, v: vFraction)
                    let offset = exactOffset(
                        surface.controlPoints[vIndex][uIndex],
                        from: planeFrame.origin,
                        exactU: planeFrame.exactU,
                        uFraction: mapped.x,
                        exactV: planeFrame.exactV,
                        vFraction: mapped.y
                    )
                    guard exactSign(exactDot(offset, planeFrame.exactU)) == .zero,
                          exactSign(exactDot(offset, planeFrame.exactV)) == .zero else {
                        isValid = false
                        break
                    }
                    row.append(exactTripleProduct(
                        planeFrame.exactU,
                        planeFrame.exactV,
                        offset
                    ))
                }
                guard isValid else { break }
                result.append(row)
            }
            if isValid {
                return result
            }
        }
        return nil
    }

    private static func verifiedSurfacePoint(
        _ surface: BSplineSurface3D,
        normalized: Point2D,
        planeFrame: PlaneFrame,
        tolerance: ModelingTolerance
    ) throws -> Point3D {
        guard case let .closed(uLower, uUpper) = surface.uDomain,
              case let .closed(vLower, vUpper) = surface.vDomain else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A quadratic tangency certificate requires closed surface domains."
            )
        }
        let point = try surface.point(
            u: uLower + (uUpper - uLower) * normalized.x,
            v: vLower + (vUpper - vLower) * normalized.y,
            tolerance: tolerance
        )
        let residual = abs((point - planeFrame.origin).dot(planeFrame.normal))
        guard residual.isFinite, residual <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: residual,
                tolerance: tolerance,
                message: "A quadratic tangency certificate witness failed plane residual verification."
            )
        }
        return point
    }

    private static func exactDifference(
        _ lhs: Point3D,
        _ rhs: Point3D
    ) -> ExactVector3 {
        ExactVector3(
            x: FloatingPointExpansion.difference(lhs.x, rhs.x),
            y: FloatingPointExpansion.difference(lhs.y, rhs.y),
            z: FloatingPointExpansion.difference(lhs.z, rhs.z)
        )
    }

    private static func exactOffset(
        _ point: Point3D,
        from origin: Point3D,
        exactU: ExactVector3,
        uFraction: Double,
        exactV: ExactVector3,
        vFraction: Double
    ) -> ExactVector3 {
        let pointOffset = exactDifference(point, origin)
        return exactSubtract(
            exactSubtract(
                pointOffset,
                exactScaled(exactU, by: uFraction)
            ),
            exactScaled(exactV, by: vFraction)
        )
    }

    private static func exactVectorIsZero(_ value: ExactVector3) -> Bool {
        exactSign(value.x) == .zero
            && exactSign(value.y) == .zero
            && exactSign(value.z) == .zero
    }

    private static func exactDot(
        _ lhs: ExactVector3,
        _ rhs: ExactVector3
    ) -> [Double] {
        exactAdd(
            exactAdd(
                exactMultiply(lhs.x, rhs.x),
                exactMultiply(lhs.y, rhs.y)
            ),
            exactMultiply(lhs.z, rhs.z)
        )
    }

    private static func exactTripleProduct(
        _ first: ExactVector3,
        _ second: ExactVector3,
        _ third: ExactVector3
    ) -> [Double] {
        exactDot(first, ExactVector3(
            x: exactSubtract(
                exactMultiply(second.y, third.z),
                exactMultiply(second.z, third.y)
            ),
            y: exactSubtract(
                exactMultiply(second.z, third.x),
                exactMultiply(second.x, third.z)
            ),
            z: exactSubtract(
                exactMultiply(second.x, third.y),
                exactMultiply(second.y, third.x)
            )
        ))
    }

    private static func exactScaled(
        _ value: ExactVector3,
        by scale: Double
    ) -> ExactVector3 {
        ExactVector3(
            x: exactMultiply(value.x, [scale]),
            y: exactMultiply(value.y, [scale]),
            z: exactMultiply(value.z, [scale])
        )
    }

    private static func exactSubtract(
        _ lhs: ExactVector3,
        _ rhs: ExactVector3
    ) -> ExactVector3 {
        ExactVector3(
            x: exactSubtract(lhs.x, rhs.x),
            y: exactSubtract(lhs.y, rhs.y),
            z: exactSubtract(lhs.z, rhs.z)
        )
    }

    private static func exactSign(_ value: [Double]) -> RobustSign {
        FloatingPointExpansion.sign(value)
    }

    private static func exactAdd(
        _ lhs: [Double],
        _ rhs: [Double]
    ) -> [Double] {
        FloatingPointExpansion.sum(lhs, rhs)
    }

    private static func exactSubtract(
        _ lhs: [Double],
        _ rhs: [Double]
    ) -> [Double] {
        FloatingPointExpansion.subtract(lhs, rhs)
    }

    private static func exactMultiply(
        _ lhs: [Double],
        _ rhs: [Double]
    ) -> [Double] {
        FloatingPointExpansion.product(lhs, rhs)
    }

    private static func isSingleSpan(_ surface: BSplineSurface3D) -> Bool {
        surface.controlPoints.count == surface.vDegree + 1
            && surface.controlPoints.allSatisfy { $0.count == surface.uDegree + 1 }
            && isSingleSpan(knots: surface.uKnots, degree: surface.uDegree)
            && isSingleSpan(knots: surface.vKnots, degree: surface.vDegree)
    }

    private static func isSingleSpan(knots: [Double], degree: Int) -> Bool {
        guard knots.count == 2 * (degree + 1),
              let lower = knots.first,
              let upper = knots.last,
              lower.isFinite,
              upper.isFinite,
              upper > lower else {
            return false
        }
        return knots.prefix(degree + 1).allSatisfy { $0 == lower }
            && knots.suffix(degree + 1).allSatisfy { $0 == upper }
    }

    private static func hasConstantWeights(_ surface: BSplineSurface3D) -> Bool {
        guard let reference = surface.weights.first?.first,
              reference.isFinite,
              reference > 0.0 else {
            return false
        }
        return surface.weights.flatMap { $0 }.allSatisfy {
            $0.isFinite && $0 > 0.0 && $0 == reference
        }
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
