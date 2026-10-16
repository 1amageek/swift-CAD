import CADCore

/// Exact native-chart authority for an open, exactly connected affine implicit chain.
struct SurfaceAreaAffineImplicitChartEncloser: Sendable {
    private struct Vector: Sendable {
        let x: OutwardScalarInterval
        let y: OutwardScalarInterval
        let z: OutwardScalarInterval

        func subtracting<A: ExactScalarAdmission & ~Copyable>(_ other: Vector, using execution: inout A) throws -> Vector {
            try execution.consumeWork(1); let x = self.x - other.x
            try execution.consumeWork(1); let y = self.y - other.y
            try execution.consumeWork(1); let z = self.z - other.z
            return Vector(x:x,y:y,z:z)
        }
        func scaled<A: ExactScalarAdmission & ~Copyable>(_ scale: OutwardScalarInterval, using execution: inout A) throws -> Vector {
            try execution.consumeWork(1); let x = self.x * scale
            try execution.consumeWork(1); let y = self.y * scale
            try execution.consumeWork(1); let z = self.z * scale
            return Vector(x:x,y:y,z:z)
        }
        func dot<A: ExactScalarAdmission & ~Copyable>(_ other: Vector, using execution: inout A) throws -> OutwardScalarInterval {
            try execution.consumeWork(1); let x = self.x * other.x
            try execution.consumeWork(1); let y = self.y * other.y
            try execution.consumeWork(1); let z = self.z * other.z
            try execution.consumeWork(1); let xy = x + y
            try execution.consumeWork(1); return xy + z
        }
        func cross<A: ExactScalarAdmission & ~Copyable>(_ other: Vector, using execution: inout A) throws -> Vector {
            func difference(_ a: OutwardScalarInterval,_ b: OutwardScalarInterval,
                _ c: OutwardScalarInterval,_ d: OutwardScalarInterval) throws -> OutwardScalarInterval {
                try execution.consumeWork(1); let first = a*b
                try execution.consumeWork(1); let second = c*d
                try execution.consumeWork(1); return first-second
            }
            return try Vector(x:difference(y,other.z,z,other.y),
                y:difference(z,other.x,x,other.z),z:difference(x,other.y,y,other.x))
        }
        static func exact<A: ExactScalarAdmission & ~Copyable>(_ point: Point3D, using execution: inout A) throws -> Vector {
            try execution.consumeWork(1); let x = OutwardScalarInterval.exact(point.x)
            try execution.consumeWork(1); let y = OutwardScalarInterval.exact(point.y)
            try execution.consumeWork(1); let z = OutwardScalarInterval.exact(point.z)
            return Vector(x:x,y:y,z:z)
        }
    }

    private let curve: CertifiedImplicitSurfaceParameterCurve
    private let uCoefficient: OutwardScalarInterval
    private let uOffset: OutwardScalarInterval
    private let vCoefficient: OutwardScalarInterval
    private let vOffset: OutwardScalarInterval

    init(curve: CertifiedImplicitSurfaceParameterCurve, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        // FIXME(INCOMPLETE_IMPLEMENTATION): General/closed implicit trim charts
        // lack integral-specific native partition authority on face-area queries. Complete
        // only after every original piece and its derivative/error budgets are certified.
        guard !curve.intersection.isClosed, !curve.intersection.cells.isEmpty,
              case .bSpline(let first) = curve.intersection.firstSurface,
              case .bSpline(let second) = curve.intersection.secondSurface,
              try ExactAffineBSplineSurfacePatch(first, using: &execution) != nil,
              try ExactAffineBSplineSurfacePatch(second, using: &execution) != nil else {
            throw Self.failure(.unsupportedCapability,tolerance,
                "Area implicit chart requires an open graph chain on two exact affine B-spline supports.")
        }
        let cell = curve.intersection.cells[0]
        for index in curve.intersection.cells.indices {
            try execution.consumeWork(1)
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
            let origin = try Vector.exact(surface.controlPoints[0][0], using: &execution)
            try execution.consumeWork(1); let uSpan = OutwardScalarInterval.exact(surface.uKnots[2]) - .exact(surface.uKnots[1])
            try execution.consumeWork(1); let vSpan = OutwardScalarInterval.exact(surface.vKnots[2]) - .exact(surface.vKnots[1])
            try execution.consumeWork(1); let uInverse = OutwardScalarInterval.exact(1).divided(by:uSpan)
            try execution.consumeWork(1); let vInverse = OutwardScalarInterval.exact(1).divided(by:vSpan)
            guard let uInverse, let vInverse else {
                throw Self.failure(.singularSystem,tolerance,"Area affine implicit native spans are unresolved.")
            }
            let u = try Vector.exact(surface.controlPoints[0][1], using: &execution)
                .subtracting(origin, using: &execution).scaled(uInverse, using: &execution)
            let v = try Vector.exact(surface.controlPoints[1][0], using: &execution)
                .subtracting(origin, using: &execution).scaled(vInverse, using: &execution)
            let uOffset = try u.scaled(.exact(surface.uKnots[1]), using: &execution)
            let vOffset = try v.scaled(.exact(surface.vKnots[1]), using: &execution)
            return (try origin.subtracting(uOffset, using: &execution)
                .subtracting(vOffset, using: &execution),u,v)
        }
        let a = try affine(first), b = try affine(second)
        let negativeU = try b.u.scaled(.exact(-1), using: &execution)
        let negativeV = try b.v.scaled(.exact(-1), using: &execution)
        func column(_ index: Int) throws -> Vector {
            try execution.consumeWork(1)
            switch index { case 0: return a.u; case 1: return a.v; case 2: return negativeU; default: return negativeV }
        }
        let free = cell.freeParameter.rawValue
        // A four-column system has exactly three fixed dependent owners.
        let i0 = free == 0 ? 1 : 0
        let i1 = free <= 1 ? 2 : 1
        let i2 = free <= 2 ? 3 : 2
        let c0 = try column(i0), c1 = try column(i1), c2 = try column(i2)
        let cross0 = try c1.cross(c2, using: &execution)
        let cross1 = try c2.cross(c0, using: &execution)
        let cross2 = try c0.cross(c1, using: &execution)
        let determinant = try c0.dot(cross0, using: &execution)
        guard determinant.isFinite, determinant.lower > 0 || determinant.upper < 0 else {
            throw Self.failure(.singularSystem,tolerance,
                "Area affine implicit chart cannot certify its complete constant dependent determinant.")
        }
        let rhs = try b.origin.subtracting(a.origin, using: &execution)
        let freeColumn = try column(free)
        func solve(_ index: Int) throws -> (coefficient:OutwardScalarInterval,offset:OutwardScalarInterval) {
            try execution.consumeWork(1)
            if index == free { return (.exact(1),.exact(0)) }
            let cross = index == i0 ? cross0 : index == i1 ? cross1 : cross2
            let offsetNumerator = try rhs.dot(cross, using: &execution)
            let coefficientNumerator = try freeColumn.dot(cross, using: &execution)
            try execution.consumeWork(1); let offset = offsetNumerator.divided(by:determinant)
            try execution.consumeWork(1); let coefficient = (-coefficientNumerator).divided(by:determinant)
            guard let offset, let coefficient, offset.isFinite, coefficient.isFinite else {
                throw Self.failure(.singularSystem,tolerance,"Area affine implicit chart arithmetic is nonfinite.")
            }
            return (coefficient,offset)
        }
        let base = curve.role == .first ? 0 : 2
        let u = try solve(base), v = try solve(base+1)
        self.curve = curve
        uCoefficient = u.coefficient; uOffset = u.offset
        vCoefficient = v.coefficient; vOffset = v.offset
    }

    var hasNativeJoins: Bool { curve.intersection.cells.count > 1 }

    func intervalProof(over fraction: ScalarInterval, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution)
        throws -> SurfaceAreaParameterChartEncloser.IntervalProof {
        if Task.isCancelled { throw Self.failure(.cancelled,tolerance,"Area affine implicit chart was cancelled.") }
        try execution.consumeWork(1); let span = OutwardScalarInterval.exact(curve.endFraction) - .exact(curve.startFraction)
        try execution.consumeWork(1); let traversed = span * OutwardScalarInterval(lower:fraction.lower,upper:fraction.upper)
        try execution.consumeWork(1); let mapped = OutwardScalarInterval.exact(curve.startFraction) + traversed
        let count = curve.intersection.cells.count
        try execution.consumeWork(1); let scaled = mapped * .exact(Double(count))
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
            try execution.consumeWork(1); let product = coefficient*value
            try execution.consumeWork(1); let position = offset+product
            try execution.consumeWork(1); let first = coefficient*slope
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
            try execution.consumeWork(1)
            if Task.isCancelled { throw Self.failure(.cancelled,tolerance,"Area affine implicit enclosure was cancelled.") }
            let localLower = max(lower,Double(index)), localUpper = min(upper,Double(index+1))
            guard localLower <= localUpper else { continue }
            try execution.consumeWork(1); let local = OutwardScalarInterval(lower:localLower,upper:localUpper) - .exact(Double(index))
            let cell = curve.intersection.cells[index]
            let range = cell.parameterBox.interval(for:cell.freeParameter)
            try execution.consumeWork(1); let width = OutwardScalarInterval.exact(range.upper) - .exact(range.lower)
            try execution.consumeWork(1); let chartSlope = width * span
            try execution.consumeWork(1); let slope = chartSlope * .exact(Double(count))
            try execution.consumeWork(1); let increment = width*local
            try execution.consumeWork(1); let value = cell.direction == .forward ? .exact(range.lower)+increment : .exact(range.upper)-increment
            try execution.consumeWork(1); let directedSlope = cell.direction == .forward ? slope : -slope
            let proof = try SurfaceAreaParameterChartEncloser.IntervalProof.smooth(
                u:coordinate(uCoefficient,uOffset,value:value,slope:directedSlope),
                v:coordinate(vCoefficient,vOffset,value:value,slope:directedSlope))
            if let previous = result {
                // Union owns four fixed original value/tangent fields.
                for _ in 0..<4 { try execution.consumeWork(1) }
                result = previous.unionValues(proof)
            } else { result = proof }
        }
        guard let result else { throw Self.failure(.classificationFailure,tolerance,"Area implicit interval has no owning native cell.") }
        return result
    }

    private static func failure(_ code: KernelErrorCode, _ tolerance: ModelingTolerance,
                                _ message: String) -> KernelError {
        KernelError(phase:.geometry,code:code,tolerance:tolerance,message:message)
    }
}
