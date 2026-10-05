import Foundation
import CADCore

struct GeometryConversionCertification {
    struct Bounds {
        let position: Double
        let tangent: Double
        let curvature: Double
        func accepts(_ r: GeometryConversionRequirements) -> Bool {
            position.isFinite && tangent.isFinite && curvature.isFinite &&
            position <= r.maximumPositionError && tangent <= r.maximumTangentAngle && curvature <= r.maximumCurvatureError
        }
    }
    struct VectorBounds {
        let x: OutwardScalarInterval
        let y: OutwardScalarInterval
        let z: OutwardScalarInterval
        init(_ value: CoordinateEnclosure3D) {
            x = .init(lower: value.x.lower, upper: value.x.upper)
            y = .init(lower: value.y.lower, upper: value.y.upper)
            z = .init(lower: value.z.lower, upper: value.z.upper)
        }
        init(x: OutwardScalarInterval, y: OutwardScalarInterval, z: OutwardScalarInterval) { self.x = x; self.y = y; self.z = z }
        static func + (a: Self, b: Self) -> Self { .init(x: a.x + b.x, y: a.y + b.y, z: a.z + b.z) }
        static func - (a: Self, b: Self) -> Self { .init(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z) }
        static func * (a: Self, b: OutwardScalarInterval) -> Self { .init(x: a.x * b, y: a.y * b, z: a.z * b) }
        var norm: OutwardScalarInterval {
            let value = IntervalVector3DBounds(x: x, y: y, z: z)
            return .init(lower: value.lengthLowerBound, upper: value.lengthUpperBound)
        }
        func dot(_ b: Self) -> OutwardScalarInterval { x * b.x + y * b.y + z * b.z }
        func cross(_ b: Self) -> Self { .init(x: y * b.z - z * b.y, y: z * b.x - x * b.z, z: x * b.y - y * b.x) }
        var normalized: Self? {
            guard let inverse = OutwardScalarInterval.exact(1).divided(by: norm) else { return nil }
            return self * inverse
        }
    }

    func curve(source: any GeometryCurveConversionSource, target: any GeometryCurveConversionSource,
               parameters: ScalarInterval, requirements r: GeometryConversionRequirements,
               tolerance: ModelingTolerance, targetCost: GeometryConversionTargetCost?, budget: inout GeometryConversionBudget) throws -> GeometryConversionGuarantee {
        struct Cell { let parameters: ScalarInterval; let depth: Int }
        if let admission = budget.admission {
            let capacity = admission.maximumSubdivisionDepth.addingReportingOverflow(1)
            let bytes = capacity.partialValue.multipliedReportingOverflow(by: MemoryLayout<Cell>.stride)
            guard !capacity.overflow, !bytes.overflow else {
                throw GeometryConversionError.resourceLimitExceeded("Conversion refinement stack accounting overflowed.")
            }
            try admission.chargeStorage(bytes: bytes.partialValue)
        }
        var stack: [Cell] = []
        if let admission = budget.admission { stack.reserveCapacity(admission.maximumSubdivisionDepth + 1) }
        stack.append(.init(parameters: parameters, depth: 0))
        var position = 0.0, tangent = 0.0, curvature = 0.0
        let initial = budget.visited
        let callerAdmission = budget.admission
        func enclosure(_ value: any GeometryCurveConversionSource, over box: ScalarInterval) throws -> CurveDifferentialEnclosure {
            if let admission = callerAdmission {
                return try value.enclosure(over: box, tolerance: tolerance, admission: admission)
            }
            return try value.enclosure(over: box, tolerance: tolerance)
        }
        while let cell = stack.popLast() {
            let box = cell.parameters
            try budget.admission?.visit(depth: cell.depth)
            try budget.visit()
            let a = try enclosure(source, over: box)
            try targetCost?.chargeProbe(over: box, tolerance: tolerance, budget: &budget)
            let b = try enclosure(target, over: box)
            let center = try centeredInterval(box)
            let ca = try enclosure(source, over: center)
            try targetCost?.chargeProbe(over: center, tolerance: tolerance, budget: &budget)
            let cb = try enclosure(target, over: center)
            try rejectDefiniteDifference(position: VectorBounds(ca.position) - VectorBounds(cb.position),
                curvature: curveCurvature(ca).flatMap { first in curveCurvature(cb).map { first - $0 } }, requirements: r)
            let delta = outwardOffset(box, center: box.midpoint)
            let difference = VectorBounds(ca.position) - VectorBounds(cb.position)
                + (VectorBounds(a.firstDerivative) - VectorBounds(b.firstDerivative)) * delta
            if let angular = angle(VectorBounds(a.firstDerivative), VectorBounds(b.firstDerivative)),
               let ka = curveCurvature(a), let kb = curveCurvature(b) {
                let bound = Bounds(position: difference.norm.upper, tangent: angular, curvature: (ka - kb).absoluteUpperBound)
                if bound.accepts(r) {
                    position = max(position, bound.position); tangent = max(tangent, bound.tangent); curvature = max(curvature, bound.curvature)
                    continue
                }
            }
            let mid = box.midpoint
            guard mid > box.lower, mid < box.upper else { throw GeometryConversionAdmissionRejection.candidate }
            let next = cell.depth.addingReportingOverflow(1)
            guard !next.overflow else {
                throw GeometryConversionError.resourceLimitExceeded("Conversion refinement depth overflowed.")
            }
            if let admission = budget.admission, next.partialValue > admission.maximumSubdivisionDepth {
                throw GeometryConversionError.resourceLimitExceeded("Conversion exhausted caller refinement depth before allocating children.")
            }
            stack.append(.init(parameters: try ScalarInterval(lower: mid, upper: box.upper), depth: next.partialValue))
            stack.append(.init(parameters: try ScalarInterval(lower: box.lower, upper: mid), depth: next.partialValue))
        }
        try Task.checkCancellation()
        return GeometryConversionGuarantee(positionErrorUpperBound: position, tangentAngleUpperBound: tangent,
            curvatureErrorUpperBound: curvature, certifiedBoxCount: budget.visited - initial)
    }

    func surface(source: any GeometrySurfaceConversionSource, target: any GeometrySurfaceConversionSource,
                 parameters: SurfaceParameterBox, requirements r: GeometryConversionRequirements,
                 tolerance: ModelingTolerance, targetCost: GeometryConversionTargetCost, budget: inout GeometryConversionBudget) throws -> GeometryConversionGuarantee {
        struct Cell { let parameters: SurfaceParameterBox; let depth: Int }
        let callerAdmission = budget.admission
        var stack: [Cell] = []
        if let admission = callerAdmission {
            let capacity = admission.maximumSubdivisionDepth.addingReportingOverflow(1)
            guard !capacity.overflow else {
                throw GeometryConversionError.resourceLimitExceeded("Surface refinement capacity overflowed.")
            }
            try admission.chargeStorage(bytes: GeometryConversionBudget.product(capacity.partialValue, MemoryLayout<Cell>.stride))
            stack.reserveCapacity(capacity.partialValue)
        }
        stack.append(.init(parameters: parameters, depth: 0))
        func enclosure(_ value: any GeometrySurfaceConversionSource, over box: SurfaceParameterBox) throws -> SurfaceDifferentialEnclosure {
            if let admission = callerAdmission {
                return try value.enclosure(over: box, tolerance: tolerance, admission: admission)
            }
            return try value.enclosure(over: box, tolerance: tolerance)
        }
        var position = 0.0, tangent = 0.0, curvature = 0.0
        let initial = budget.visited
        while let cell = stack.popLast() {
            let box = cell.parameters
            try callerAdmission?.visit(depth: cell.depth)
            try budget.visit()
            let a = try enclosure(source, over: box)
            try targetCost.chargeProbe(over: box, tolerance: tolerance, budget: &budget)
            let b = try enclosure(target, over: box)
            let center = try SurfaceParameterBox(u: centeredInterval(box.u), v: centeredInterval(box.v))
            let ca = try enclosure(source, over: center)
            try targetCost.chargeProbe(over: center, tolerance: tolerance, budget: &budget)
            let cb = try enclosure(target, over: center)
            let centerDifference = VectorBounds(ca.position) - VectorBounds(cb.position)
            let centerCurvature: OutwardScalarInterval?
            if let ka = principalCurvatures(ca), let kb = principalCurvatures(cb) {
                let first = ka.0 - kb.0, second = ka.1 - kb.1
                centerCurvature = first.absoluteLowerBound > second.absoluteLowerBound ? first : second
            } else { centerCurvature = nil }
            try rejectDefiniteDifference(position: centerDifference, curvature: centerCurvature, requirements: r)
            let u = outwardOffset(box.u, center: box.u.midpoint), v = outwardOffset(box.v, center: box.v.midpoint)
            let differenceU = VectorBounds(a.tangentU) - VectorBounds(b.tangentU)
            let differenceV = VectorBounds(a.tangentV) - VectorBounds(b.tangentV)
            let contributionU = differenceU * u, contributionV = differenceV * v
            let difference = centerDifference + contributionU + contributionV
            if let angular = surfaceAngle(a, b), let ka = principalCurvatures(a), let kb = principalCurvatures(b) {
                let curvatureBound = max((ka.0 - kb.0).absoluteUpperBound, (ka.1 - kb.1).absoluteUpperBound)
                let bound = Bounds(position: difference.norm.upper, tangent: angular, curvature: curvatureBound)
                if bound.accepts(r) {
                    position = max(position, bound.position); tangent = max(tangent, bound.tangent); curvature = max(curvature, bound.curvature)
                    continue
                }
            }
            let refineU = contributionU.norm.upper > contributionV.norm.upper
                || (contributionU.norm.upper == contributionV.norm.upper
                    && box.u.width / parameters.u.width >= box.v.width / parameters.v.width)
            let next = cell.depth.addingReportingOverflow(1)
            guard !next.overflow else { throw GeometryConversionError.resourceLimitExceeded("Surface refinement depth overflowed.") }
            if let admission = callerAdmission, next.partialValue > admission.maximumSubdivisionDepth {
                throw GeometryConversionError.resourceLimitExceeded("Surface conversion exhausted caller refinement depth before allocating children.")
            }
            if refineU {
                let mid = box.u.midpoint
                guard mid > box.u.lower, mid < box.u.upper else { throw GeometryConversionAdmissionRejection.candidate }
                stack.append(.init(parameters: try SurfaceParameterBox(u: ScalarInterval(lower: mid, upper: box.u.upper), v: box.v), depth: next.partialValue))
                stack.append(.init(parameters: try SurfaceParameterBox(u: ScalarInterval(lower: box.u.lower, upper: mid), v: box.v), depth: next.partialValue))
            } else {
                let mid = box.v.midpoint
                guard mid > box.v.lower, mid < box.v.upper else { throw GeometryConversionAdmissionRejection.candidate }
                stack.append(.init(parameters: try SurfaceParameterBox(u: box.u, v: ScalarInterval(lower: mid, upper: box.v.upper)), depth: next.partialValue))
                stack.append(.init(parameters: try SurfaceParameterBox(u: box.u, v: ScalarInterval(lower: box.v.lower, upper: mid)), depth: next.partialValue))
            }
        }
        try Task.checkCancellation()
        return GeometryConversionGuarantee(positionErrorUpperBound: position, tangentAngleUpperBound: tangent,
            curvatureErrorUpperBound: curvature, certifiedBoxCount: budget.visited - initial)
    }

    private func centeredInterval(_ interval: ScalarInterval) throws -> ScalarInterval {
        let mid = interval.midpoint
        let lower = max(interval.lower, mid.nextDown), upper = min(interval.upper, mid.nextUp)
        guard lower < upper else { throw GeometryConversionAdmissionRejection.candidate }
        return try ScalarInterval(lower: lower, upper: upper)
    }
    private func outwardOffset(_ interval: ScalarInterval, center: Double) -> OutwardScalarInterval {
        .init(lower: (interval.lower - center).nextDown, upper: (interval.upper - center).nextUp)
    }
    private func rejectDefiniteDifference(position: VectorBounds, curvature: OutwardScalarInterval?,
                                         requirements: GeometryConversionRequirements) throws {
        if position.norm.lower > requirements.maximumPositionError ||
            (curvature?.absoluteLowerBound ?? 0) > requirements.maximumCurvatureError {
            throw GeometryConversionAdmissionRejection.candidate
        }
    }
    private func angle(_ first: VectorBounds, _ second: VectorBounds) -> Double? {
        let minimum = min(first.norm.lower, second.norm.lower)
        guard minimum > 0, let bound = (.exact(Double.pi.nextUp) * (first - second).norm).divided(by: .exact(minimum)) else { return nil }
        // Normalization is 2/minimum-Lipschitz; angle <= pi/2 times unit chord.
        return min(Double.pi.nextUp, bound.upper)
    }
    private func curveCurvature(_ enclosure: CurveDifferentialEnclosure) -> OutwardScalarInterval? {
        let first = VectorBounds(enclosure.firstDerivative), second = VectorBounds(enclosure.secondDerivative)
        let speed = first.norm
        guard speed.lower > 0 else { return nil }
        return first.cross(second).norm.divided(by: speed * speed * speed)
    }
    private func surfaceAngle(_ a: SurfaceDifferentialEnclosure, _ b: SurfaceDifferentialEnclosure) -> Double? {
        let au = VectorBounds(a.tangentU), av = VectorBounds(a.tangentV)
        let bu = VectorBounds(b.tangentU), bv = VectorBounds(b.tangentV)
        guard let u = angle(au, bu), let v = angle(av, bv), let n = angle(au.cross(av), bu.cross(bv)) else { return nil }
        return max(u, v, n)
    }
    private func principalCurvatures(_ a: SurfaceDifferentialEnclosure) -> (OutwardScalarInterval, OutwardScalarInterval)? {
        let u = VectorBounds(a.tangentU), v = VectorBounds(a.tangentV)
        let cross = u.cross(v)
        guard let normal = cross.normalized else { return nil }
        let e = u.norm * u.norm, f = u.dot(v), g = v.norm * v.norm
        let determinant = cross.norm * cross.norm
        let l = VectorBounds(a.secondDerivativeUU).dot(normal)
        let m = VectorBounds(a.secondDerivativeUV).dot(normal)
        let n = VectorBounds(a.secondDerivativeVV).dot(normal)
        guard let mean = (e * n - .exact(2) * f * m + g * l).divided(by: .exact(2) * determinant),
              let gaussian = (l * n - m * m).divided(by: determinant) else { return nil }
        let discriminant = mean * mean - gaussian
        guard discriminant.isFinite, discriminant.upper >= 0 else { return nil }
        let root = OutwardScalarInterval(lower: max(0, sqrt(max(0, discriminant.lower)).nextDown),
            upper: sqrt(max(0, discriminant.upper)).nextUp)
        return (mean - root, mean + root)
    }
}
