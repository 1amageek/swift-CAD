import CADCore

struct ExactPlaneHeightFieldContext: Sendable {
    struct Witness: Sendable {
        let point: Point3D
        let firstParameter: SurfaceParameterProjection
        let secondParameter: SurfaceParameterProjection
    }

    let surface: BSplineSurface3D
    let origin: Point3D
    let u: Vector3D
    let v: Vector3D

    private let exactU: ExactExpansionArithmetic.Vector3
    private let exactV: ExactExpansionArithmetic.Vector3

    init?(surface: BSplineSurface3D) {
        guard Self.isSingleSpan(surface),
              Self.hasConstantWeights(surface),
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
        let exactU = ExactExpansionArithmetic.difference(uEnd, origin)
        let exactV = ExactExpansionArithmetic.difference(vEnd, origin)
        let metricDeterminant = ExactExpansionArithmetic.subtract(
            ExactExpansionArithmetic.multiply(
                ExactExpansionArithmetic.dot(exactU, exactU),
                ExactExpansionArithmetic.dot(exactV, exactV)
            ),
            ExactExpansionArithmetic.multiply(
                ExactExpansionArithmetic.dot(exactU, exactV),
                ExactExpansionArithmetic.dot(exactU, exactV)
            )
        )
        guard ExactExpansionArithmetic.sign(metricDeterminant) == .positive else {
            return nil
        }
        for vIndex in surface.controlPoints.indices {
            let vFraction = Double(vIndex) / Double(surface.vDegree)
            for uIndex in surface.controlPoints[vIndex].indices {
                let uFraction = Double(uIndex) / Double(surface.uDegree)
                let offset = ExactExpansionArithmetic.offset(
                    surface.controlPoints[vIndex][uIndex],
                    from: origin,
                    exactU: exactU,
                    uFraction: uFraction,
                    exactV: exactV,
                    vFraction: vFraction
                )
                guard ExactExpansionArithmetic.isZero(offset) else {
                    return nil
                }
            }
        }
        self.surface = surface
        self.origin = origin
        self.u = u
        self.v = v
        self.exactU = exactU
        self.exactV = exactV
    }

    func exactHeightControls(
        for heightSurface: BSplineSurface3D
    ) -> [[[Double]]]? {
        guard let firstRow = heightSurface.controlPoints.first,
              let lastRow = heightSurface.controlPoints.last,
              let heightOrigin = firstRow.first,
              let heightUEnd = firstRow.last,
              let heightVEnd = lastRow.first else {
            return nil
        }
        let heightExactU = ExactExpansionArithmetic.difference(
            heightUEnd,
            heightOrigin
        )
        let heightExactV = ExactExpansionArithmetic.difference(
            heightVEnd,
            heightOrigin
        )
        let projectedDeterminant = ExactExpansionArithmetic.subtract(
            ExactExpansionArithmetic.multiply(
                ExactExpansionArithmetic.dot(heightExactU, exactU),
                ExactExpansionArithmetic.dot(heightExactV, exactV)
            ),
            ExactExpansionArithmetic.multiply(
                ExactExpansionArithmetic.dot(heightExactU, exactV),
                ExactExpansionArithmetic.dot(heightExactV, exactU)
            )
        )
        guard ExactExpansionArithmetic.sign(projectedDeterminant) != .zero else {
            return nil
        }

        var result: [[[Double]]] = []
        result.reserveCapacity(heightSurface.controlPoints.count)
        for vIndex in heightSurface.controlPoints.indices {
            let vFraction = Double(vIndex) / Double(heightSurface.vDegree)
            var row: [[Double]] = []
            row.reserveCapacity(heightSurface.controlPoints[vIndex].count)
            for uIndex in heightSurface.controlPoints[vIndex].indices {
                let point = heightSurface.controlPoints[vIndex][uIndex]
                let uFraction = Double(uIndex) / Double(heightSurface.uDegree)
                let affineResidual = ExactExpansionArithmetic.offset(
                    point,
                    from: heightOrigin,
                    exactU: heightExactU,
                    uFraction: uFraction,
                    exactV: heightExactV,
                    vFraction: vFraction
                )
                guard ExactExpansionArithmetic.sign(
                    ExactExpansionArithmetic.dot(affineResidual, exactU)
                ) == .zero,
                ExactExpansionArithmetic.sign(
                    ExactExpansionArithmetic.dot(affineResidual, exactV)
                ) == .zero else {
                    return nil
                }
                row.append(ExactExpansionArithmetic.tripleProduct(
                    exactU,
                    exactV,
                    ExactExpansionArithmetic.difference(point, origin)
                ))
            }
            result.append(row)
        }
        return result
    }

    func verifiedWitness(
        on heightSurface: BSplineSurface3D,
        normalized: Point2D,
        planeIsFirst: Bool,
        certificateName: String,
        tolerance: ModelingTolerance
    ) throws -> Witness {
        guard case let .closed(heightULower, heightUUpper) = heightSurface.uDomain,
              case let .closed(heightVLower, heightVUpper) = heightSurface.vDomain,
              case let .closed(planeULower, planeUUpper) = surface.uDomain,
              case let .closed(planeVLower, planeVUpper) = surface.vDomain else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "An exact \(certificateName) certificate requires closed surface domains."
            )
        }
        let heightU = heightULower
            + (heightUUpper - heightULower) * normalized.x
        let heightV = heightVLower
            + (heightVUpper - heightVLower) * normalized.y
        let point = try heightSurface.point(
            u: heightU,
            v: heightV,
            tolerance: tolerance
        )
        let relative = point - origin
        let metricUU = u.dot(u)
        let metricUV = u.dot(v)
        let metricVV = v.dot(v)
        let determinant = metricUU * metricVV - metricUV * metricUV
        guard determinant.isFinite, determinant > 0.0 else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                tolerance: tolerance,
                message: "An exact \(certificateName) plane frame is singular."
            )
        }
        let rightU = relative.dot(u)
        let rightV = relative.dot(v)
        let normalizedPlaneU = (
            rightU * metricVV - rightV * metricUV
        ) / determinant
        let normalizedPlaneV = (
            rightV * metricUU - rightU * metricUV
        ) / determinant
        let planeU = planeULower
            + (planeUUpper - planeULower) * normalizedPlaneU
        let planeV = planeVLower
            + (planeVUpper - planeVLower) * normalizedPlaneV
        let planePoint = try surface.point(
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
                message: "An exact \(certificateName) witness failed plane residual verification."
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

    static func isSingleSpan(_ surface: BSplineSurface3D) -> Bool {
        surface.controlPoints.count == surface.vDegree + 1
            && surface.controlPoints.allSatisfy {
                $0.count == surface.uDegree + 1
            }
            && isSingleSpan(knots: surface.uKnots, degree: surface.uDegree)
            && isSingleSpan(knots: surface.vKnots, degree: surface.vDegree)
    }

    static func hasConstantWeights(_ surface: BSplineSurface3D) -> Bool {
        guard let reference = surface.weights.first?.first,
              reference.isFinite,
              reference > 0.0 else {
            return false
        }
        return surface.weights.flatMap { $0 }.allSatisfy {
            $0.isFinite && $0 > 0.0 && $0 == reference
        }
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
}
