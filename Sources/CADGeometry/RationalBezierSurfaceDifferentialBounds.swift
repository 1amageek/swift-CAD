import CADCore
import Foundation

private let maximumCertifiedBernsteinProductDegree = 16

struct RationalBezierSurfaceDifferentialBounds: Sendable {
    let tangentUNumerator: IntervalVector3DBounds
    let tangentVNumerator: IntervalVector3DBounds
    let normalNumerator: IntervalVector3DBounds

    init(patch: RationalBezierSurfacePatch3D) {
        if let exactBounds = ExactBernsteinDifferentialBounds(patch: patch) {
            tangentUNumerator = exactBounds.tangentUNumerator
            tangentVNumerator = exactBounds.tangentVNumerator
            normalNumerator = exactBounds.normalNumerator
            return
        }

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

    static func enclosing(_ values: [OutwardScalarInterval]) -> OutwardScalarInterval {
        OutwardScalarInterval(
            lower: values.map(\.lower).min() ?? -.infinity,
            upper: values.map(\.upper).max() ?? .infinity
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

/// Retains the algebraic correlation between homogeneous surface values and
/// derivatives by forming their exact Bernstein product coefficient nets.
/// The coefficient intervals are outward-rounded, so their convex hulls are
/// certified bounds for the rational tangent and normal numerators.
private struct ExactBernsteinDifferentialBounds {
    let tangentUNumerator: IntervalVector3DBounds
    let tangentVNumerator: IntervalVector3DBounds
    let normalNumerator: IntervalVector3DBounds

    init?(patch: RationalBezierSurfacePatch3D) {
        guard let uControlPointCount = patch.controlPoints.first?.count,
              patch.controlPoints.count > 1,
              uControlPointCount > 1 else {
            return nil
        }
        let uDegree = uControlPointCount - 1
        let vDegree = patch.controlPoints.count - 1
        let maximumExactSurfaceDegree = (maximumCertifiedBernsteinProductDegree + 1) / 4
        guard uDegree <= maximumExactSurfaceDegree,
              vDegree <= maximumExactSurfaceDegree else {
            return nil
        }
        guard let homogeneous = BernsteinVector4Surface(patch: patch),
              let derivativeU = homogeneous.derivativeU(parameterSpan: patch.uUpper - patch.uLower),
              let derivativeV = homogeneous.derivativeV(parameterSpan: patch.vUpper - patch.vLower),
              let derivativeUWeighted = derivativeU.xyz.multiplied(by: homogeneous.weight),
              let valueTimesWeightDerivativeU = homogeneous.xyz.multiplied(by: derivativeU.weight),
              let tangentU = derivativeUWeighted.subtracting(valueTimesWeightDerivativeU),
              let derivativeVWeighted = derivativeV.xyz.multiplied(by: homogeneous.weight),
              let valueTimesWeightDerivativeV = homogeneous.xyz.multiplied(by: derivativeV.weight),
              let tangentV = derivativeVWeighted.subtracting(valueTimesWeightDerivativeV),
              let normal = tangentU.cross(tangentV) else {
            return nil
        }
        tangentUNumerator = tangentU.enclosure
        tangentVNumerator = tangentV.enclosure
        normalNumerator = normal.enclosure
    }
}

private struct BernsteinVector4Surface {
    let xyz: BernsteinVector3Surface
    let weight: BernsteinScalarSurface

    init?(patch: RationalBezierSurfacePatch3D) {
        guard patch.controlPoints.isEmpty == false,
              patch.controlPoints.count == patch.weights.count,
              let controlPointCount = patch.controlPoints.first?.count,
              controlPointCount > 0,
              patch.controlPoints.indices.allSatisfy({
                  patch.controlPoints[$0].count == controlPointCount
                      && patch.weights[$0].count == controlPointCount
              }) else {
            return nil
        }
        var x: [[OutwardScalarInterval]] = []
        var y: [[OutwardScalarInterval]] = []
        var z: [[OutwardScalarInterval]] = []
        var weight: [[OutwardScalarInterval]] = []
        x.reserveCapacity(patch.controlPoints.count)
        y.reserveCapacity(patch.controlPoints.count)
        z.reserveCapacity(patch.controlPoints.count)
        weight.reserveCapacity(patch.controlPoints.count)
        for vIndex in patch.controlPoints.indices {
            var xRow: [OutwardScalarInterval] = []
            var yRow: [OutwardScalarInterval] = []
            var zRow: [OutwardScalarInterval] = []
            var weightRow: [OutwardScalarInterval] = []
            xRow.reserveCapacity(controlPointCount)
            yRow.reserveCapacity(controlPointCount)
            zRow.reserveCapacity(controlPointCount)
            weightRow.reserveCapacity(controlPointCount)
            for uIndex in patch.controlPoints[vIndex].indices {
                let point = patch.controlPoints[vIndex][uIndex]
                let scalarWeight = OutwardScalarInterval(patch.weights[vIndex][uIndex])
                xRow.append(OutwardScalarInterval(point.x) * scalarWeight)
                yRow.append(OutwardScalarInterval(point.y) * scalarWeight)
                zRow.append(OutwardScalarInterval(point.z) * scalarWeight)
                weightRow.append(scalarWeight)
            }
            x.append(xRow)
            y.append(yRow)
            z.append(zRow)
            weight.append(weightRow)
        }
        guard let xSurface = BernsteinScalarSurface(coefficients: x),
              let ySurface = BernsteinScalarSurface(coefficients: y),
              let zSurface = BernsteinScalarSurface(coefficients: z),
              let weightSurface = BernsteinScalarSurface(coefficients: weight) else {
            return nil
        }
        xyz = BernsteinVector3Surface(x: xSurface, y: ySurface, z: zSurface)
        self.weight = weightSurface
    }

    private init(xyz: BernsteinVector3Surface, weight: BernsteinScalarSurface) {
        self.xyz = xyz
        self.weight = weight
    }

    func derivativeU(parameterSpan: Double) -> BernsteinVector4Surface? {
        guard let xyz = xyz.derivativeU(parameterSpan: parameterSpan),
              let weight = weight.derivativeU(parameterSpan: parameterSpan) else {
            return nil
        }
        return BernsteinVector4Surface(xyz: xyz, weight: weight)
    }

    func derivativeV(parameterSpan: Double) -> BernsteinVector4Surface? {
        guard let xyz = xyz.derivativeV(parameterSpan: parameterSpan),
              let weight = weight.derivativeV(parameterSpan: parameterSpan) else {
            return nil
        }
        return BernsteinVector4Surface(xyz: xyz, weight: weight)
    }
}

private struct BernsteinVector3Surface {
    let x: BernsteinScalarSurface
    let y: BernsteinScalarSurface
    let z: BernsteinScalarSurface

    func derivativeU(parameterSpan: Double) -> BernsteinVector3Surface? {
        guard let x = x.derivativeU(parameterSpan: parameterSpan),
              let y = y.derivativeU(parameterSpan: parameterSpan),
              let z = z.derivativeU(parameterSpan: parameterSpan) else {
            return nil
        }
        return BernsteinVector3Surface(x: x, y: y, z: z)
    }

    func derivativeV(parameterSpan: Double) -> BernsteinVector3Surface? {
        guard let x = x.derivativeV(parameterSpan: parameterSpan),
              let y = y.derivativeV(parameterSpan: parameterSpan),
              let z = z.derivativeV(parameterSpan: parameterSpan) else {
            return nil
        }
        return BernsteinVector3Surface(x: x, y: y, z: z)
    }

    func multiplied(by scalar: BernsteinScalarSurface) -> BernsteinVector3Surface? {
        guard let x = x.multiplied(by: scalar),
              let y = y.multiplied(by: scalar),
              let z = z.multiplied(by: scalar) else {
            return nil
        }
        return BernsteinVector3Surface(x: x, y: y, z: z)
    }

    func subtracting(_ other: BernsteinVector3Surface) -> BernsteinVector3Surface? {
        guard let x = x.subtracting(other.x),
              let y = y.subtracting(other.y),
              let z = z.subtracting(other.z) else {
            return nil
        }
        return BernsteinVector3Surface(x: x, y: y, z: z)
    }

    func cross(_ other: BernsteinVector3Surface) -> BernsteinVector3Surface? {
        guard let yz = y.multiplied(by: other.z),
              let zy = z.multiplied(by: other.y),
              let zx = z.multiplied(by: other.x),
              let xz = x.multiplied(by: other.z),
              let xy = x.multiplied(by: other.y),
              let yx = y.multiplied(by: other.x),
              let xComponent = yz.subtracting(zy),
              let yComponent = zx.subtracting(xz),
              let zComponent = xy.subtracting(yx) else {
            return nil
        }
        return BernsteinVector3Surface(
            x: xComponent,
            y: yComponent,
            z: zComponent
        )
    }

    var enclosure: IntervalVector3DBounds {
        IntervalVector3DBounds(
            x: x.enclosure,
            y: y.enclosure,
            z: z.enclosure
        )
    }
}

private struct BernsteinScalarSurface {
    /// Exact Bernstein product coefficients are only used while every output
    /// degree remains small enough for exact integer binomial arithmetic.
    let coefficients: [[OutwardScalarInterval]]
    let uDegree: Int
    let vDegree: Int

    init?(coefficients: [[OutwardScalarInterval]]) {
        guard coefficients.isEmpty == false,
              let count = coefficients.first?.count,
              count > 0,
              coefficients.allSatisfy({ $0.count == count }) else {
            return nil
        }
        self.coefficients = coefficients
        uDegree = count - 1
        vDegree = coefficients.count - 1
    }

    func derivativeU(parameterSpan: Double) -> BernsteinScalarSurface? {
        guard uDegree > 0,
              parameterSpan.isFinite,
              parameterSpan > 0.0 else {
            return nil
        }
        let scale = OutwardScalarInterval(Double(uDegree) / parameterSpan)
        let result = coefficients.map { row in
            (0..<uDegree).map { index in
                (row[index + 1] - row[index]) * scale
            }
        }
        return BernsteinScalarSurface(coefficients: result)
    }

    func derivativeV(parameterSpan: Double) -> BernsteinScalarSurface? {
        guard vDegree > 0,
              parameterSpan.isFinite,
              parameterSpan > 0.0 else {
            return nil
        }
        let scale = OutwardScalarInterval(Double(vDegree) / parameterSpan)
        let result = (0..<vDegree).map { rowIndex in
            coefficients[rowIndex].indices.map { columnIndex in
                (coefficients[rowIndex + 1][columnIndex]
                    - coefficients[rowIndex][columnIndex]) * scale
            }
        }
        return BernsteinScalarSurface(coefficients: result)
    }

    func subtracting(_ other: BernsteinScalarSurface) -> BernsteinScalarSurface? {
        guard uDegree == other.uDegree, vDegree == other.vDegree else {
            return nil
        }
        let result = coefficients.indices.map { vIndex in
            coefficients[vIndex].indices.map { uIndex in
                coefficients[vIndex][uIndex] - other.coefficients[vIndex][uIndex]
            }
        }
        return BernsteinScalarSurface(coefficients: result)
    }

    func multiplied(by other: BernsteinScalarSurface) -> BernsteinScalarSurface? {
        let outputUDegree = uDegree + other.uDegree
        let outputVDegree = vDegree + other.vDegree
        guard outputUDegree <= maximumCertifiedBernsteinProductDegree,
              outputVDegree <= maximumCertifiedBernsteinProductDegree else {
            return nil
        }
        var result = Array(
            repeating: Array(
                repeating: OutwardScalarInterval(0.0),
                count: outputUDegree + 1
            ),
            count: outputVDegree + 1
        )
        for outputV in 0...outputVDegree {
            let firstVLower = max(0, outputV - other.vDegree)
            let firstVUpper = min(vDegree, outputV)
            for outputU in 0...outputUDegree {
                let firstULower = max(0, outputU - other.uDegree)
                let firstUUpper = min(uDegree, outputU)
                var coefficient = OutwardScalarInterval(0.0)
                for firstV in firstVLower...firstVUpper {
                    let secondV = outputV - firstV
                    guard let vWeight = Self.productWeight(
                        firstDegree: vDegree,
                        firstIndex: firstV,
                        secondDegree: other.vDegree,
                        secondIndex: secondV,
                        outputDegree: outputVDegree,
                        outputIndex: outputV
                    ) else {
                        return nil
                    }
                    for firstU in firstULower...firstUUpper {
                        let secondU = outputU - firstU
                        guard let uWeight = Self.productWeight(
                            firstDegree: uDegree,
                            firstIndex: firstU,
                            secondDegree: other.uDegree,
                            secondIndex: secondU,
                            outputDegree: outputUDegree,
                            outputIndex: outputU
                        ) else {
                            return nil
                        }
                        coefficient = coefficient
                            + coefficients[firstV][firstU]
                            * other.coefficients[secondV][secondU]
                            * uWeight
                            * vWeight
                    }
                }
                result[outputV][outputU] = coefficient
            }
        }
        return BernsteinScalarSurface(coefficients: result)
    }

    var enclosure: OutwardScalarInterval {
        OutwardScalarInterval.enclosing(coefficients.flatMap { $0 })
    }

    private static func productWeight(
        firstDegree: Int,
        firstIndex: Int,
        secondDegree: Int,
        secondIndex: Int,
        outputDegree: Int,
        outputIndex: Int
    ) -> OutwardScalarInterval? {
        guard let first = binomial(firstDegree, firstIndex),
              let second = binomial(secondDegree, secondIndex),
              let output = binomial(outputDegree, outputIndex),
              output > 0 else {
            return nil
        }
        let numerator = first.multipliedReportingOverflow(by: second)
        guard numerator.overflow == false else {
            return nil
        }
        return OutwardScalarInterval(Double(numerator.partialValue) / Double(output))
    }

    private static func binomial(_ n: Int, _ k: Int) -> Int64? {
        guard n >= 0, k >= 0, k <= n else { return nil }
        let reducedK = min(k, n - k)
        var row = Array(repeating: Int64(0), count: reducedK + 1)
        row[0] = 1
        guard reducedK > 0 else { return 1 }
        for currentN in 1...n {
            let upper = min(currentN, reducedK)
            if upper == 0 { continue }
            for index in stride(from: upper, through: 1, by: -1) {
                let sum = row[index].addingReportingOverflow(row[index - 1])
                guard sum.overflow == false else { return nil }
                row[index] = sum.partialValue
            }
        }
        return row[reducedK]
    }
}
