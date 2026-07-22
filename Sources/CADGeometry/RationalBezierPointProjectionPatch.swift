import CADCore
import Foundation

struct RationalBezierPointProjectionPatch: Sendable {
    private struct OutwardInterval: Sendable {
        let lower: Double
        let upper: Double

        init(_ value: Double) {
            lower = value.nextDown
            upper = value.nextUp
        }

        private init(lower: Double, upper: Double) {
            self.lower = lower
            self.upper = upper
        }

        static func + (lhs: OutwardInterval, rhs: OutwardInterval) -> OutwardInterval {
            OutwardInterval(
                lower: (lhs.lower + rhs.lower).nextDown,
                upper: (lhs.upper + rhs.upper).nextUp
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

        static func / (lhs: OutwardInterval, rhs: OutwardInterval) -> OutwardInterval {
            guard rhs.lower > 0.0 else {
                return OutwardInterval(lower: -.infinity, upper: .infinity)
            }
            return lhs * OutwardInterval(
                lower: (1.0 / rhs.upper).nextDown,
                upper: (1.0 / rhs.lower).nextUp
            )
        }
    }

    private struct HomogeneousPoint: Sendable {
        let x: OutwardInterval
        let y: OutwardInterval
        let z: OutwardInterval
        let weight: OutwardInterval

        init(point: Point3D, weight: Double) {
            let weightInterval = OutwardInterval(weight)
            x = OutwardInterval(point.x) * weightInterval
            y = OutwardInterval(point.y) * weightInterval
            z = OutwardInterval(point.z) * weightInterval
            self.weight = weightInterval
        }

        private init(
            x: OutwardInterval,
            y: OutwardInterval,
            z: OutwardInterval,
            weight: OutwardInterval
        ) {
            self.x = x
            self.y = y
            self.z = z
            self.weight = weight
        }

        func midpoint(with other: HomogeneousPoint) -> HomogeneousPoint {
            let half = OutwardInterval(0.5)
            return HomogeneousPoint(
                x: (x + other.x) * half,
                y: (y + other.y) * half,
                z: (z + other.z) * half,
                weight: (weight + other.weight) * half
            )
        }

        func cartesianBounds(tolerance: ModelingTolerance) throws -> (
            x: OutwardInterval,
            y: OutwardInterval,
            z: OutwardInterval
        ) {
            guard weight.lower.isFinite,
                  weight.upper.isFinite,
                  weight.lower > 0.0 else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularSystem,
                    residual: weight.lower,
                    tolerance: tolerance,
                    message: "Rational Bezier projection could not bound a positive homogeneous weight."
                )
            }
            return (x / weight, y / weight, z / weight)
        }
    }

    private let controlNet: [[HomogeneousPoint]]
    let uLower: Double
    let uUpper: Double
    let vLower: Double
    let vUpper: Double

    init(patch: RationalBezierSurfacePatch3D) {
        controlNet = patch.controlPoints.indices.map { vIndex in
            patch.controlPoints[vIndex].indices.map { uIndex in
                HomogeneousPoint(
                    point: patch.controlPoints[vIndex][uIndex],
                    weight: patch.weights[vIndex][uIndex]
                )
            }
        }
        uLower = patch.uLower
        uUpper = patch.uUpper
        vLower = patch.vLower
        vUpper = patch.vUpper
    }

    private init(
        controlNet: [[HomogeneousPoint]],
        uLower: Double,
        uUpper: Double,
        vLower: Double,
        vUpper: Double
    ) {
        self.controlNet = controlNet
        self.uLower = uLower
        self.uUpper = uUpper
        self.vLower = vLower
        self.vUpper = vUpper
    }

    func boundingBox(tolerance: ModelingTolerance) throws -> BoundingBox3D {
        var minimumX = Double.infinity
        var minimumY = Double.infinity
        var minimumZ = Double.infinity
        var maximumX = -Double.infinity
        var maximumY = -Double.infinity
        var maximumZ = -Double.infinity
        for control in controlNet.flatMap({ $0 }) {
            let bounds = try control.cartesianBounds(tolerance: tolerance)
            minimumX = min(minimumX, bounds.x.lower)
            minimumY = min(minimumY, bounds.y.lower)
            minimumZ = min(minimumZ, bounds.z.lower)
            maximumX = max(maximumX, bounds.x.upper)
            maximumY = max(maximumY, bounds.y.upper)
            maximumZ = max(maximumZ, bounds.z.upper)
        }
        return try BoundingBox3D(
            minimum: Point3D(x: minimumX, y: minimumY, z: minimumZ),
            maximum: Point3D(x: maximumX, y: maximumY, z: maximumZ)
        )
    }

    func subdivided() -> [RationalBezierPointProjectionPatch] {
        let quadrants = subdivided(controlNet: controlNet)
        let uMiddle = uLower + (uUpper - uLower) * 0.5
        let vMiddle = vLower + (vUpper - vLower) * 0.5
        let bounds = [
            (uLower, uMiddle, vLower, vMiddle),
            (uMiddle, uUpper, vLower, vMiddle),
            (uLower, uMiddle, vMiddle, vUpper),
            (uMiddle, uUpper, vMiddle, vUpper),
        ]
        return bounds.indices.map { index in
            RationalBezierPointProjectionPatch(
                controlNet: quadrants[index],
                uLower: bounds[index].0,
                uUpper: bounds[index].1,
                vLower: bounds[index].2,
                vUpper: bounds[index].3
            )
        }
    }

    private func subdivided(
        controlNet: [[HomogeneousPoint]]
    ) -> [[[HomogeneousPoint]]] {
        var uLowerRows: [[HomogeneousPoint]] = []
        var uUpperRows: [[HomogeneousPoint]] = []
        for row in controlNet {
            let halves = split(row)
            uLowerRows.append(halves.lower)
            uUpperRows.append(halves.upper)
        }
        let lowerUHalves = splitColumns(uLowerRows)
        let upperUHalves = splitColumns(uUpperRows)
        return [
            lowerUHalves.lower,
            upperUHalves.lower,
            lowerUHalves.upper,
            upperUHalves.upper,
        ]
    }

    private func splitColumns(
        _ values: [[HomogeneousPoint]]
    ) -> (lower: [[HomogeneousPoint]], upper: [[HomogeneousPoint]]) {
        guard let firstRow = values.first else { return ([], []) }
        var lowerColumns: [[HomogeneousPoint]] = []
        var upperColumns: [[HomogeneousPoint]] = []
        for columnIndex in firstRow.indices {
            let halves = split(values.map { $0[columnIndex] })
            lowerColumns.append(halves.lower)
            upperColumns.append(halves.upper)
        }
        return (
            values.indices.map { rowIndex in lowerColumns.map { $0[rowIndex] } },
            values.indices.map { rowIndex in upperColumns.map { $0[rowIndex] } }
        )
    }

    private func split(
        _ values: [HomogeneousPoint]
    ) -> (lower: [HomogeneousPoint], upper: [HomogeneousPoint]) {
        guard values.count > 1 else { return (values, values) }
        var levels = [values]
        while let previous = levels.last, previous.count > 1 {
            levels.append((0..<(previous.count - 1)).map { index in
                previous[index].midpoint(with: previous[index + 1])
            })
        }
        return (
            levels.map { $0[0] },
            levels.reversed().map { $0[$0.count - 1] }
        )
    }
}
