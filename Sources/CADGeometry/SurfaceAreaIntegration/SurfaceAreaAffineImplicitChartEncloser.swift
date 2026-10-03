import CADCore

/// Exact native-chart authority for one open affine implicit intersection cell.
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
    private let freeRange: ScalarInterval
    private let direction: CertifiedImplicitIntersectionDirection
    private let uCoefficient: OutwardScalarInterval
    private let uOffset: OutwardScalarInterval
    private let vCoefficient: OutwardScalarInterval
    private let vOffset: OutwardScalarInterval

    init(curve: CertifiedImplicitSurfaceParameterCurve, tolerance: ModelingTolerance) throws {
        // FIXME(INCOMPLETE_IMPLEMENTATION): General/closed/multicell implicit trim charts
        // lack integral-specific native partition authority on face-area queries. Complete
        // only after every original piece and its derivative/error budgets are certified.
        guard !curve.intersection.isClosed, curve.intersection.cells.count == 1,
              case .bSpline(let first) = curve.intersection.firstSurface,
              case .bSpline(let second) = curve.intersection.secondSurface,
              ExactAffineBSplineSurfacePatch(first) != nil,
              ExactAffineBSplineSurfacePatch(second) != nil else {
            throw Self.failure(.unsupportedCapability,tolerance,
                "Area implicit chart requires one open graph cell on two exact affine B-spline supports.")
        }
        let cell = curve.intersection.cells[0]
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
        freeRange = cell.parameterBox.interval(for:cell.freeParameter)
        direction = cell.direction
        uCoefficient = coefficients[base]; uOffset = offsets[base]
        vCoefficient = coefficients[base+1]; vOffset = offsets[base+1]
    }

    func intervalJet(over fraction: ScalarInterval, tolerance: ModelingTolerance)
        throws -> (u: SurfaceIntervalJet, v: SurfaceIntervalJet) {
        if Task.isCancelled { throw Self.failure(.cancelled,tolerance,"Area affine implicit chart was cancelled.") }
        let span = OutwardScalarInterval.exact(curve.endFraction) - .exact(curve.startFraction)
        let mapped = OutwardScalarInterval.exact(curve.startFraction)
            + span * OutwardScalarInterval(lower:fraction.lower,upper:fraction.upper)
        let width = OutwardScalarInterval.exact(freeRange.upper) - .exact(freeRange.lower)
        let value: OutwardScalarInterval, slope: OutwardScalarInterval
        if direction == .forward {
            value = .exact(freeRange.lower)+width*mapped; slope = width*span
        } else {
            value = .exact(freeRange.upper)-width*mapped; slope = -width*span
        }
        func coordinate(_ coefficient: OutwardScalarInterval, _ offset: OutwardScalarInterval) throws -> SurfaceIntervalJet {
            let position = offset+coefficient*value, first = coefficient*slope
            guard position.isFinite, first.isFinite else {
                throw Self.failure(.singularSystem,tolerance,"Area affine implicit chart could not enclose finite native UV.")
            }
            // Exact affine source equations make every higher derivative zero.
            let zero = OutwardScalarInterval.exact(0)
            return SurfaceIntervalJet(value:position,derivativeU:first,derivativeV:zero,
                secondDerivativeUU:zero,secondDerivativeUV:zero,secondDerivativeVV:zero,
                thirdDerivativeUUU:zero,thirdDerivativeUUV:zero,thirdDerivativeUVV:zero,thirdDerivativeVVV:zero)
        }
        return try (coordinate(uCoefficient,uOffset),coordinate(vCoefficient,vOffset))
    }

    private static func failure(_ code: KernelErrorCode, _ tolerance: ModelingTolerance,
                                _ message: String) -> KernelError {
        KernelError(phase:.geometry,code:code,tolerance:tolerance,message:message)
    }
}
