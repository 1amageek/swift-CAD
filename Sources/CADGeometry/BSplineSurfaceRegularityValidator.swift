import CADCore
import Foundation

public struct BSplineSurfaceRegularityValidator: Sendable {
    public var maximumSubdivisionDepth: Int
    public var maximumCellCount: Int

    public init(
        maximumSubdivisionDepth: Int = 18,
        maximumCellCount: Int = 262_144
    ) {
        self.maximumSubdivisionDepth = maximumSubdivisionDepth
        self.maximumCellCount = maximumCellCount
    }

    public func validate(
        _ surface: BSplineSurface3D,
        uDomain: ParameterDomain,
        vDomain: ParameterDomain,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        try surface.validate(tolerance: tolerance)
        guard maximumSubdivisionDepth >= 0, maximumCellCount > 0 else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "B-spline surface regularity limits must be positive."
            )
        }
        guard surface.uDegree > 0, surface.vDegree > 0,
              case let .closed(uLower, uUpper) = uDomain,
              case let .closed(vLower, vUpper) = vDomain,
              try surface.uDomain.containsSpan(from: uLower, to: uUpper, tolerance: tolerance),
              try surface.vDomain.containsSpan(from: vLower, to: vUpper, tolerance: tolerance) else {
            throw KernelError(
                phase: .geometry,
                code: .singularGeometry,
                tolerance: tolerance,
                message: "A regular B-spline surface requires positive degrees and contained finite parameter domains."
            )
        }

        let parameterTolerance = max(
            tolerance.relative * max(abs(uLower), abs(uUpper), abs(vLower), abs(vUpper), 1.0),
            Double.ulpOfOne * 256.0
        )
        let patches = try BSplineSurfaceBezierDecomposer()
            .surfacePatches(surface: surface, tolerance: tolerance)
            .compactMap { patch -> RationalBezierSurfacePatch3D? in
                let clippedULower = max(patch.uLower, uLower)
                let clippedUUpper = min(patch.uUpper, uUpper)
                let clippedVLower = max(patch.vLower, vLower)
                let clippedVUpper = min(patch.vUpper, vUpper)
                guard clippedUUpper - clippedULower > parameterTolerance,
                      clippedVUpper - clippedVLower > parameterTolerance else {
                    return nil
                }
                return try patch.trimmed(
                    uFrom: clippedULower,
                    uTo: clippedUUpper,
                    vFrom: clippedVLower,
                    vTo: clippedVUpper,
                    tolerance: tolerance
                )
            }
        guard patches.isEmpty == false else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "The requested B-spline surface domain contains no non-degenerate knot span."
            )
        }

        var pending = patches.map { Cell(patch: $0, depth: 0) }
        var visitedCellCount = 0
        while let cell = pending.popLast() {
            visitedCellCount += 1
            guard visitedCellCount <= maximumCellCount else {
                throw resourceLimit(
                    residual: Double(visitedCellCount),
                    tolerance: tolerance,
                    message: "B-spline surface regularity exhausted its certified cell budget."
                )
            }
            if try certificate(for: cell.patch, tolerance: tolerance).isRegular {
                continue
            }
            try rejectSampledSingularity(
                in: cell.patch,
                surface: surface,
                tolerance: tolerance
            )
            guard cell.depth < maximumSubdivisionDepth else {
                throw resourceLimit(
                    residual: Double(cell.depth),
                    tolerance: tolerance,
                    message: "B-spline surface regularity could not certify a cell within the subdivision limit."
                )
            }
            pending.append(contentsOf: try cell.patch.subdivided().map {
                Cell(patch: $0, depth: cell.depth + 1)
            })
        }
    }

    private struct Cell: Sendable {
        let patch: RationalBezierSurfacePatch3D
        let depth: Int
    }

    private struct Certificate: Sendable {
        let isRegular: Bool
    }

    private func certificate(
        for patch: RationalBezierSurfacePatch3D,
        tolerance: ModelingTolerance
    ) throws -> Certificate {
        let homogeneous = patch.controlPoints.indices.map { vIndex in
            patch.controlPoints[vIndex].indices.map { uIndex in
                HomogeneousPoint(
                    point: patch.controlPoints[vIndex][uIndex],
                    weight: patch.weights[vIndex][uIndex]
                )
            }
        }
        guard let firstRow = homogeneous.first,
              homogeneous.count > 1,
              firstRow.count > 1 else {
            return Certificate(isRegular: false)
        }
        let uSpan = patch.uUpper - patch.uLower
        let vSpan = patch.vUpper - patch.vLower
        guard uSpan.isFinite, uSpan > 0.0, vSpan.isFinite, vSpan > 0.0 else {
            return Certificate(isRegular: false)
        }
        let uDegree = firstRow.count - 1
        let vDegree = homogeneous.count - 1
        let derivativeU = homogeneous.map { row in
            (0..<uDegree).map { index in
                (row[index + 1] - row[index]) * (Double(uDegree) / uSpan)
            }
        }
        let derivativeV = (0..<vDegree).map { rowIndex in
            firstRow.indices.map { columnIndex in
                (homogeneous[rowIndex + 1][columnIndex] - homogeneous[rowIndex][columnIndex])
                    * (Double(vDegree) / vSpan)
            }
        }
        let valueBounds = HomogeneousBounds.enclosing(homogeneous.flatMap { $0 })
        let uBounds = HomogeneousBounds.enclosing(derivativeU.flatMap { $0 })
        let vBounds = HomogeneousBounds.enclosing(derivativeV.flatMap { $0 })
        guard valueBounds.weight.lower > 0.0 else {
            return Certificate(isRegular: false)
        }
        let pointNumerator = valueBounds.xyz
        let tangentUNumerator = uBounds.xyz * valueBounds.weight
            - pointNumerator * uBounds.weight
        let tangentVNumerator = vBounds.xyz * valueBounds.weight
            - pointNumerator * vBounds.weight
        let normalNumerator = tangentUNumerator.cross(tangentVNumerator)
        let maximumWeight = valueBounds.weight.upper.nextUp
        let maximumWeightSquared = (maximumWeight * maximumWeight).nextUp
        let tangentULower = max(
            0.0,
            (tangentUNumerator.lengthLowerBound / maximumWeightSquared).nextDown
        )
        let tangentVLower = max(
            0.0,
            (tangentVNumerator.lengthLowerBound / maximumWeightSquared).nextDown
        )
        let denominator = (
            tangentUNumerator.lengthUpperBound
                * tangentVNumerator.lengthUpperBound
        ).nextUp
        let angularLower = denominator > 0.0
            ? max(0.0, (normalNumerator.lengthLowerBound / denominator).nextDown)
            : 0.0
        let angularTolerance = max(
            sin(min(tolerance.angle, Double.pi * 0.5)),
            tolerance.relative,
            Double.ulpOfOne * 256.0
        )
        return Certificate(
            isRegular: tangentULower > tolerance.distance
                && tangentVLower > tolerance.distance
                && angularLower > angularTolerance
        )
    }

    private func rejectSampledSingularity(
        in patch: RationalBezierSurfacePatch3D,
        surface: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws {
        let u = patch.uLower + (patch.uUpper - patch.uLower) * 0.5
        let v = patch.vLower + (patch.vUpper - patch.vLower) * 0.5
        do {
            _ = try surface.normal(u: u, v: v, tolerance: tolerance)
        } catch let error as KernelError where error.code == .singularSystem {
            throw KernelError(
                phase: .geometry,
                code: .singularGeometry,
                residual: error.residual,
                tolerance: tolerance,
                message: "The B-spline surface contains a singular parameter in the retained domain."
            )
        }
    }

    private func resourceLimit(
        residual: Double,
        tolerance: ModelingTolerance,
        message: String
    ) -> KernelError {
        KernelError(
            phase: .geometry,
            code: .resourceLimitExceeded,
            residual: residual,
            tolerance: tolerance,
            message: message
        )
    }

    private struct HomogeneousPoint: Sendable {
        let x: Double
        let y: Double
        let z: Double
        let weight: Double

        init(point: Point3D, weight: Double) {
            x = point.x * weight
            y = point.y * weight
            z = point.z * weight
            self.weight = weight
        }

        private init(x: Double, y: Double, z: Double, weight: Double) {
            self.x = x
            self.y = y
            self.z = z
            self.weight = weight
        }

        static func - (lhs: HomogeneousPoint, rhs: HomogeneousPoint) -> HomogeneousPoint {
            HomogeneousPoint(
                x: lhs.x - rhs.x,
                y: lhs.y - rhs.y,
                z: lhs.z - rhs.z,
                weight: lhs.weight - rhs.weight
            )
        }

        static func * (lhs: HomogeneousPoint, rhs: Double) -> HomogeneousPoint {
            HomogeneousPoint(
                x: lhs.x * rhs,
                y: lhs.y * rhs,
                z: lhs.z * rhs,
                weight: lhs.weight * rhs
            )
        }
    }

    private struct HomogeneousBounds: Sendable {
        let xyz: IntervalVector
        let weight: OutwardInterval

        static func enclosing(_ values: [HomogeneousPoint]) -> HomogeneousBounds {
            HomogeneousBounds(
                xyz: IntervalVector(
                    x: .enclosing(values.map(\.x)),
                    y: .enclosing(values.map(\.y)),
                    z: .enclosing(values.map(\.z))
                ),
                weight: .enclosing(values.map(\.weight))
            )
        }
    }

    private struct OutwardInterval: Sendable {
        let lower: Double
        let upper: Double

        static func enclosing(_ values: [Double]) -> OutwardInterval {
            OutwardInterval(
                lower: (values.min() ?? -.infinity).nextDown,
                upper: (values.max() ?? .infinity).nextUp
            )
        }

        static func - (lhs: OutwardInterval, rhs: OutwardInterval) -> OutwardInterval {
            OutwardInterval(
                lower: (lhs.lower - rhs.upper).nextDown,
                upper: (lhs.upper - rhs.lower).nextUp
            )
        }

        static func * (lhs: OutwardInterval, rhs: OutwardInterval) -> OutwardInterval {
            let products = [
                lhs.lower * rhs.lower,
                lhs.lower * rhs.upper,
                lhs.upper * rhs.lower,
                lhs.upper * rhs.upper,
            ]
            return OutwardInterval(
                lower: (products.min() ?? -.infinity).nextDown,
                upper: (products.max() ?? .infinity).nextUp
            )
        }

        var absoluteLowerBound: Double {
            if lower > 0.0 {
                return lower.nextDown
            }
            if upper < 0.0 {
                return (-upper).nextDown
            }
            return 0.0
        }

        var absoluteUpperBound: Double {
            max(abs(lower), abs(upper)).nextUp
        }
    }

    private struct IntervalVector: Sendable {
        let x: OutwardInterval
        let y: OutwardInterval
        let z: OutwardInterval

        static func - (lhs: IntervalVector, rhs: IntervalVector) -> IntervalVector {
            IntervalVector(x: lhs.x - rhs.x, y: lhs.y - rhs.y, z: lhs.z - rhs.z)
        }

        static func * (lhs: IntervalVector, rhs: OutwardInterval) -> IntervalVector {
            IntervalVector(x: lhs.x * rhs, y: lhs.y * rhs, z: lhs.z * rhs)
        }

        func cross(_ other: IntervalVector) -> IntervalVector {
            IntervalVector(
                x: y * other.z - z * other.y,
                y: z * other.x - x * other.z,
                z: x * other.y - y * other.x
            )
        }

        var lengthLowerBound: Double {
            max(x.absoluteLowerBound, y.absoluteLowerBound, z.absoluteLowerBound)
        }

        var lengthUpperBound: Double {
            let xUpper = x.absoluteUpperBound
            let yUpper = y.absoluteUpperBound
            let zUpper = z.absoluteUpperBound
            let xSquared = (xUpper * xUpper).nextUp
            let ySquared = (yUpper * yUpper).nextUp
            let zSquared = (zUpper * zUpper).nextUp
            let xySquared = (xSquared + ySquared).nextUp
            return sqrt((xySquared + zSquared).nextUp).nextUp
        }
    }
}
