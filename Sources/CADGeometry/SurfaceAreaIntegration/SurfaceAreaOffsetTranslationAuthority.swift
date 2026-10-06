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

/// Exact original degree-one translation law retained by a higher offset query.
struct SurfaceAreaOffsetTranslationAuthority: Sendable {
    let source: BSplineSurface3D
    let direction: SurfaceAreaTranslationCertificate
    let varyingAxis: SurfaceAreaIntervalTaylorScalarJet.Axis
    let translation: IntervalVector3DBounds
    let nativeLower: Double
    let nativeUpper: Double
    let constantRailCoordinates: (Double?,Double?,Double?)
    let constantNormal: IntervalVector3DBounds?

    init?(source: BSplineSurface3D, tolerance: ModelingTolerance,
          consumeWork: () throws -> Void) throws {
        let alongV = !source.isVPeriodic && source.vDegree == 1 && source.vControlPointCount == 2
            && source.vKnots.count == 4
        let alongU = !source.isUPeriodic && source.uDegree == 1 && source.uControlPointCount == 2
            && source.uKnots.count == 4
        guard alongV || alongU else { return nil }
        let count = alongV ? source.uControlPointCount : source.vControlPointCount
        guard count > 0, source.controlPoints.count == source.weights.count else { return nil }
        for row in source.controlPoints.indices {
            try consumeWork()
            guard source.controlPoints[row].count == source.uControlPointCount,
                  source.weights[row].count == source.uControlPointCount else { return nil }
        }
        func point(_ index: Int,_ translated: Bool) -> Point3D {
            alongV ? source.controlPoints[translated ? 1 : 0][index]
                : source.controlPoints[index][translated ? 1 : 0]
        }
        func weight(_ index: Int,_ translated: Bool) -> Double {
            alongV ? source.weights[translated ? 1 : 0][index]
                : source.weights[index][translated ? 1 : 0]
        }
        func values(_ point: Point3D) -> (Double,Double,Double) { (point.x,point.y,point.z) }
        // TwoDiff is allocation-free and gives the unique rounded head plus
        // exact tail for finite stored operands. Equal pairs prove equal reals.
        func difference(_ a: Double,_ b: Double) -> (Double,Double)? {
            let head = a-b, virtualB = a-head, virtualA = head+virtualB
            let tail = (a-virtualA)+(virtualB-b)
            return head.isFinite && tail.isFinite ? (head,tail) : nil
        }
        try consumeWork()
        let first = point(0,false)
        try consumeWork()
        let last = point(count-1,false)
        try consumeWork()
        let translatedFirst = point(0,true)
        let a = values(first), b = values(translatedFirst)
        try consumeWork(); try consumeWork(); try consumeWork()
        guard let dx = difference(b.0,a.0), let dy = difference(b.1,a.1),
              let dz = difference(b.2,a.2) else { return nil }
        var constantX = true, constantY = true, constantZ = true
        var increasingX = true, increasingY = true, increasingZ = true
        var decreasingX = true, decreasingY = true, decreasingZ = true
        var previous = first
        for index in 0..<count {
            try CurrentTaskCancellationChecker().checkCancellation(); try consumeWork()
            try consumeWork()
            let firstWeight = weight(index,false)
            try consumeWork()
            let secondWeight = weight(index,true)
            guard firstWeight > 0, firstWeight == secondWeight else { return nil }
            try consumeWork()
            let p = point(index,false)
            try consumeWork()
            let q = point(index,true)
            let pv = values(p), qv = values(q)
            try consumeWork(); try consumeWork(); try consumeWork()
            guard let ax = difference(qv.0,pv.0), ax.0 == dx.0, ax.1 == dx.1,
                  let ay = difference(qv.1,pv.1), ay.0 == dy.0, ay.1 == dy.1,
                  let az = difference(qv.2,pv.2), az.0 == dz.0, az.1 == dz.1 else { return nil }
            try consumeWork(); try consumeWork(); try consumeWork()
            constantX = constantX && p.x == first.x
            constantY = constantY && p.y == first.y
            constantZ = constantZ && p.z == first.z
            if index > 0 {
                try consumeWork(); try consumeWork(); try consumeWork()
                increasingX = increasingX && p.x > previous.x
                increasingY = increasingY && p.y > previous.y
                increasingZ = increasingZ && p.z > previous.z
                decreasingX = decreasingX && p.x < previous.x
                decreasingY = decreasingY && p.y < previous.y
                decreasingZ = decreasingZ && p.z < previous.z
            }
            previous = p
        }
        let lower = alongV ? source.vKnots[1] : source.uKnots[1]
        let upper = alongV ? source.vKnots[2] : source.uKnots[2]
        let width = OutwardScalarInterval.exact(upper) - .exact(lower)
        guard width.lower > 0 else { return nil }
        func interval(_ pair: (Double,Double)) -> OutwardScalarInterval {
            pair.1 == 0 ? .exact(pair.0) : .exact(pair.0) + .exact(pair.1)
        }
        guard let tx = interval(dx).divided(by:width), let ty = interval(dy).divided(by:width),
              let tz = interval(dz).divided(by:width) else { return nil }
        let translator = IntervalVector3DBounds(x:tx,y:ty,z:tz)
        let knots = alongV ? source.uKnots : source.vKnots
        let degree = alongV ? source.uDegree : source.vDegree
        let periodic = alongV ? source.isUPeriodic : source.isVPeriodic
        var single = !periodic && degree > 0 && count == degree+1
        if single {
            for index in knots.indices {
                try consumeWork()
                single = single && (index <= degree ? knots[index] == knots[degree] : knots[index] == knots[count])
            }
        }
        let line: Vector3D?
        if single, constantY, constantZ, increasingX || decreasingX { line = Vector3D(x:last.x > first.x ? 1 : -1,y:0,z:0) }
        else if single, constantX, constantZ, increasingY || decreasingY { line = Vector3D(x:0,y:last.y > first.y ? 1 : -1,z:0) }
        else if single, constantX, constantY, increasingZ || decreasingZ { line = Vector3D(x:0,y:0,z:last.z > first.z ? 1 : -1) }
        else { line = nil }
        let normal: IntervalVector3DBounds?
        if let line {
            let rail = IntervalVector3DBounds(x:.exact(line.x),y:.exact(line.y),z:.exact(line.z))
            let cross = alongV ? rail.cross(translator) : translator.cross(rail)
            let norm = OutwardScalarInterval(lower:cross.lengthLowerBound,upper:cross.lengthUpperBound)
            if let inverse = OutwardScalarInterval.exact(1).divided(by:norm), norm.lower > 0 {
                normal = cross * inverse
            } else { normal = nil }
        } else { normal = nil }
        self.source = source; direction = alongV ? .v : .u
        varyingAxis = alongV ? .u : .v; translation = translator
        nativeLower = lower; nativeUpper = upper
        constantRailCoordinates = (constantX ? first.x : nil,constantY ? first.y : nil,constantZ ? first.z : nil)
        constantNormal = normal
    }
    func restoringTranslation(to curve: SurfaceIntervalVectorJet,over box: SurfaceParameterBox)
        -> SurfaceIntervalVectorJet {
        let fixed = direction == .v ? box.v : box.u
        let shift = OutwardScalarInterval(lower:fixed.lower,upper:fixed.upper) - .exact(nativeLower)
        let zero = OutwardScalarInterval.exact(0)
        func component(_ field: SurfaceIntervalJet,_ t: OutwardScalarInterval) -> SurfaceIntervalJet {
            SurfaceIntervalJet(value:field.value+t*shift,
                derivativeU:direction == .u ? t : field.derivativeU,
                derivativeV:direction == .v ? t : field.derivativeV,
                secondDerivativeUU:direction == .u ? zero : field.secondDerivativeUU,
                secondDerivativeUV:zero,secondDerivativeVV:direction == .v ? zero : field.secondDerivativeVV,
                thirdDerivativeUUU:direction == .u ? zero : field.thirdDerivativeUUU,
                thirdDerivativeUUV:zero,thirdDerivativeUVV:zero,
                thirdDerivativeVVV:direction == .v ? zero : field.thirdDerivativeVVV)
        }
        return SurfaceIntervalVectorJet(x:component(curve.x,translation.x),
            y:component(curve.y,translation.y),z:component(curve.z,translation.z))
    }

}
