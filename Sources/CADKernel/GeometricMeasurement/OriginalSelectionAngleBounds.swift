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
        try vector.validate()
        return .init(x: try .init(lower: vector.x, upper: vector.x),
            y: try .init(lower: vector.y, upper: vector.y),
            z: try .init(lower: vector.z, upper: vector.z))
    }

    package static func difference(_ end: Point3D, _ start: Point3D) throws -> CoordinateEnclosure3D {
        try end.validate(); try start.validate()
        return try coordinates(.exact(end.x) - .exact(start.x),
            .exact(end.y) - .exact(start.y), .exact(end.z) - .exact(start.z))
    }

    package static func cross(_ a: CoordinateEnclosure3D, _ b: CoordinateEnclosure3D,
        consumeWork: () throws -> Void = {}) throws -> CoordinateEnclosure3D {
        let ax = interval(a.x), ay = interval(a.y), az = interval(a.z)
        let bx = interval(b.x), by = interval(b.y), bz = interval(b.z)
        try consumeWork(); let x = ay*bz-az*by
        try consumeWork(); let y = az*bx-ax*bz
        try consumeWork(); let z = ax*by-ay*bx
        return try coordinates(x,y,z)
    }

    package static func crossDirection(_ a: CoordinateEnclosure3D, _ b: CoordinateEnclosure3D,
        tolerance: ModelingTolerance) throws -> CoordinateEnclosure3D {
        try cross(stableDirection(a, tolerance: tolerance), stableDirection(b, tolerance: tolerance))
    }

    package static func scaled(_ a: CoordinateEnclosure3D, sign: Double,
        consumeWork: () throws -> Void = {}) throws -> CoordinateEnclosure3D {
        try consumeWork(); let x = interval(a.x) * .exact(sign)
        try consumeWork(); let y = interval(a.y) * .exact(sign)
        try consumeWork(); let z = interval(a.z) * .exact(sign)
        return try coordinates(x,y,z)
    }

    package static func representative(_ original: CoordinateEnclosure3D, tolerance: ModelingTolerance,
        consumeWork: () throws -> Void = {}) throws -> Vector3D {
        let a = try stableDirection(original, tolerance: tolerance, consumeWork: consumeWork)
        let norm = try magnitude(a, consumeWork: consumeWork)
        guard norm.isFinite, norm.lower > 0 else {
            throw failure(tolerance, "Original angle direction cannot exclude a singular vector.")
        }
        try consumeWork(); let vector = Vector3D(x: a.x.midpoint, y: a.y.midpoint, z: a.z.midpoint)
        try consumeWork()
        let length = vector.length
        guard length.isFinite, length > 0 else {
            throw failure(tolerance, "Original direction midpoint has no finite nonzero representative.")
        }
        try consumeWork(); return vector / length
    }

    package static func enclose(_ first: CoordinateEnclosure3D, _ second: CoordinateEnclosure3D,
        tolerance: ModelingTolerance, consumeWork: () throws -> Void = {}) throws -> ScalarInterval {
        try tolerance.validate()
        let a = try stableDirection(first, tolerance: tolerance, consumeWork: consumeWork)
        let b = try stableDirection(second, tolerance: tolerance, consumeWork: consumeWork)
        let na = try magnitude(a, consumeWork: consumeWork), nb = try magnitude(b, consumeWork: consumeWork)
        guard na.isFinite, nb.isFinite, na.lower > 0, nb.lower > 0 else {
            throw failure(tolerance, "Original angle directions have no certified nonzero norm.")
        }
        try consumeWork(); let dx = interval(a.x)*interval(b.x)
        try consumeWork(); let dy = interval(a.y)*interval(b.y)
        try consumeWork(); let dz = interval(a.z)*interval(b.z)
        try consumeWork(); let dot = dx + dy + dz
        try consumeWork(); let denominator = na*nb
        try consumeWork()
        guard let cosine = dot.divided(by: denominator)?.intersection(with: .init(lower: -1, upper: 1)), cosine.isFinite else {
            throw failure(tolerance, "Original angle cosine has no finite unit-domain enclosure.")
        }
        try consumeWork(); let acosLower = max(0, acos(cosine.upper).nextDown)
        try consumeWork(); let acosUpper = min(Double.pi.nextUp, acos(cosine.lower).nextUp)
        let acosBounds = OutwardScalarInterval(lower: acosLower, upper: acosUpper)
        let crossNorm = try magnitude(cross(a, b, consumeWork: consumeWork), consumeWork: consumeWork)
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
            try consumeWork(); let a0 = atan2(crossNorm.lower, dot.lower)
            try consumeWork(); let a1 = atan2(crossNorm.lower, dot.upper)
            try consumeWork(); let a2 = atan2(crossNorm.upper, dot.lower)
            try consumeWork(); let a3 = atan2(crossNorm.upper, dot.upper)
            try consumeWork(); let low = min(a0,a1,a2,a3), high = max(a0,a1,a2,a3)
            guard low.isFinite, high.isFinite else {
                throw failure(tolerance, "Original atan2 angle has no finite enclosure.")
            }
            atanBounds = .init(lower: max(0, low.nextDown), upper: min(Double.pi.nextUp, high.nextUp))
        }
        try consumeWork()
        guard let result = acosBounds.intersection(with: atanBounds), result.isFinite else {
            throw failure(tolerance, "Independent original angle enclosures disagree.")
        }
        return try ScalarInterval(lower: result.lower, upper: result.upper)
    }

    package static func measure(_ a: CoordinateEnclosure3D, _ b: CoordinateEnclosure3D,
        tolerance: ModelingTolerance, consumeWork: () throws -> Void = {}) throws -> ScalarInterval {
        let result = try enclose(a, b, tolerance: tolerance, consumeWork: consumeWork)
        try consumeWork(); let estimate = result.midpoint
        try consumeWork(); let error = max((estimate-result.lower).nextUp, (result.upper-estimate).nextUp)
        try consumeWork(); let goal = (OutwardScalarInterval.exact(tolerance.angle)
            + .exact(tolerance.relative) * .exact(result.lower)).lower
        guard error <= goal else {
            throw KernelError(phase: .geometry, code: .classificationFailure, residual: error,
                tolerance: tolerance, message: "Original selection angle cannot attain the requested absolute and relative angular accuracy.")
        }
        return result
    }

    private static func stableDirection(_ original: CoordinateEnclosure3D,
        tolerance: ModelingTolerance, consumeWork: () throws -> Void = {}) throws -> CoordinateEnclosure3D {
        try consumeWork(); let scale = max(abs(original.x.lower), abs(original.x.upper), abs(original.y.lower),
            abs(original.y.upper), abs(original.z.lower), abs(original.z.upper))
        guard scale.isFinite, scale > 0 else {
            throw failure(tolerance, "Original direction has no finite positive scaling authority.")
        }
        func component(_ value: ScalarInterval) throws -> ScalarInterval {
            // Division by this exact positive constant is monotone. Direct endpoint
            // division avoids constructing a nonrepresentable reciprocal for subnormals.
            try consumeWork()
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
    private static func magnitude(_ vector: CoordinateEnclosure3D,
        consumeWork: () throws -> Void = {}) throws -> OutwardScalarInterval {
        try consumeWork(); let x = square(interval(vector.x))
        try consumeWork(); let y = square(interval(vector.y))
        try consumeWork(); let z = square(interval(vector.z))
        try consumeWork(); let squared = x + y + z
        try consumeWork(); let lower = max(0, sqrt(max(0, squared.lower)).nextDown)
        try consumeWork(); let upper = sqrt(squared.upper).nextUp
        return .init(lower: lower, upper: upper)
    }
    private static func coordinates(_ x: OutwardScalarInterval, _ y: OutwardScalarInterval,
        _ z: OutwardScalarInterval) throws -> CoordinateEnclosure3D {
        .init(x: try .init(lower: x.lower, upper: x.upper), y: try .init(lower: y.lower, upper: y.upper),
            z: try .init(lower: z.lower, upper: z.upper))
    }
    private static func failure(_ tolerance: ModelingTolerance, _ message: String) -> KernelError {
        .init(phase: .geometry, code: .singularGeometry, tolerance: tolerance, message: message)
    }
}
