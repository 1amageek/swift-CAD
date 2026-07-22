import CADCore

struct RationalBezierSurfaceDifferentialBounds: Sendable {
    let tangentUNumerator: IntervalVector3DBounds
    let tangentVNumerator: IntervalVector3DBounds
    let normalNumerator: IntervalVector3DBounds

    init(patch: RationalBezierSurfacePatch3D) {
        let homogeneous = patch.controlPoints.indices.map { vIndex in
            patch.controlPoints[vIndex].indices.map { uIndex in
                HomogeneousSurfacePoint(
                    point: patch.controlPoints[vIndex][uIndex],
                    weight: patch.weights[vIndex][uIndex]
                )
            }
        }
        let firstRow = homogeneous[0]
        let uDegree = firstRow.count - 1
        let vDegree = homogeneous.count - 1
        let uScale = Double(uDegree) / (patch.uUpper - patch.uLower)
        let vScale = Double(vDegree) / (patch.vUpper - patch.vLower)
        let derivativeU = homogeneous.map { row in
            (0..<uDegree).map { index in
                (row[index + 1] - row[index]) * uScale
            }
        }
        let derivativeV = (0..<vDegree).map { rowIndex in
            firstRow.indices.map { columnIndex in
                (homogeneous[rowIndex + 1][columnIndex]
                    - homogeneous[rowIndex][columnIndex]) * vScale
            }
        }
        let valueBounds = HomogeneousSurfaceBounds.enclosing(homogeneous.flatMap { $0 })
        let uBounds = HomogeneousSurfaceBounds.enclosing(derivativeU.flatMap { $0 })
        let vBounds = HomogeneousSurfaceBounds.enclosing(derivativeV.flatMap { $0 })
        tangentUNumerator = uBounds.xyz * valueBounds.weight
            - valueBounds.xyz * uBounds.weight
        tangentVNumerator = vBounds.xyz * valueBounds.weight
            - valueBounds.xyz * vBounds.weight
        normalNumerator = tangentUNumerator.cross(tangentVNumerator)
    }

    var representativeTangentU: Vector3D {
        tangentUNumerator.midpoint
    }

    var representativeTangentV: Vector3D {
        tangentVNumerator.midpoint
    }

    func tangentUProjection(along axis: Vector3D) -> OutwardScalarInterval {
        tangentUNumerator.dot(axis)
    }

    func tangentVProjection(along axis: Vector3D) -> OutwardScalarInterval {
        tangentVNumerator.dot(axis)
    }

    func normalProjection(along axis: Vector3D) -> OutwardScalarInterval {
        normalNumerator.dot(axis)
    }
}

struct OutwardScalarInterval: Sendable {
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

    static func enclosing(_ values: [Double]) -> OutwardScalarInterval {
        OutwardScalarInterval(
            lower: (values.min() ?? -.infinity).nextDown,
            upper: (values.max() ?? .infinity).nextUp
        )
    }

    static func + (
        lhs: OutwardScalarInterval,
        rhs: OutwardScalarInterval
    ) -> OutwardScalarInterval {
        OutwardScalarInterval(
            lower: (lhs.lower + rhs.lower).nextDown,
            upper: (lhs.upper + rhs.upper).nextUp
        )
    }

    static func - (
        lhs: OutwardScalarInterval,
        rhs: OutwardScalarInterval
    ) -> OutwardScalarInterval {
        OutwardScalarInterval(
            lower: (lhs.lower - rhs.upper).nextDown,
            upper: (lhs.upper - rhs.lower).nextUp
        )
    }

    static func * (
        lhs: OutwardScalarInterval,
        rhs: OutwardScalarInterval
    ) -> OutwardScalarInterval {
        let products = [
            lhs.lower * rhs.lower,
            lhs.lower * rhs.upper,
            lhs.upper * rhs.lower,
            lhs.upper * rhs.upper,
        ]
        return OutwardScalarInterval(
            lower: (products.min() ?? -.infinity).nextDown,
            upper: (products.max() ?? .infinity).nextUp
        )
    }

    var sign: Int? {
        if lower > 0.0 { return 1 }
        if upper < 0.0 { return -1 }
        return nil
    }

    var midpoint: Double {
        lower + (upper - lower) * 0.5
    }
}

struct IntervalVector3DBounds: Sendable {
    let x: OutwardScalarInterval
    let y: OutwardScalarInterval
    let z: OutwardScalarInterval

    static func - (
        lhs: IntervalVector3DBounds,
        rhs: IntervalVector3DBounds
    ) -> IntervalVector3DBounds {
        IntervalVector3DBounds(
            x: lhs.x - rhs.x,
            y: lhs.y - rhs.y,
            z: lhs.z - rhs.z
        )
    }

    static func * (
        lhs: IntervalVector3DBounds,
        rhs: OutwardScalarInterval
    ) -> IntervalVector3DBounds {
        IntervalVector3DBounds(
            x: lhs.x * rhs,
            y: lhs.y * rhs,
            z: lhs.z * rhs
        )
    }

    func cross(_ other: IntervalVector3DBounds) -> IntervalVector3DBounds {
        IntervalVector3DBounds(
            x: y * other.z - z * other.y,
            y: z * other.x - x * other.z,
            z: x * other.y - y * other.x
        )
    }

    func dot(_ vector: Vector3D) -> OutwardScalarInterval {
        x * OutwardScalarInterval(vector.x)
            + y * OutwardScalarInterval(vector.y)
            + z * OutwardScalarInterval(vector.z)
    }

    var midpoint: Vector3D {
        Vector3D(x: x.midpoint, y: y.midpoint, z: z.midpoint)
    }
}

private struct HomogeneousSurfacePoint: Sendable {
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

    static func - (
        lhs: HomogeneousSurfacePoint,
        rhs: HomogeneousSurfacePoint
    ) -> HomogeneousSurfacePoint {
        HomogeneousSurfacePoint(
            x: lhs.x - rhs.x,
            y: lhs.y - rhs.y,
            z: lhs.z - rhs.z,
            weight: lhs.weight - rhs.weight
        )
    }

    static func * (
        lhs: HomogeneousSurfacePoint,
        rhs: Double
    ) -> HomogeneousSurfacePoint {
        HomogeneousSurfacePoint(
            x: lhs.x * rhs,
            y: lhs.y * rhs,
            z: lhs.z * rhs,
            weight: lhs.weight * rhs
        )
    }
}

private struct HomogeneousSurfaceBounds: Sendable {
    let xyz: IntervalVector3DBounds
    let weight: OutwardScalarInterval

    static func enclosing(_ values: [HomogeneousSurfacePoint]) -> HomogeneousSurfaceBounds {
        HomogeneousSurfaceBounds(
            xyz: IntervalVector3DBounds(
                x: .enclosing(values.map(\.x)),
                y: .enclosing(values.map(\.y)),
                z: .enclosing(values.map(\.z))
            ),
            weight: .enclosing(values.map(\.weight))
        )
    }
}
