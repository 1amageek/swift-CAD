import Foundation
import CADCore

struct QuadraticHeightFieldTangencyCertificate: Sendable {
    struct Witness: Sendable {
        let point: Point3D
        let firstParameter: SurfaceParameterProjection
        let secondParameter: SurfaceParameterProjection
    }

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

    private struct PlaneFrame {
        let surface: BSplineSurface3D
        let origin: Point3D
        let u: Vector3D
        let v: Vector3D
        let exactU: ExactVector3
        let exactV: ExactVector3
    }

    private struct ExactVector3 {
        let x: [Double]
        let y: [Double]
        let z: [Double]
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
               planeIsFirst: true,
               tolerance: tolerance
           ) {
            return certificate
        }
        if let frame = planeFrame(surface: second),
           let certificate = try heightCertificate(
               planeFrame: frame,
               heightSurface: first,
               planeIsFirst: false,
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
            surface: surface,
            origin: origin,
            u: u,
            v: v,
            exactU: exactU,
            exactV: exactV
        )
    }

    private static func heightCertificate(
        planeFrame: PlaneFrame,
        heightSurface: BSplineSurface3D,
        planeIsFirst: Bool,
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
                kind: .isolated(try verifiedWitness(
                    heightSurface,
                    normalized: parameter,
                    planeFrame: planeFrame,
                    planeIsFirst: planeIsFirst,
                    tolerance: tolerance
                ))
            )
        case let .line(line):
            guard let contact = try segment(
                line: line,
                surface: heightSurface,
                planeFrame: planeFrame,
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
                planeFrame: planeFrame,
                planeIsFirst: planeIsFirst,
                tolerance: tolerance
            ), let secondSegment = try segment(
                line: secondLine,
                surface: heightSurface,
                planeFrame: planeFrame,
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
        planeFrame: PlaneFrame,
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
            lowerWitness: try verifiedWitness(
                surface,
                normalized: endpoints.lower,
                planeFrame: planeFrame,
                planeIsFirst: planeIsFirst,
                tolerance: tolerance
            ),
            midpointWitness: try verifiedWitness(
                surface,
                normalized: midpoint(endpoints.lower, endpoints.upper),
                planeFrame: planeFrame,
                planeIsFirst: planeIsFirst,
                tolerance: tolerance
            ),
            upperWitness: try verifiedWitness(
                surface,
                normalized: endpoints.upper,
                planeFrame: planeFrame,
                planeIsFirst: planeIsFirst,
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
        guard let firstRow = surface.controlPoints.first,
              let lastRow = surface.controlPoints.last,
              let origin = firstRow.first,
              let uEnd = firstRow.last,
              let vEnd = lastRow.first else {
            return nil
        }
        let exactU = exactDifference(uEnd, origin)
        let exactV = exactDifference(vEnd, origin)
        let projectedDeterminant = exactSubtract(
            exactMultiply(
                exactDot(exactU, planeFrame.exactU),
                exactDot(exactV, planeFrame.exactV)
            ),
            exactMultiply(
                exactDot(exactU, planeFrame.exactV),
                exactDot(exactV, planeFrame.exactU)
            )
        )
        guard exactSign(projectedDeterminant) != .zero else { return nil }

        var result: [[[Double]]] = []
        result.reserveCapacity(surface.controlPoints.count)
        for vIndex in surface.controlPoints.indices {
            let vFraction = Double(vIndex) / Double(surface.vDegree)
            var row: [[Double]] = []
            row.reserveCapacity(surface.controlPoints[vIndex].count)
            for uIndex in surface.controlPoints[vIndex].indices {
                let point = surface.controlPoints[vIndex][uIndex]
                let uFraction = Double(uIndex) / Double(surface.uDegree)
                let affineResidual = exactOffset(
                    point,
                    from: origin,
                    exactU: exactU,
                    uFraction: uFraction,
                    exactV: exactV,
                    vFraction: vFraction
                )
                guard exactSign(exactDot(
                    affineResidual,
                    planeFrame.exactU
                )) == .zero,
                exactSign(exactDot(
                    affineResidual,
                    planeFrame.exactV
                )) == .zero else {
                    return nil
                }
                let planeOffset = exactDifference(point, planeFrame.origin)
                row.append(exactTripleProduct(
                    planeFrame.exactU,
                    planeFrame.exactV,
                    planeOffset
                ))
            }
            result.append(row)
        }
        return result
    }

    private static func verifiedWitness(
        _ surface: BSplineSurface3D,
        normalized: Point2D,
        planeFrame: PlaneFrame,
        planeIsFirst: Bool,
        tolerance: ModelingTolerance
    ) throws -> Witness {
        guard case let .closed(uLower, uUpper) = surface.uDomain,
              case let .closed(vLower, vUpper) = surface.vDomain,
              case let .closed(planeULower, planeUUpper) = planeFrame.surface.uDomain,
              case let .closed(planeVLower, planeVUpper) = planeFrame.surface.vDomain else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A quadratic tangency certificate requires closed surface domains."
            )
        }
        let heightU = uLower + (uUpper - uLower) * normalized.x
        let heightV = vLower + (vUpper - vLower) * normalized.y
        let point = try surface.point(
            u: heightU,
            v: heightV,
            tolerance: tolerance
        )
        let relative = point - planeFrame.origin
        let metricUU = planeFrame.u.dot(planeFrame.u)
        let metricUV = planeFrame.u.dot(planeFrame.v)
        let metricVV = planeFrame.v.dot(planeFrame.v)
        let determinant = metricUU * metricVV - metricUV * metricUV
        guard determinant.isFinite, determinant > 0.0 else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                tolerance: tolerance,
                message: "A quadratic tangency plane frame is singular."
            )
        }
        let rightU = relative.dot(planeFrame.u)
        let rightV = relative.dot(planeFrame.v)
        let normalizedPlaneU = (rightU * metricVV - rightV * metricUV) / determinant
        let normalizedPlaneV = (rightV * metricUU - rightU * metricUV) / determinant
        let planeU = planeULower + (planeUUpper - planeULower) * normalizedPlaneU
        let planeV = planeVLower + (planeVUpper - planeVLower) * normalizedPlaneV
        let planePoint = try planeFrame.surface.point(
            u: planeU,
            v: planeV,
            tolerance: tolerance
        )
        let residual = (planePoint - point).length
        guard residual.isFinite, residual <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: residual,
                tolerance: tolerance,
                message: "A quadratic tangency certificate witness failed plane residual verification."
            )
        }
        let planeProjection = try SurfaceParameterProjection(
            u: planeU,
            v: planeV,
            point: planePoint,
            residual: residual
        )
        let heightProjection = try SurfaceParameterProjection(
            u: heightU,
            v: heightV,
            point: point,
            residual: 0.0
        )
        return Witness(
            point: point,
            firstParameter: planeIsFirst ? planeProjection : heightProjection,
            secondParameter: planeIsFirst ? heightProjection : planeProjection
        )
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
