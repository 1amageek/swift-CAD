import CADCore

/// Physical primitive admission separated from local numerical calculation.
package enum OriginalAffineWordPhysicalAdmission {
    package static func sourceTolerance<B: ExactScalarAdmission & ~Copyable>(for curve: Curve3D,
        word: PreparedOriginalAffineOperationWord, tolerance: ModelingTolerance, usage: inout B)
        throws -> ModelingTolerance {
        switch curve {
        case .circle(let value):
            let basis = try circleOrthonormalBasis(value.normal, tolerance: tolerance)
            return try planar(basis.0, basis.1, value.radius, value.radius,
                word: word, tolerance: tolerance, usage: &usage)
        case .analytic(.circle(_, let normal, let radius)), .analytic(.arc(_, let normal, let radius, _, _)):
            let basis = try analyticOrthonormalBasis(normal, tolerance: tolerance)
            return try planar(basis.u, basis.v, radius, radius, word: word, tolerance: tolerance, usage: &usage)
        case .analytic(.ellipse(_, let normal, let majorAxis, let major, let minor)):
            return try planar(majorAxis, normal.cross(majorAxis).normalized(tolerance: tolerance.distance), major, minor,
                word: word, tolerance: tolerance, usage: &usage)
        default: return tolerance
        }
    }

    package static func sourceTolerance<B: ExactScalarAdmission & ~Copyable>(for surface: Surface3D,
        word: PreparedOriginalAffineOperationWord, tolerance: ModelingTolerance, usage: inout B)
        throws -> ModelingTolerance {
        switch surface {
        case .cylinder(let value):
            let basis = try legacyBasis(value.axis, tolerance: tolerance)
            return try planar(basis.0, basis.1, value.radius, value.radius,
                word: word, tolerance: tolerance, usage: &usage)
        case .analytic(.cylinder(_, let axis, let radius)):
            let basis = try analyticOrthonormalBasis(axis, tolerance: tolerance)
            return try planar(basis.u, basis.v, radius, radius, word: word, tolerance: tolerance, usage: &usage)
        case .analytic(.sphere(_, let radius)):
            return try spatial(.unitX, .unitY, .unitZ, radius, word: word, tolerance: tolerance, usage: &usage)
        case .analytic(.torus(_, let axis, let major, let minor)):
            guard major.isFinite, minor.isFinite, major > minor, minor > 0 else {
                throw GeometryError.invalidRadius(minor)
            }
            let basis = try analyticOrthonormalBasis(axis, tolerance: tolerance)
            let first = try planar(basis.u, basis.v, major, major, word: word, tolerance: tolerance, usage: &usage)
            let second = try spatial(basis.u, basis.v, axis, minor, word: word, tolerance: tolerance, usage: &usage)
            try RationalAlgebraStorage.retain(2, of: Vector3D.self, usage: &usage)
            guard try word.minimumProjectedImageDifferenceIsGreaterThan(originalAxes: [basis.u, basis.v],
                originalAxis: axis, originalLower: minor, originalUpper: major,
                physicalThreshold: tolerance.distance, usage: &usage) else { throw GeometryError.invalidRadius(minor) }
            let distance = min(first.distance, second.distance, (major - minor) * 0.25)
            guard distance > 0 else {
                throw GeometryConversionError.resourceLimitExceeded("Original torus local clearance calculation underflows.")
            }
            return .init(distance: distance, angle: tolerance.angle, relative: tolerance.relative)
        default: return tolerance
        }
    }

    private static func planar<B: ExactScalarAdmission & ~Copyable>(_ first: Vector3D, _ second: Vector3D,
        _ firstLength: Double, _ secondLength: Double, word: PreparedOriginalAffineOperationWord,
        tolerance: ModelingTolerance, usage: inout B) throws -> ModelingTolerance {
        try tolerance.validate()
        guard firstLength.isFinite, secondLength.isFinite, firstLength > 0, secondLength > 0 else {
            throw GeometryError.invalidRadius(min(firstLength, secondLength))
        }
        try RationalAlgebraStorage.retain(2, of: Vector3D.self, usage: &usage)
        try RationalAlgebraStorage.retain(2, of: Double.self, usage: &usage)
        guard try word.minimumImageLengthIsGreaterThan(originalAxes: [first, second],
            originalLengths: [firstLength, secondLength], physicalThreshold: tolerance.distance, usage: &usage) else {
            throw GeometryError.invalidRadius(min(firstLength, secondLength))
        }
        return try localTolerance(min(firstLength, secondLength), target: tolerance)
    }

    private static func spatial<B: ExactScalarAdmission & ~Copyable>(_ first: Vector3D, _ second: Vector3D,
        _ third: Vector3D, _ radius: Double, word: PreparedOriginalAffineOperationWord,
        tolerance: ModelingTolerance, usage: inout B) throws -> ModelingTolerance {
        try tolerance.validate()
        guard radius.isFinite, radius > 0 else { throw GeometryError.invalidRadius(radius) }
        try RationalAlgebraStorage.retain(3, of: Vector3D.self, usage: &usage)
        try RationalAlgebraStorage.retain(3, of: Double.self, usage: &usage)
        guard try word.minimumImageLengthIsGreaterThan(originalAxes: [first, second, third],
            originalLengths: [radius, radius, radius], physicalThreshold: tolerance.distance, usage: &usage) else {
            throw GeometryError.invalidRadius(radius)
        }
        return try localTolerance(radius, target: tolerance)
    }

    private static func localTolerance(_ length: Double, target: ModelingTolerance) throws -> ModelingTolerance {
        let distance = min(target.distance, length * 0.5)
        guard distance.isFinite, distance > 0 else {
            throw GeometryConversionError.resourceLimitExceeded("Original local radius calculation has no positive binary tolerance.")
        }
        return .init(distance: distance, angle: target.angle, relative: target.relative)
    }

    private static func legacyBasis(_ normal: Vector3D, tolerance: ModelingTolerance) throws -> (Vector3D, Vector3D) {
        let n = try normal.normalized(tolerance: tolerance.distance)
        let helper = abs(n.z) < 0.9 ? Vector3D.unitZ : .unitY
        let u = try helper.cross(n).normalized(tolerance: tolerance.distance)
        return (u, n.cross(u))
    }
}
