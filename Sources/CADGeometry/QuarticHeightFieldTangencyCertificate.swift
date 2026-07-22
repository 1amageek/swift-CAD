import CADCore
import Foundation

struct QuarticHeightFieldTangencyCertificate: Sendable {
    struct Witness: Sendable {
        let point: Point3D
        let firstParameter: SurfaceParameterProjection
        let secondParameter: SurfaceParameterProjection
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

    let witness: Witness

    static func certified(
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws -> QuarticHeightFieldTangencyCertificate? {
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

    private static func heightCertificate(
        planeFrame: PlaneFrame,
        heightSurface: BSplineSurface3D,
        planeIsFirst: Bool,
        tolerance: ModelingTolerance
    ) throws -> QuarticHeightFieldTangencyCertificate? {
        guard isSingleSpan(heightSurface),
              hasConstantWeights(heightSurface),
              heightSurface.uDegree == 4,
              heightSurface.vDegree == 4,
              let heightControls = exactHeightControls(
                  planeFrame: planeFrame,
                  surface: heightSurface
              ),
              let isolatedParameter = isolatedQuarticPowerSumRoot(
                  bernsteinControlExpansions: heightControls
              ) else {
            return nil
        }
        return QuarticHeightFieldTangencyCertificate(
            witness: try verifiedWitness(
                heightSurface,
                normalized: isolatedParameter,
                planeFrame: planeFrame,
                planeIsFirst: planeIsFirst,
                tolerance: tolerance
            )
        )
    }

    private static func isolatedQuarticPowerSumRoot(
        bernsteinControlExpansions: [[[Double]]]
    ) -> Point2D? {
        guard bernsteinControlExpansions.count == 5,
              bernsteinControlExpansions.allSatisfy({ $0.count == 5 }) else {
            return nil
        }
        let power = powerCoefficients(
            bernsteinControlExpansions: bernsteinControlExpansions
        )
        let uLeading = power[0][4]
        let vLeading = power[4][0]
        let uSign = exactSign(uLeading)
        let vSign = exactSign(vLeading)
        guard uSign != .zero,
              uSign == vSign else {
            return nil
        }
        let uLeadingEstimate = estimate(uLeading)
        let vLeadingEstimate = estimate(vLeading)
        let uCubicEstimate = estimate(power[0][3])
        let vCubicEstimate = estimate(power[3][0])
        guard uLeadingEstimate.isFinite,
              vLeadingEstimate.isFinite,
              uLeadingEstimate != 0.0,
              vLeadingEstimate != 0.0 else {
            return nil
        }
        let uRoot = -uCubicEstimate / (4.0 * uLeadingEstimate)
        let vRoot = -vCubicEstimate / (4.0 * vLeadingEstimate)
        guard uRoot.isFinite,
              vRoot.isFinite,
              uRoot >= 0.0,
              uRoot <= 1.0,
              vRoot >= 0.0,
              vRoot <= 1.0 else {
            return nil
        }

        for vPower in 0...4 {
            for uPower in 0...4 {
                var expected: [Double] = [0.0]
                if vPower == 0 {
                    expected = exactAdd(
                        expected,
                        quarticPowerCoefficient(
                            leading: uLeading,
                            root: uRoot,
                            power: uPower
                        )
                    )
                }
                if uPower == 0 {
                    expected = exactAdd(
                        expected,
                        quarticPowerCoefficient(
                            leading: vLeading,
                            root: vRoot,
                            power: vPower
                        )
                    )
                }
                guard exactSign(exactSubtract(
                    power[vPower][uPower],
                    expected
                )) == .zero else {
                    return nil
                }
            }
        }
        return Point2D(x: uRoot, y: vRoot)
    }

    private static func powerCoefficients(
        bernsteinControlExpansions: [[[Double]]]
    ) -> [[[Double]]] {
        (0...4).map { vPower in
            (0...4).map { uPower in
                var coefficient: [Double] = [0.0]
                for vIndex in 0...vPower {
                    for uIndex in 0...uPower {
                        let sign = (vPower - vIndex + uPower - uIndex).isMultiple(of: 2)
                            ? 1.0
                            : -1.0
                        let scale = sign
                            * binomial(4, vPower)
                            * binomial(vPower, vIndex)
                            * binomial(4, uPower)
                            * binomial(uPower, uIndex)
                        coefficient = exactAdd(
                            coefficient,
                            exactMultiply(
                                bernsteinControlExpansions[vIndex][uIndex],
                                [scale]
                            )
                        )
                    }
                }
                return coefficient
            }
        }
    }

    private static func quarticPowerCoefficient(
        leading: [Double],
        root: Double,
        power: Int
    ) -> [Double] {
        exactMultiply(
            exactMultiply(leading, [binomial(4, power)]),
            exactPower(-root, exponent: 4 - power)
        )
    }

    private static func exactPower(_ value: Double, exponent: Int) -> [Double] {
        guard exponent > 0 else { return [1.0] }
        return (0..<exponent).reduce([1.0]) { result, _ in
            exactMultiply(result, [value])
        }
    }

    private static func binomial(_ degree: Int, _ index: Int) -> Double {
        let reducedIndex = min(index, degree - index)
        guard reducedIndex > 0 else { return 1.0 }
        return (1...reducedIndex).reduce(1.0) { result, step in
            result * Double(degree - reducedIndex + step) / Double(step)
        }
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
        for vIndex in surface.controlPoints.indices {
            let vFraction = Double(vIndex) / Double(surface.vDegree)
            for uIndex in surface.controlPoints[vIndex].indices {
                let uFraction = Double(uIndex) / Double(surface.uDegree)
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
                row.append(exactTripleProduct(
                    planeFrame.exactU,
                    planeFrame.exactV,
                    exactDifference(point, planeFrame.origin)
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
                message: "A quartic tangency certificate requires closed surface domains."
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
                message: "A quartic tangency plane frame is singular."
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
                message: "A quartic tangency certificate witness failed plane residual verification."
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

    private static func estimate(_ value: [Double]) -> Double {
        value.reduce(0.0, +)
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
}
