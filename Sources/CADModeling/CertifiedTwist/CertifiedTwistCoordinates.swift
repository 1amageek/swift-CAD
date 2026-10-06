import CADCore
import CADGeometry

/// Outward Rodrigues evaluation encloses normalization and all coefficient math.
package struct CertifiedTwistCoordinates {
    package typealias I = OutwardScalarInterval
    let start: [I]
    let advance: [I]
    let anchor: [I]
    let axis: [I]
    private let admission: GeometryConversionAdmission

    package init(start: CoordinateEnclosure3D, fullEnd: CoordinateEnclosure3D, fraction: Double,
        plane: Plane3D, tolerance: ModelingTolerance, admission: GeometryConversionAdmission) throws {
        self.admission = admission
        try admission.chargeStorage(bytes: 33 * MemoryLayout<I>.stride)
        try admission.chargeWork(33)
        self.start = Self.values(start)
        advance = zip(Self.values(fullEnd), Self.values(start)).map { ($0 - $1) * .exact(fraction) }
        let directed = IntervalVector3DBounds(x: advance[0], y: advance[1], z: advance[2])
        let length = I(lower: directed.lengthLowerBound, upper: directed.lengthUpperBound)
        guard length.isFinite, length.lower > tolerance.distance else {
            throw CertifiedTwistSweepPlan.failure("Sweep axis has no certified positive length.", tolerance)
        }
        axis = try advance.map {
            guard let component = $0.divided(by: length) else {
                throw CertifiedTwistSweepPlan.failure("Sweep axis normalization failed.", tolerance)
            }
            return component
        }
        let planeNormal = [I.exact(plane.normal.x), .exact(plane.normal.y), .exact(plane.normal.z)]
        let offset = zip(Self.values(start), Self.values(plane.origin)).map { $0 - $1 }
        let numerator = zip(planeNormal, offset).reduce(I.exact(0)) { $0 + $1.0 * $1.1 }
        let denominator = zip(planeNormal, advance).reduce(I.exact(0)) { $0 + $1.0 * $1.1 }
        guard let ratio = numerator.divided(by: denominator) else {
            throw CertifiedTwistSweepPlan.failure("Sweep axis has no certified intersection with the section plane.", tolerance)
        }
        anchor = zip(Self.values(start), advance).map { $0 - $1 * ratio }
    }

    package func radialBound(_ point: Point3D) throws -> Double {
        try admission.chargeStorage(bytes: 3 * MemoryLayout<I>.stride)
        try admission.chargeWork(3)
        return zip(Self.values(point), anchor).reduce(I.exact(0)) { $0 + .exact(($1.0 - $1.1).absoluteUpperBound) }.upper
    }

    package func pathPoint(station: I) throws -> [I] {
        try admission.chargeStorage(bytes: 3 * MemoryLayout<I>.stride)
        return try (0..<3).map {
            try admission.chargeWork()
            return start[$0] + advance[$0] * station
        }
    }

    package func transformed(_ point: Point3D, station: I, cosine: I, sine: I, scale: I) throws -> [I] {
        try admission.chargeStorage(bytes: 15 * MemoryLayout<I>.stride)
        try admission.chargeWork(12)
        let r = zip(Self.values(point), anchor).map { $0 - $1 }
        let projection = zip(axis, r).reduce(I.exact(0)) { $0 + $1.0 * $1.1 }
        let axial = axis.map { $0 * projection }
        let cross = [axis[1] * r[2] - axis[2] * r[1],
                     axis[2] * r[0] - axis[0] * r[2],
                     axis[0] * r[1] - axis[1] * r[0]]
        return try (0..<3).map { i in
            try admission.chargeWork()
            return start[i] + advance[i] * station + scale * axial[i] + cosine * (r[i] - axial[i]) + sine * cross[i]
        }
    }

    private static func values(_ p: CoordinateEnclosure3D) -> [I] {
        [.init(lower: p.x.lower, upper: p.x.upper), .init(lower: p.y.lower, upper: p.y.upper),
         .init(lower: p.z.lower, upper: p.z.upper)]
    }

    private static func values(_ p: Point3D) -> [I] { [.exact(p.x), .exact(p.y), .exact(p.z)] }
}
