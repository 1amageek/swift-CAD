import CADCore

/// Exact native-chart authority for an open, exactly connected affine implicit chain.
struct SurfaceAreaAffineImplicitChartEncloser: Sendable {
    private struct Vector: Sendable {
        let x: OutwardScalarInterval
        let y: OutwardScalarInterval
        let z: OutwardScalarInterval

        static func - (a: Vector, b: Vector) -> Vector {
            Vector(x:a.x-b.x,y:a.y-b.y,z:a.z-b.z)
        }
        func scaled(_ scale: OutwardScalarInterval) -> Vector {
            Vector(x:x*scale,y:y*scale,z:z*scale)
        }
        func dot(_ other: Vector) -> OutwardScalarInterval {
            x*other.x+y*other.y+z*other.z
        }
        func cross(_ other: Vector) -> Vector {
            Vector(x:y*other.z-z*other.y,y:z*other.x-x*other.z,z:x*other.y-y*other.x)
        }
        static func exact(_ point: Point3D) -> Vector {
            Vector(x:.exact(point.x),y:.exact(point.y),z:.exact(point.z))
        }
    }

    private let curve: CertifiedImplicitSurfaceParameterCurve
    private let uCoefficient: OutwardScalarInterval
    private let uOffset: OutwardScalarInterval
    private let vCoefficient: OutwardScalarInterval
    private let vOffset: OutwardScalarInterval

    init(curve: CertifiedImplicitSurfaceParameterCurve, tolerance: ModelingTolerance) throws {
        // FIXME(INCOMPLETE_IMPLEMENTATION): General/closed implicit trim charts
        // lack integral-specific native partition authority on face-area queries. Complete
        // only after every original piece and its derivative/error budgets are certified.
        guard !curve.intersection.isClosed, !curve.intersection.cells.isEmpty,
              case .bSpline(let first) = curve.intersection.firstSurface,
              case .bSpline(let second) = curve.intersection.secondSurface,
              ExactAffineBSplineSurfacePatch(first) != nil,
              ExactAffineBSplineSurfacePatch(second) != nil else {
            throw Self.failure(.unsupportedCapability,tolerance,
                "Area implicit chart requires an open graph chain on two exact affine B-spline supports.")
        }
        let cell = curve.intersection.cells[0]
        for index in curve.intersection.cells.indices {
            if Task.isCancelled { throw Self.failure(.cancelled,tolerance,"Area affine implicit preparation was cancelled.") }
            let current = curve.intersection.cells[index]
            // FIXME(INCOMPLETE_IMPLEMENTATION): Mixed-coordinate/direction
            // implicit joins lack exact original chart authority on production face-area
            // queries. Complete only when every join and its piecewise measure are proved.
            guard current.freeParameter == cell.freeParameter, current.direction == cell.direction else {
                throw Self.failure(.unsupportedCapability,tolerance,"Area implicit chain requires one native free coordinate and direction.")
            }
            if index > 0 {
                let previous = curve.intersection.cells[index-1].parameterBox.interval(for:cell.freeParameter)
                let next = current.parameterBox.interval(for:cell.freeParameter)
                let end = cell.direction == .forward ? previous.upper : previous.lower
                let start = cell.direction == .forward ? next.lower : next.upper
                // The same constant invertible correspondence system then proves all
                // dependent native coordinates agree. Anchor tolerance is not authority.
                // FIXME(INCOMPLETE_IMPLEMENTATION): Inexact implicit joins lack complete
                // trim measure on production face-area queries. Complete only after the
                // original gap and its full-domain integration authority are certified.
                guard end == start else {
                    throw Self.failure(.unsupportedCapability,tolerance,"Area implicit native endpoints must connect exactly.")
                }
            }
        }
        func affine(_ surface: BSplineSurface3D) throws -> (origin: Vector, u: Vector, v: Vector) {
            let origin = Vector.exact(surface.controlPoints[0][0])
            let uSpan = OutwardScalarInterval.exact(surface.uKnots[2]) - .exact(surface.uKnots[1])
            let vSpan = OutwardScalarInterval.exact(surface.vKnots[2]) - .exact(surface.vKnots[1])
            guard let uInverse = OutwardScalarInterval.exact(1).divided(by:uSpan),
                  let vInverse = OutwardScalarInterval.exact(1).divided(by:vSpan) else {
                throw Self.failure(.singularSystem,tolerance,"Area affine implicit native spans are unresolved.")
            }
            let u = (Vector.exact(surface.controlPoints[0][1])-origin).scaled(uInverse)
            let v = (Vector.exact(surface.controlPoints[1][0])-origin).scaled(vInverse)
            return (origin-u.scaled(.exact(surface.uKnots[1]))-v.scaled(.exact(surface.vKnots[1])),u,v)
        }
        let a = try affine(first), b = try affine(second)
        let columns = [a.u,a.v,b.u.scaled(.exact(-1)),b.v.scaled(.exact(-1))]
        let free = cell.freeParameter.rawValue
        let indexes = (0..<4).filter { $0 != free }
        let c0 = columns[indexes[0]], c1 = columns[indexes[1]], c2 = columns[indexes[2]]
        let crossProducts = [c1.cross(c2),c2.cross(c0),c0.cross(c1)]
        let determinant = c0.dot(crossProducts[0])
        guard determinant.isFinite, determinant.lower > 0 || determinant.upper < 0 else {
            throw Self.failure(.singularSystem,tolerance,
                "Area affine implicit chart cannot certify its complete constant dependent determinant.")
        }
        let rhs = b.origin-a.origin
        var coefficients = Array(repeating:OutwardScalarInterval.exact(0),count:4)
        var offsets = coefficients
        coefficients[free] = .exact(1)
        for (index,cross) in zip(indexes,crossProducts) {
            guard let offset = rhs.dot(cross).divided(by:determinant),
                  let coefficient = (-columns[free].dot(cross)).divided(by:determinant),
                  offset.isFinite, coefficient.isFinite else {
                throw Self.failure(.singularSystem,tolerance,"Area affine implicit chart arithmetic is nonfinite.")
            }
            offsets[index] = offset
            coefficients[index] = coefficient
        }
        let base = curve.role == .first ? 0 : 2
        self.curve = curve
        uCoefficient = coefficients[base]; uOffset = offsets[base]
        vCoefficient = coefficients[base+1]; vOffset = offsets[base+1]
    }

    var hasNativeJoins: Bool { curve.intersection.cells.count > 1 }

    func intervalProof(over fraction: ScalarInterval, tolerance: ModelingTolerance)
        throws -> SurfaceAreaParameterChartEncloser.IntervalProof {
        if Task.isCancelled { throw Self.failure(.cancelled,tolerance,"Area affine implicit chart was cancelled.") }
        let span = OutwardScalarInterval.exact(curve.endFraction) - .exact(curve.startFraction)
        let mapped = OutwardScalarInterval.exact(curve.startFraction)
            + span * OutwardScalarInterval(lower:fraction.lower,upper:fraction.upper)
        let count = curve.intersection.cells.count
        let scaled = mapped * .exact(Double(count))
        guard scaled.isFinite else {
            throw Self.failure(.singularSystem,tolerance,"Area implicit cell fraction arithmetic is nonfinite.")
        }
        let lower = max(0,min(Double(count),scaled.lower))
        let upper = max(0,min(Double(count),scaled.upper))
        let first = max(0,Int(lower.rounded(.down))-1)
        let last = min(count-1,Int(upper.rounded(.down)))
        var result: SurfaceAreaParameterChartEncloser.IntervalProof?
        func coordinate(_ coefficient: OutwardScalarInterval, _ offset: OutwardScalarInterval,
                        value: OutwardScalarInterval, slope: OutwardScalarInterval) throws -> SurfaceIntervalJet {
            let position = offset+coefficient*value, first = coefficient*slope
            guard position.isFinite, first.isFinite else {
                throw Self.failure(.singularSystem,tolerance,"Area affine implicit chart could not enclose finite native UV.")
            }
            // Exact affine source equations make higher derivatives zero on this piece only.
            let zero = OutwardScalarInterval.exact(0)
            return SurfaceIntervalJet(value:position,derivativeU:first,derivativeV:zero,
                secondDerivativeUU:zero,secondDerivativeUV:zero,secondDerivativeVV:zero,
                thirdDerivativeUUU:zero,thirdDerivativeUUV:zero,thirdDerivativeUVV:zero,thirdDerivativeVVV:zero)
        }
        for index in first...last {
            if Task.isCancelled { throw Self.failure(.cancelled,tolerance,"Area affine implicit enclosure was cancelled.") }
            let localLower = max(lower,Double(index)), localUpper = min(upper,Double(index+1))
            guard localLower <= localUpper else { continue }
            let local = OutwardScalarInterval(lower:localLower,upper:localUpper) - .exact(Double(index))
            let cell = curve.intersection.cells[index]
            let range = cell.parameterBox.interval(for:cell.freeParameter)
            let width = OutwardScalarInterval.exact(range.upper) - .exact(range.lower)
            let slope = width * span * .exact(Double(count))
            let value = cell.direction == .forward ? .exact(range.lower)+width*local : .exact(range.upper)-width*local
            let directedSlope = cell.direction == .forward ? slope : -slope
            let proof = try SurfaceAreaParameterChartEncloser.IntervalProof.smooth(
                u:coordinate(uCoefficient,uOffset,value:value,slope:directedSlope),
                v:coordinate(vCoefficient,vOffset,value:value,slope:directedSlope))
            result = result.map { $0.unionValues(proof) } ?? proof
        }
        guard let result else { throw Self.failure(.classificationFailure,tolerance,"Area implicit interval has no owning native cell.") }
        return result
    }

    private static func failure(_ code: KernelErrorCode, _ tolerance: ModelingTolerance,
                                _ message: String) -> KernelError {
        KernelError(phase:.geometry,code:code,tolerance:tolerance,message:message)
    }
}
