import CADCore
import CADGeometry
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#else
#error("Original angle arithmetic requires a C math implementation.")
#endif

/// Complete original direction boxes; representative vectors never authorize an angle.
package struct OriginalSelectionAngleBounds {
    package static func exact(_ vector: Vector3D) throws -> CoordinateEnclosure3D {
        var execution = try OriginalQueryExecution.kernelOriginal()
        return try exact(vector, using: &execution)
    }

    package static func difference(_ end: Point3D, _ start: Point3D) throws -> CoordinateEnclosure3D {
        var execution = try OriginalQueryExecution.kernelOriginal()
        return try difference(end, start, using: &execution)
    }

    package static func cross(_ a: CoordinateEnclosure3D, _ b: CoordinateEnclosure3D) throws -> CoordinateEnclosure3D {
        var execution = try OriginalQueryExecution.kernelOriginal()
        return try cross(a, b, using: &execution)
    }

    package static func crossDirection(_ a: CoordinateEnclosure3D, _ b: CoordinateEnclosure3D, tolerance: ModelingTolerance) throws -> CoordinateEnclosure3D {
        var execution = try OriginalQueryExecution.kernelOriginal()
        return try crossDirection(a, b, tolerance: tolerance, using: &execution)
    }

    package static func scaled(_ a: CoordinateEnclosure3D, sign: Double) throws -> CoordinateEnclosure3D {
        var execution = try OriginalQueryExecution.kernelOriginal()
        return try scaled(a, sign: sign, using: &execution)
    }

    package static func representative(_ original: CoordinateEnclosure3D, tolerance: ModelingTolerance) throws -> Vector3D {
        var execution = try OriginalQueryExecution.kernelOriginal()
        return try representative(original, tolerance: tolerance, using: &execution)
    }

    package static func enclose(_ first: CoordinateEnclosure3D, _ second: CoordinateEnclosure3D, tolerance: ModelingTolerance) throws -> ScalarInterval {
        var execution = try OriginalQueryExecution.kernelOriginal()
        return try enclose(first, second, tolerance: tolerance, using: &execution)
    }

    package static func measure(_ a: CoordinateEnclosure3D, _ b: CoordinateEnclosure3D, tolerance: ModelingTolerance) throws -> ScalarInterval {
        var execution = try OriginalQueryExecution.kernelOriginal()
        return try measure(a, b, tolerance: tolerance, using: &execution)
    }

    package static func exact(_ vector: Vector3D, using execution: inout OriginalQueryExecution) throws -> CoordinateEnclosure3D {
        try execution.consumeWork(1)
        try vector.validate()
        return .init(x: try .init(lower: vector.x, upper: vector.x),
            y: try .init(lower: vector.y, upper: vector.y),
            z: try .init(lower: vector.z, upper: vector.z))
    }

    package static func difference(_ end: Point3D, _ start: Point3D, using execution: inout OriginalQueryExecution) throws -> CoordinateEnclosure3D {
        try execution.consumeWork(1)
        try end.validate(); try start.validate()
        return try coordinates(.exact(end.x) - .exact(start.x),
            .exact(end.y) - .exact(start.y), .exact(end.z) - .exact(start.z), using: &execution)
    }

    package static func cross(_ a: CoordinateEnclosure3D, _ b: CoordinateEnclosure3D, using execution: inout OriginalQueryExecution) throws -> CoordinateEnclosure3D {
        try execution.consumeWork(1)
        let ax = interval(a.x), ay = interval(a.y), az = interval(a.z)
        let bx = interval(b.x), by = interval(b.y), bz = interval(b.z)
        try execution.consumeWork(1); let x = ay*bz-az*by
        try execution.consumeWork(1); let y = az*bx-ax*bz
        try execution.consumeWork(1); let z = ax*by-ay*bx
        return try coordinates(x,y,z, using: &execution)
    }

    package static func crossDirection(_ a: CoordinateEnclosure3D, _ b: CoordinateEnclosure3D,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> CoordinateEnclosure3D {
        try execution.consumeWork(1)
        return try cross(stableDirection(a, tolerance: tolerance, using: &execution), stableDirection(b, tolerance: tolerance, using: &execution), using: &execution)
    }

    package static func scaled(_ a: CoordinateEnclosure3D, sign: Double, using execution: inout OriginalQueryExecution) throws -> CoordinateEnclosure3D {
        try execution.consumeWork(1)
        try execution.consumeWork(1); let x = interval(a.x) * .exact(sign)
        try execution.consumeWork(1); let y = interval(a.y) * .exact(sign)
        try execution.consumeWork(1); let z = interval(a.z) * .exact(sign)
        return try coordinates(x,y,z, using: &execution)
    }

    package static func representative(_ original: CoordinateEnclosure3D, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> Vector3D {
        try execution.consumeWork(1)
        let a = try stableDirection(original, tolerance: tolerance, using: &execution)
        let norm = try magnitude(a, using: &execution)
        guard norm.isFinite, norm.lower > 0 else {
            throw failure(tolerance, "Original angle direction cannot exclude a singular vector.")
        }
        try execution.consumeWork(1); let vector = Vector3D(x: a.x.midpoint, y: a.y.midpoint, z: a.z.midpoint)
        try execution.consumeWork(1)
        let length = vector.length
        guard length.isFinite, length > 0 else {
            throw failure(tolerance, "Original direction midpoint has no finite nonzero representative.")
        }
        try execution.consumeWork(1); return vector / length
    }

    package static func enclose(_ first: CoordinateEnclosure3D, _ second: CoordinateEnclosure3D,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> ScalarInterval {
        try execution.consumeWork(1)
        try tolerance.validate()
        let a = try stableDirection(first, tolerance: tolerance, using: &execution)
        let b = try stableDirection(second, tolerance: tolerance, using: &execution)
        let na = try magnitude(a, using: &execution), nb = try magnitude(b, using: &execution)
        guard na.isFinite, nb.isFinite, na.lower > 0, nb.lower > 0 else {
            throw failure(tolerance, "Original angle directions have no certified nonzero norm.")
        }
        try execution.consumeWork(1); let dx = interval(a.x)*interval(b.x)
        try execution.consumeWork(1); let dy = interval(a.y)*interval(b.y)
        try execution.consumeWork(1); let dz = interval(a.z)*interval(b.z)
        try execution.consumeWork(1); let dot = dx + dy + dz
        try execution.consumeWork(1); let denominator = na*nb
        try execution.consumeWork(1)
        guard let cosine = dot.divided(by: denominator)?.intersection(with: .init(lower: -1, upper: 1)), cosine.isFinite else {
            throw failure(tolerance, "Original angle cosine has no finite unit-domain enclosure.")
        }
        try execution.consumeWork(1); let acosLower = max(0, acos(cosine.upper).nextDown)
        try execution.consumeWork(1); let acosUpper = min(Double.pi.nextUp, acos(cosine.lower).nextUp)
        let acosBounds = OutwardScalarInterval(lower: acosLower, upper: acosUpper)
        let crossNorm = try magnitude(cross(a, b, using: &execution), using: &execution)
        guard crossNorm.isFinite, dot.isFinite else {
            throw failure(tolerance, "Original cross-product angle exceeded finite arithmetic.")
        }
        // atan2(y,x) is continuous on y >= 0 away from the origin. All
        // rectangle extrema lie at corners, with the entire [0,pi] retained
        // when both original intervals can vanish. This tightens acos near
        // parallel directions without discarding its independent enclosure.
        let atanBounds: OutwardScalarInterval
        if crossNorm.lower == 0, dot.lower <= 0, dot.upper >= 0 {
            atanBounds = .init(lower: 0, upper: Double.pi.nextUp)
        } else {
            try execution.consumeWork(1); let a0 = atan2(crossNorm.lower, dot.lower)
            try execution.consumeWork(1); let a1 = atan2(crossNorm.lower, dot.upper)
            try execution.consumeWork(1); let a2 = atan2(crossNorm.upper, dot.lower)
            try execution.consumeWork(1); let a3 = atan2(crossNorm.upper, dot.upper)
            try execution.consumeWork(1); let low = min(a0,a1,a2,a3), high = max(a0,a1,a2,a3)
            guard low.isFinite, high.isFinite else {
                throw failure(tolerance, "Original atan2 angle has no finite enclosure.")
            }
            atanBounds = .init(lower: max(0, low.nextDown), upper: min(Double.pi.nextUp, high.nextUp))
        }
        try execution.consumeWork(1)
        guard let result = acosBounds.intersection(with: atanBounds), result.isFinite else {
            throw failure(tolerance, "Independent original angle enclosures disagree.")
        }
        return try ScalarInterval(lower: result.lower, upper: result.upper)
    }

    package static func measure(_ a: CoordinateEnclosure3D, _ b: CoordinateEnclosure3D,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> ScalarInterval {
        try execution.consumeWork(1)
        let result = try enclose(a, b, tolerance: tolerance, using: &execution)
        try execution.consumeWork(1); let estimate = result.midpoint
        try execution.consumeWork(1); let error = max((estimate-result.lower).nextUp, (result.upper-estimate).nextUp)
        try execution.consumeWork(1); let goal = (OutwardScalarInterval.exact(tolerance.angle)
            + .exact(tolerance.relative) * .exact(result.lower)).lower
        guard error <= goal else {
            throw KernelError(phase: .geometry, code: .classificationFailure, residual: error,
                tolerance: tolerance, message: "Original selection angle cannot attain the requested absolute and relative angular accuracy.")
        }
        return result
    }

    private static func stableDirection(_ original: CoordinateEnclosure3D,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> CoordinateEnclosure3D {
        try execution.consumeWork(1)
        try execution.consumeWork(1); let scale = max(abs(original.x.lower), abs(original.x.upper), abs(original.y.lower),
            abs(original.y.upper), abs(original.z.lower), abs(original.z.upper))
        guard scale.isFinite, scale > 0 else {
            throw failure(tolerance, "Original direction has no finite positive scaling authority.")
        }
        func component(_ value: ScalarInterval) throws -> ScalarInterval {
            // Division by this exact positive constant is monotone. Direct endpoint
            // division avoids constructing a nonrepresentable reciprocal for subnormals.
            try execution.consumeWork(1)
            return try .init(lower: (value.lower / scale).nextDown, upper: (value.upper / scale).nextUp)
        }
        return .init(x: try component(original.x), y: try component(original.y), z: try component(original.z))
    }

    private static func interval(_ value: ScalarInterval) -> OutwardScalarInterval {
        .init(lower: value.lower, upper: value.upper)
    }
    private static func square(_ value: OutwardScalarInterval) -> OutwardScalarInterval {
        let low = value.absoluteLowerBound, high = value.absoluteUpperBound
        return .init(lower: max(0, (low*low).nextDown), upper: (high*high).nextUp)
    }
    private static func magnitude(_ vector: CoordinateEnclosure3D, using execution: inout OriginalQueryExecution) throws -> OutwardScalarInterval {
        try execution.consumeWork(1)
        try execution.consumeWork(1); let x = square(interval(vector.x))
        try execution.consumeWork(1); let y = square(interval(vector.y))
        try execution.consumeWork(1); let z = square(interval(vector.z))
        try execution.consumeWork(1); let squared = x + y + z
        try execution.consumeWork(1); let lower = max(0, sqrt(max(0, squared.lower)).nextDown)
        try execution.consumeWork(1); let upper = sqrt(squared.upper).nextUp
        return .init(lower: lower, upper: upper)
    }
    private static func coordinates(_ x: OutwardScalarInterval, _ y: OutwardScalarInterval,
        _ z: OutwardScalarInterval, using execution: inout OriginalQueryExecution) throws -> CoordinateEnclosure3D {
        try execution.consumeWork(1)
        return .init(x: try .init(lower: x.lower, upper: x.upper), y: try .init(lower: y.lower, upper: y.upper),
            z: try .init(lower: z.lower, upper: z.upper))
    }
    private static func failure(_ tolerance: ModelingTolerance, _ message: String) -> KernelError {
        .init(phase: .geometry, code: .singularGeometry, tolerance: tolerance, message: message)
    }
}
