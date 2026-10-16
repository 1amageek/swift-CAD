import CADCore
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

private let maximumCertifiedBernsteinProductDegree = 16

package struct RationalBezierSurfaceDifferentialBounds: Sendable {
    let tangentUNumerator: IntervalVector3DBounds
    let tangentVNumerator: IntervalVector3DBounds
    let normalNumerator: IntervalVector3DBounds

    static func outerBoundaries(of patch: RationalBezierSurfacePatch3D,
        uDomain: ParameterDomain, vDomain: ParameterDomain) -> Set<SurfaceParameterBoundary> {
        guard case let .closed(u0, u1) = uDomain, case let .closed(v0, v1) = vDomain else { return [] }
        var result: Set<SurfaceParameterBoundary> = []
        if patch.uLower == u0 { result.insert(.uLower) }
        if patch.uUpper == u1 { result.insert(.uUpper) }
        if patch.vLower == v0 { result.insert(.vLower) }
        if patch.vUpper == v1 { result.insert(.vUpper) }
        return result
    }

    /// Bounds tangent-plane deviation, not positional boundary continuity.
    /// A nil result is inconclusive and must not be classified as a sharp edge.
    package static func boundaryNormalSineBounds<A: ExactScalarAdmission & ~Copyable>(
        first: BSplineSurface3D,
        firstBoundary: SurfaceParameterBoundary,
        second: BSplineSurface3D,
        secondBoundary: SurfaceParameterBoundary,
        reverseSecond: Bool,
        tolerance: ModelingTolerance, using execution: inout A
    ) throws -> ScalarInterval? {
        try first.validate(tolerance: tolerance, using: &execution)
        try second.validate(tolerance: tolerance, using: &execution)
        func normal(_ surface: BSplineSurface3D, using execution: inout A) throws -> BernsteinVector3Surface? {
            guard surface.uControlPointCount == surface.uDegree + 1,
                  surface.vControlPointCount == surface.vDegree + 1,
                  case let .closed(u0, u1) = surface.uDomain,
                  case let .closed(v0, v1) = surface.vDomain,
                  surface.uKnots.prefix(surface.uDegree + 1).allSatisfy({ $0 == u0 }),
                  surface.uKnots.suffix(surface.uDegree + 1).allSatisfy({ $0 == u1 }),
                  surface.vKnots.prefix(surface.vDegree + 1).allSatisfy({ $0 == v0 }),
                  surface.vKnots.suffix(surface.vDegree + 1).allSatisfy({ $0 == v1 }) else { return nil }
            let patch = RationalBezierSurfacePatch3D(controlPoints: surface.controlPoints,
                weights: surface.weights, uLower: u0, uUpper: u1, vLower: v0, vUpper: v1)
            if surface.weights.allSatisfy({ $0.allSatisfy { $0 == 1 } }) {
                // Positive parameter scales cancel in the normalized normal.
                guard let homogeneous = try BernsteinVector4Surface(patch: patch, using: &execution),
                      let u = try homogeneous.xyz.derivativeU(parameterSpan: 1, using: &execution),
                      let v = try homogeneous.xyz.derivativeV(parameterSpan: 1, using: &execution) else { return nil }
                return try u.cross(v, using: &execution)
            }
            // Remove the common positive W factor before comparing normals:
            // (W*Pu-P*Wu) x (W*Pv-P*Wv)
            // = W * (W*(Pu x Pv) - Wv*(Pu x P) - Wu*(P x Pv)).
            // This preserves direction while avoiding unnecessary product degree.
            guard let h = try BernsteinVector4Surface(patch: patch, using: &execution),
                  let u = try h.derivativeU(parameterSpan: 1, using: &execution),
                  let v = try h.derivativeV(parameterSpan: 1, using: &execution),
                  let leading = try u.xyz.cross(v.xyz, using: &execution)?.multiplied(by: h.weight, using: &execution),
                  let first = try u.xyz.cross(h.xyz, using: &execution)?.multiplied(by: v.weight, using: &execution),
                  let second = try h.xyz.cross(v.xyz, using: &execution)?.multiplied(by: u.weight, using: &execution) else { return nil }
            return try leading.subtracting(first, using: &execution)?.subtracting(second, using: &execution)
        }
        guard let firstNormal = try normal(first, using: &execution)?.boundary(firstBoundary, reversed: false, using: &execution),
              let secondNormal = try normal(second, using: &execution)?.boundary(secondBoundary, reversed: reverseSecond, using: &execution),
              let cross = try firstNormal.cross(secondNormal, using: &execution) else { return nil }
        let a = try firstNormal.enclosure(using: &execution), b = try secondNormal.enclosure(using: &execution), c = try cross.enclosure(using: &execution)
        let denominator = OutwardScalarInterval(lower: a.lengthLowerBound, upper: a.lengthUpperBound)
            * OutwardScalarInterval(lower: b.lengthLowerBound, upper: b.lengthUpperBound)
        guard denominator.lower > 0,
              let ratio = OutwardScalarInterval(lower: c.lengthLowerBound, upper: c.lengthUpperBound)
                .divided(by: denominator), ratio.isFinite else { return nil }
        return try ScalarInterval(lower: max(0, ratio.lower), upper: min(1, ratio.upper))
    }

    package static func boundaryNormalSineBounds(first: BSplineSurface3D,
        firstBoundary: SurfaceParameterBoundary, second: BSplineSurface3D,
        secondBoundary: SurfaceParameterBoundary, reverseSecond: Bool,
        tolerance: ModelingTolerance) throws -> ScalarInterval? {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try boundaryNormalSineBounds(first: first, firstBoundary: firstBoundary,
            second: second, secondBoundary: secondBoundary, reverseSecond: reverseSecond,
            tolerance: tolerance, using: &execution)
    }

    init(originalTangentU: IntervalVector3DBounds, originalTangentV: IntervalVector3DBounds,
        originalNormal: IntervalVector3DBounds) {
        tangentUNumerator = originalTangentU; tangentVNumerator = originalTangentV
        normalNumerator = originalNormal
    }

    static func prepared<A: ExactScalarAdmission & ~Copyable>(patch: RationalBezierSurfacePatch3D,
        stationaryBoundaries: Set<SurfaceParameterBoundary> = [], using execution: inout A) throws -> Self {
        let fields = try prepare(patch: patch, stationaryBoundaries: stationaryBoundaries, using: &execution)
        try execution.checkpoint()
        return Self(fields: fields)
    }

    init(patch: RationalBezierSurfacePatch3D,
         stationaryBoundaries: Set<SurfaceParameterBoundary> = []) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        self = try Self.prepared(patch: patch, stationaryBoundaries: stationaryBoundaries, using: &execution)
    }
    private init(fields: (IntervalVector3DBounds, IntervalVector3DBounds, IntervalVector3DBounds)) {
        tangentUNumerator = fields.0; tangentVNumerator = fields.1; normalNumerator = fields.2
    }
    private static func prepare<A: ExactScalarAdmission & ~Copyable>(patch: RationalBezierSurfacePatch3D,
        stationaryBoundaries: Set<SurfaceParameterBoundary>, using execution: inout A) throws
        -> (IntervalVector3DBounds, IntervalVector3DBounds, IntervalVector3DBounds) {
        // Unit weights make the rational denominator identically one, including
        // interior subdivision cells without stationary boundary factors.
        try execution.checkpoint()
        for row in patch.weights {
            try execution.consumeWork(row.count)
        }
        if patch.weights.allSatisfy({ $0.allSatisfy { $0 == 1 } }),
           let h = try BernsteinVector4Surface(patch: patch, using: &execution),
           var u = try h.xyz.derivativeU(parameterSpan: patch.uUpper - patch.uLower, using: &execution),
           var v = try h.xyz.derivativeV(parameterSpan: patch.vUpper - patch.vLower, using: &execution) {
            let points = patch.controlPoints
            let nu = points[0].count - 1, nv = points.count - 1
            // Exact repeated controls, not small derivative samples, identify
            // factors of the corresponding independent parameter only.
            try OriginalCoefficientAllocation.reserve(count: 4, of: SurfaceParameterBoundary.self, using: &execution)
            for side in [SurfaceParameterBoundary.uLower, .uUpper, .vLower, .vUpper]
                where stationaryBoundaries.contains(side) {
                var count = 0
                switch side {
                case .uLower:
                    while count < nu - 1 {
                        try execution.consumeWork(points.count)
                        guard points.allSatisfy({ $0[count + 1] == $0[0] }) else { break }
                        count += 1
                    }
                case .uUpper:
                    while count < nu - 1 {
                        try execution.consumeWork(points.count)
                        guard points.allSatisfy({ $0[nu - count - 1] == $0[nu] }) else { break }
                        count += 1
                    }
                case .vLower:
                    while count < nv - 1 {
                        try execution.consumeWork(points[0].count)
                        guard points[count + 1] == points[0] else { break }
                        count += 1
                    }
                case .vUpper:
                    while count < nv - 1 {
                        try execution.consumeWork(points[0].count)
                        guard points[nv - count - 1] == points[nv] else { break }
                        count += 1
                    }
                }
                for _ in 0..<count {
                    // A constant zero derivative cannot be divided further;
                    // keeping its zero enclosure forces admission to fail.
                    switch side {
                    case .uLower, .uUpper:
                        if let reduced = try u.removingKnownBoundaryFactor(side, using: &execution) { u = reduced }
                    case .vLower, .vUpper:
                        if let reduced = try v.removingKnownBoundaryFactor(side, using: &execution) { v = reduced }
                    }
                }
            }
            if let normal = try u.cross(v, using: &execution) {
                return (try u.enclosure(using: &execution), try v.enclosure(using: &execution), try normal.enclosure(using: &execution))
            }
        }
        try execution.checkpoint()
        if let exactBounds = try ExactBernsteinDifferentialBounds(patch: patch, using: &execution) {
            return (exactBounds.tangentUNumerator, exactBounds.tangentVNumerator, exactBounds.normalNumerator)
        }

        try execution.checkpoint()
        let homogeneous = try OriginalCoefficientAllocation.map(elements: patch.controlPoints.indices, using: &execution) { vIndex, execution in
            try OriginalCoefficientAllocation.map(elements: patch.controlPoints[vIndex].indices, using: &execution) { uIndex, execution in
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
        let derivativeU = try OriginalCoefficientAllocation.map(elements: homogeneous, using: &execution) { row, execution in
            try OriginalCoefficientAllocation.map(elements: 0..<uDegree, using: &execution) { index, execution in
                (row[index + 1] - row[index]) * uScale
            }
        }
        let derivativeV = try OriginalCoefficientAllocation.map(elements: 0..<vDegree, using: &execution) { rowIndex, execution in
            try OriginalCoefficientAllocation.map(elements: firstRow.indices, using: &execution) { columnIndex, execution in
                (homogeneous[rowIndex + 1][columnIndex]
                    - homogeneous[rowIndex][columnIndex]) * vScale
            }
        }
        let valueBounds = try HomogeneousSurfaceBounds.enclosing(try OriginalCoefficientAllocation.flatten(rows: homogeneous, using: &execution), using: &execution)
        let uBounds = try HomogeneousSurfaceBounds.enclosing(try OriginalCoefficientAllocation.flatten(rows: derivativeU, using: &execution), using: &execution)
        let vBounds = try HomogeneousSurfaceBounds.enclosing(try OriginalCoefficientAllocation.flatten(rows: derivativeV, using: &execution), using: &execution)
        let tangentU = uBounds.xyz * valueBounds.weight - valueBounds.xyz * uBounds.weight
        let tangentV = vBounds.xyz * valueBounds.weight - valueBounds.xyz * vBounds.weight
        return (tangentU, tangentV, tangentU.cross(tangentV))
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

    static func enclosing<A: ExactScalarAdmission & ~Copyable>(_ values: [HomogeneousSurfacePoint], using execution: inout A) throws -> HomogeneousSurfaceBounds {
        HomogeneousSurfaceBounds(
            xyz: IntervalVector3DBounds(
                x: .enclosing(try OriginalCoefficientAllocation.map(elements: values, using: &execution) { value, _ in value.x }),
                y: .enclosing(try OriginalCoefficientAllocation.map(elements: values, using: &execution) { value, _ in value.y }),
                z: .enclosing(try OriginalCoefficientAllocation.map(elements: values, using: &execution) { value, _ in value.z })
            ),
            weight: .enclosing(try OriginalCoefficientAllocation.map(elements: values, using: &execution) { value, _ in value.weight })
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

    init?<A: ExactScalarAdmission & ~Copyable>(patch: RationalBezierSurfacePatch3D, using execution: inout A) throws {
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
        guard let homogeneous = try BernsteinVector4Surface(patch: patch, using: &execution),
              let derivativeU = try homogeneous.derivativeU(parameterSpan: patch.uUpper - patch.uLower, using: &execution),
              let derivativeV = try homogeneous.derivativeV(parameterSpan: patch.vUpper - patch.vLower, using: &execution),
              let derivativeUWeighted = try derivativeU.xyz.multiplied(by: homogeneous.weight, using: &execution),
              let valueTimesWeightDerivativeU = try homogeneous.xyz.multiplied(by: derivativeU.weight, using: &execution),
              let tangentU = try derivativeUWeighted.subtracting(valueTimesWeightDerivativeU, using: &execution),
              let derivativeVWeighted = try derivativeV.xyz.multiplied(by: homogeneous.weight, using: &execution),
              let valueTimesWeightDerivativeV = try homogeneous.xyz.multiplied(by: derivativeV.weight, using: &execution),
              let tangentV = try derivativeVWeighted.subtracting(valueTimesWeightDerivativeV, using: &execution),
              let normal = try tangentU.cross(tangentV, using: &execution) else {
            return nil
        }
        tangentUNumerator = try tangentU.enclosure(using: &execution)
        tangentVNumerator = try tangentV.enclosure(using: &execution)
        normalNumerator = try normal.enclosure(using: &execution)
    }
}

private struct BernsteinVector4Surface {
    let xyz: BernsteinVector3Surface
    let weight: BernsteinScalarSurface

    init?<A: ExactScalarAdmission & ~Copyable>(patch: RationalBezierSurfacePatch3D, using execution: inout A) throws {
        try execution.checkpoint()
        try execution.consumeWork(patch.controlPoints.count)
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
        try OriginalCoefficientAllocation.reserve(count: try exactScalarCount(patch.controlPoints.count, 4, multiply: true), of: [OutwardScalarInterval].self, using: &execution)
        var x: [[OutwardScalarInterval]] = []
        var y: [[OutwardScalarInterval]] = []
        var z: [[OutwardScalarInterval]] = []
        var weight: [[OutwardScalarInterval]] = []
        x.reserveCapacity(patch.controlPoints.count)
        y.reserveCapacity(patch.controlPoints.count)
        z.reserveCapacity(patch.controlPoints.count)
        weight.reserveCapacity(patch.controlPoints.count)
        for vIndex in patch.controlPoints.indices {
            try OriginalCoefficientAllocation.reserve(count: try exactScalarCount(controlPointCount, 4, multiply: true), of: OutwardScalarInterval.self, using: &execution)
            var xRow: [OutwardScalarInterval] = []
            var yRow: [OutwardScalarInterval] = []
            var zRow: [OutwardScalarInterval] = []
            var weightRow: [OutwardScalarInterval] = []
            xRow.reserveCapacity(controlPointCount)
            yRow.reserveCapacity(controlPointCount)
            zRow.reserveCapacity(controlPointCount)
            weightRow.reserveCapacity(controlPointCount)
            for uIndex in patch.controlPoints[vIndex].indices {
                try execution.consumeWork(1)
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

    func derivativeU<A: ExactScalarAdmission & ~Copyable>(parameterSpan: Double, using execution: inout A) throws -> BernsteinVector4Surface? {
        guard let xyz = try xyz.derivativeU(parameterSpan: parameterSpan, using: &execution),
              let weight = try weight.derivativeU(parameterSpan: parameterSpan, using: &execution) else {
            return nil
        }
        return try BernsteinVector4Surface(xyz: xyz, weight: weight)
    }

    func derivativeV<A: ExactScalarAdmission & ~Copyable>(parameterSpan: Double, using execution: inout A) throws -> BernsteinVector4Surface? {
        guard let xyz = try xyz.derivativeV(parameterSpan: parameterSpan, using: &execution),
              let weight = try weight.derivativeV(parameterSpan: parameterSpan, using: &execution) else {
            return nil
        }
        return try BernsteinVector4Surface(xyz: xyz, weight: weight)
    }
}

private struct BernsteinVector3Surface {
    let x: BernsteinScalarSurface
    let y: BernsteinScalarSurface
    let z: BernsteinScalarSurface

    func removingKnownBoundaryFactor<A: ExactScalarAdmission & ~Copyable>(_ side: SurfaceParameterBoundary, using execution: inout A) throws -> Self? {
        guard let x = try x.removingKnownBoundaryFactor(side, using: &execution), let y = try y.removingKnownBoundaryFactor(side, using: &execution),
              let z = try z.removingKnownBoundaryFactor(side, using: &execution) else { return nil }
        return Self(x: x, y: y, z: z)
    }

    func boundary<A: ExactScalarAdmission & ~Copyable>(_ side: SurfaceParameterBoundary, reversed: Bool, using execution: inout A) throws -> BernsteinVector3Surface {
        BernsteinVector3Surface(x: try x.boundary(side, reversed: reversed, using: &execution),
            y: try y.boundary(side, reversed: reversed, using: &execution), z: try z.boundary(side, reversed: reversed, using: &execution))
    }

    func derivativeU<A: ExactScalarAdmission & ~Copyable>(parameterSpan: Double, using execution: inout A) throws -> BernsteinVector3Surface? {
        guard let x = try x.derivativeU(parameterSpan: parameterSpan, using: &execution),
              let y = try y.derivativeU(parameterSpan: parameterSpan, using: &execution),
              let z = try z.derivativeU(parameterSpan: parameterSpan, using: &execution) else {
            return nil
        }
        return BernsteinVector3Surface(x: x, y: y, z: z)
    }

    func derivativeV<A: ExactScalarAdmission & ~Copyable>(parameterSpan: Double, using execution: inout A) throws -> BernsteinVector3Surface? {
        guard let x = try x.derivativeV(parameterSpan: parameterSpan, using: &execution),
              let y = try y.derivativeV(parameterSpan: parameterSpan, using: &execution),
              let z = try z.derivativeV(parameterSpan: parameterSpan, using: &execution) else {
            return nil
        }
        return BernsteinVector3Surface(x: x, y: y, z: z)
    }

    func multiplied<A: ExactScalarAdmission & ~Copyable>(by scalar: BernsteinScalarSurface, using execution: inout A) throws -> BernsteinVector3Surface? {
        guard let x = try x.multiplied(by: scalar, using: &execution),
              let y = try y.multiplied(by: scalar, using: &execution),
              let z = try z.multiplied(by: scalar, using: &execution) else {
            return nil
        }
        return BernsteinVector3Surface(x: x, y: y, z: z)
    }

    func subtracting<A: ExactScalarAdmission & ~Copyable>(_ other: BernsteinVector3Surface, using execution: inout A) throws -> BernsteinVector3Surface? {
        guard let x = try x.subtracting(other.x, using: &execution),
              let y = try y.subtracting(other.y, using: &execution),
              let z = try z.subtracting(other.z, using: &execution) else {
            return nil
        }
        return BernsteinVector3Surface(x: x, y: y, z: z)
    }

    func cross<A: ExactScalarAdmission & ~Copyable>(_ other: BernsteinVector3Surface, using execution: inout A) throws -> BernsteinVector3Surface? {
        guard let yz = try y.multiplied(by: other.z, using: &execution),
              let zy = try z.multiplied(by: other.y, using: &execution),
              let zx = try z.multiplied(by: other.x, using: &execution),
              let xz = try x.multiplied(by: other.z, using: &execution),
              let xy = try x.multiplied(by: other.y, using: &execution),
              let yx = try y.multiplied(by: other.x, using: &execution),
              let xComponent = try yz.subtracting(zy, using: &execution),
              let yComponent = try zx.subtracting(xz, using: &execution),
              let zComponent = try xy.subtracting(yx, using: &execution) else {
            return nil
        }
        return BernsteinVector3Surface(
            x: xComponent,
            y: yComponent,
            z: zComponent
        )
    }

    func enclosure<A: ExactScalarAdmission & ~Copyable>(using execution: inout A) throws -> IntervalVector3DBounds {
        IntervalVector3DBounds(
            x: try x.enclosure(using: &execution),
            y: try y.enclosure(using: &execution),
            z: try z.enclosure(using: &execution)
        )
    }
}

private struct BernsteinScalarSurface {
    /// Exact Bernstein product coefficients are only used while every output
    /// degree remains small enough for exact integer binomial arithmetic.
    let coefficients: [[OutwardScalarInterval]]
    let uDegree: Int
    let vDegree: Int

    func removingKnownBoundaryFactor<A: ExactScalarAdmission & ~Copyable>(_ side: SurfaceParameterBoundary, using execution: inout A) throws -> Self? {
        // B(n,i)/t = n/i * B(n-1,i-1); the opposite endpoint is symmetric.
        // The caller establishes exact vanishing from the original control net.
        let result: [[OutwardScalarInterval]]
        switch side {
        case .uLower:
            guard uDegree > 0 else { return nil }
            result = try OriginalCoefficientAllocation.map(elements: coefficients, using: &execution) { row, execution in try OriginalCoefficientAllocation.map(elements: 1...uDegree, using: &execution) { index, execution in
                row[index] * OutwardScalarInterval(Double(uDegree) / Double(index))
            } }
        case .uUpper:
            guard uDegree > 0 else { return nil }
            result = try OriginalCoefficientAllocation.map(elements: coefficients, using: &execution) { row, execution in try OriginalCoefficientAllocation.map(elements: 0..<uDegree, using: &execution) { index, execution in
                row[index] * OutwardScalarInterval(Double(uDegree) / Double(uDegree - index))
            } }
        case .vLower:
            guard vDegree > 0 else { return nil }
            result = try OriginalCoefficientAllocation.map(elements: 1...vDegree, using: &execution) { j, execution in try OriginalCoefficientAllocation.map(elements: coefficients[j], using: &execution) { value, execution in
                value * OutwardScalarInterval(Double(vDegree) / Double(j))
            } }
        case .vUpper:
            guard vDegree > 0 else { return nil }
            result = try OriginalCoefficientAllocation.map(elements: 0..<vDegree, using: &execution) { j, execution in try OriginalCoefficientAllocation.map(elements: coefficients[j], using: &execution) { value, execution in
                value * OutwardScalarInterval(Double(vDegree) / Double(vDegree - j))
            } }
        }
        // Removing a known factor keeps a nonempty rectangular coefficient net.
        return Self(coefficients: result)
    }

    private init(boundaryCoefficients: [OutwardScalarInterval]) {
        coefficients = [boundaryCoefficients]
        uDegree = boundaryCoefficients.count - 1
        vDegree = 0
    }

    func boundary<A: ExactScalarAdmission & ~Copyable>(_ side: SurfaceParameterBoundary, reversed: Bool, using execution: inout A) throws -> BernsteinScalarSurface {
        let values: [OutwardScalarInterval]
        switch side {
        case .uLower: values = try OriginalCoefficientAllocation.map(elements: coefficients, using: &execution) { row, _ in row[0] }
        case .uUpper: values = try OriginalCoefficientAllocation.map(elements: coefficients, using: &execution) { row, _ in row[uDegree] }
        case .vLower: values = coefficients[0]
        case .vUpper: values = coefficients[vDegree]
        }
        let output = reversed ? try OriginalCoefficientAllocation.map(elements: values.reversed(), using: &execution) { value, _ in value } : values
        try OriginalCoefficientAllocation.reserve(count: 1, of: [OutwardScalarInterval].self, using: &execution)
        return BernsteinScalarSurface(boundaryCoefficients: output)
    }

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

    func derivativeU<A: ExactScalarAdmission & ~Copyable>(parameterSpan: Double, using execution: inout A) throws -> BernsteinScalarSurface? {
        guard uDegree > 0,
              parameterSpan.isFinite,
              parameterSpan > 0.0 else {
            return nil
        }
        let scale = OutwardScalarInterval(Double(uDegree) / parameterSpan)
        let result = try OriginalCoefficientAllocation.map(elements: coefficients, using: &execution) { row, execution in
            try OriginalCoefficientAllocation.map(elements: 0..<uDegree, using: &execution) { index, execution in
                (row[index + 1] - row[index]) * scale
            }
        }
        return BernsteinScalarSurface(coefficients: result)
    }

    func derivativeV<A: ExactScalarAdmission & ~Copyable>(parameterSpan: Double, using execution: inout A) throws -> BernsteinScalarSurface? {
        guard vDegree > 0,
              parameterSpan.isFinite,
              parameterSpan > 0.0 else {
            return nil
        }
        let scale = OutwardScalarInterval(Double(vDegree) / parameterSpan)
        let result = try OriginalCoefficientAllocation.map(elements: 0..<vDegree, using: &execution) { rowIndex, execution in
            try OriginalCoefficientAllocation.map(elements: coefficients[rowIndex].indices, using: &execution) { columnIndex, execution in
                (coefficients[rowIndex + 1][columnIndex]
                    - coefficients[rowIndex][columnIndex]) * scale
            }
        }
        return BernsteinScalarSurface(coefficients: result)
    }

    func subtracting<A: ExactScalarAdmission & ~Copyable>(_ other: BernsteinScalarSurface, using execution: inout A) throws -> BernsteinScalarSurface? {
        guard uDegree == other.uDegree, vDegree == other.vDegree else {
            return nil
        }
        let result = try OriginalCoefficientAllocation.map(elements: coefficients.indices, using: &execution) { vIndex, execution in
            try OriginalCoefficientAllocation.map(elements: coefficients[vIndex].indices, using: &execution) { uIndex, execution in
                coefficients[vIndex][uIndex] - other.coefficients[vIndex][uIndex]
            }
        }
        return BernsteinScalarSurface(coefficients: result)
    }

    func multiplied<A: ExactScalarAdmission & ~Copyable>(by other: BernsteinScalarSurface, using execution: inout A) throws -> BernsteinScalarSurface? {
        let outputUDegree = uDegree + other.uDegree
        let outputVDegree = vDegree + other.vDegree
        guard outputUDegree <= maximumCertifiedBernsteinProductDegree,
              outputVDegree <= maximumCertifiedBernsteinProductDegree else {
            return nil
        }
        var result = try OriginalCoefficientAllocation.map(elements: 0...outputVDegree, using: &execution) { _, execution in
            try OriginalCoefficientAllocation.reserve(count: outputUDegree + 1, of: OutwardScalarInterval.self, using: &execution)
            return Array(repeating: OutwardScalarInterval(0.0), count: outputUDegree + 1)
        }
        for outputV in 0...outputVDegree {
            try execution.checkpoint()
            let firstVLower = max(0, outputV - other.vDegree)
            let firstVUpper = min(vDegree, outputV)
            for outputU in 0...outputUDegree {
                let firstULower = max(0, outputU - other.uDegree)
                let firstUUpper = min(uDegree, outputU)
                var coefficient = OutwardScalarInterval(0.0)
                for firstV in firstVLower...firstVUpper {
                    let secondV = outputV - firstV
                    guard let vWeight = try Self.productWeight(
                        firstDegree: vDegree,
                        firstIndex: firstV,
                        secondDegree: other.vDegree,
                        secondIndex: secondV,
                        outputDegree: outputVDegree,
                        outputIndex: outputV,
                    using: &execution) else {
                        return nil
                    }
                    for firstU in firstULower...firstUUpper {
                        try execution.consumeWork(1)
                        let secondU = outputU - firstU
                        guard let uWeight = try Self.productWeight(
                            firstDegree: uDegree,
                            firstIndex: firstU,
                            secondDegree: other.uDegree,
                            secondIndex: secondU,
                            outputDegree: outputUDegree,
                            outputIndex: outputU,
                        using: &execution) else {
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

    func enclosure<A: ExactScalarAdmission & ~Copyable>(using execution: inout A) throws -> OutwardScalarInterval {
        OutwardScalarInterval.enclosing(try OriginalCoefficientAllocation.flatten(rows: coefficients, using: &execution))
    }

    private static func productWeight<A: ExactScalarAdmission & ~Copyable>(
        firstDegree: Int,
        firstIndex: Int,
        secondDegree: Int,
        secondIndex: Int,
        outputDegree: Int,
        outputIndex: Int,
    using execution: inout A) throws -> OutwardScalarInterval? {
        guard let first = try binomial(firstDegree, firstIndex, using: &execution),
              let second = try binomial(secondDegree, secondIndex, using: &execution),
              let output = try binomial(outputDegree, outputIndex, using: &execution),
              output > 0 else {
            return nil
        }
        let numerator = first.multipliedReportingOverflow(by: second)
        guard numerator.overflow == false else {
            return nil
        }
        return OutwardScalarInterval(Double(numerator.partialValue) / Double(output))
    }

    private static func binomial<A: ExactScalarAdmission & ~Copyable>(_ n: Int, _ k: Int, using execution: inout A) throws -> Int64? {
        guard n >= 0, k >= 0, k <= n else { return nil }
        let reducedK = min(k, n - k)
        try OriginalCoefficientAllocation.reserve(count: reducedK + 1, of: Int64.self, using: &execution)
        var row = Array(repeating: Int64(0), count: reducedK + 1)
        row[0] = 1
        guard reducedK > 0 else { return 1 }
        for currentN in 1...n {
            try execution.checkpoint()
            let upper = min(currentN, reducedK)
            if upper == 0 { continue }
            for index in stride(from: upper, through: 1, by: -1) {
                try execution.consumeWork(1)
                let sum = row[index].addingReportingOverflow(row[index - 1])
                guard sum.overflow == false else { return nil }
                row[index] = sum.partialValue
            }
        }
        return row[reducedK]
    }
}
