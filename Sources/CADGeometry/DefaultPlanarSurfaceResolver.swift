import CADCore

package struct DefaultPlanarSurfaceResolver: PlanarSurfaceResolving {
    package init() {}

    package func canonicalPlane(
        for surface: Surface3D
    ) -> ResolvedPlaneGeometry? {
        switch surface {
        case let .plane(plane):
            return ResolvedPlaneGeometry(
                origin: plane.origin,
                normal: plane.normal
            )
        case let .analytic(.plane(origin, normal)):
            return ResolvedPlaneGeometry(
                origin: origin,
                normal: normal
            )
        case .cylinder, .analytic, .bSpline:
            return nil
        case let .procedural(.offset(offset)):
            guard let sourcePlane = canonicalPlane(for: offset.source) else {
                return nil
            }
            return ResolvedPlaneGeometry(
                origin: sourcePlane.origin + sourcePlane.normal * offset.distance,
                normal: sourcePlane.normal
            )
        case let .procedural(.originalImage(image)):
            guard let original = canonicalPlane(for: image.source) else { return nil }
            let vector = image.transform.basisY.cross(image.transform.basisZ) * original.normal.x
                + image.transform.basisZ.cross(image.transform.basisX) * original.normal.y
                + image.transform.basisX.cross(image.transform.basisY) * original.normal.z
            let length = vector.length
            guard length.isFinite, length > 0 else { return nil }
            let orientation = ((image.uGain > 0) == (image.vGain > 0) ? 1.0 : -1.0)
                * (image.swapAxes ? -1.0 : 1.0)
            return ResolvedPlaneGeometry(origin: image.transform.applying(to: original.origin),
                normal: vector * (orientation / length))
        case .procedural(.ruled), .procedural(.rollingBall), .procedural(.originalRevolution), .procedural(.originalCoons), .procedural(.originalBoundaryCorrected), .procedural(.originalPlaneDerivative), .procedural(.originalDrafted), .procedural(.originalAngularTransport), .procedural(.originalAffineWord):
            return nil
        }
    }

    package func exactPlane(for surface: Surface3D,
        tolerance: ModelingTolerance) throws -> ResolvedPlaneGeometry? {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try exactPlane(for: surface, tolerance: tolerance, using: &execution)
    }

    package func exactPlane(for surface: Surface3D, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> ResolvedPlaneGeometry? {
        try execution.checkpoint()
        try execution.consumeWork(1)
        try execution.admitSourceDepth(0)
        try tolerance.validate()
        try surface.validate(tolerance: tolerance, using: &execution)
        try GeometryStructuralComparisonWork.charge(surface: surface, using: &execution)
        let result: ResolvedPlaneGeometry?
        switch surface {
        case .procedural(.originalImage):
            // FIXME(INCOMPLETE_IMPLEMENTATION): Exact-plane consumers reach this
            // original affine support. A rounded cofactor normal cannot replace
            // its retained source plane; supply an exact representation receipt
            // before this source may be returned as an authored plane.
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                message: "Original affine plane resolution requires exact source representation authority.")
        case let .procedural(.offset(offset)):
            guard offset.distance == 0 else {
                // FIXME(INCOMPLETE_IMPLEMENTATION): Exact-plane consumers may
                // receive a nonzero original offset. Its rounded translated
                // origin is not an exact source representation receipt.
                throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                    message: "Original offset plane resolution requires exact source representation authority.")
            }
            result = try execution.withSourceDepthOffset(1) { execution in
                try exactPlane(for: offset.source, tolerance: tolerance, using: &execution)
            }
        case let .bSpline(native):
            result = try plane(forControlPoints: native.controlPoints.joined(),
                tolerance: tolerance, using: &execution)
        default:
            result = canonicalPlane(for: surface)
        }
        try execution.checkpoint()
        return result
    }

    package func plane<Points: Collection>(
        forControlPoints points: Points,
        tolerance: ModelingTolerance
    ) throws -> ResolvedPlaneGeometry? where Points.Element == Point3D {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try plane(forControlPoints: points, tolerance: tolerance, using: &execution)
    }

    package func plane<Points: Collection, A: ExactScalarAdmission & ~Copyable>(
        forControlPoints points: Points,
        tolerance: ModelingTolerance, using execution: inout A
    ) throws -> ResolvedPlaneGeometry? where Points.Element == Point3D {
        try execution.checkpoint()
        try tolerance.validate()
        for point in points { try execution.consumeWork(1); try point.validate() }
        guard let origin = points.first else { return nil }
        guard let first = try points.dropFirst().first(where: {
            try execution.consumeWork(1)
            return ($0 - origin).length > tolerance.distance
        }) else {
            return nil
        }
        let firstDirection = first - origin
        var candidateNormal: (vector: Vector3D, minimumArea: Double)?
        for point in points.dropFirst() {
            try execution.consumeWork(1)
            let candidateDirection = point - origin
            let cross = firstDirection.cross(candidateDirection)
            let minimumArea = tolerance.distance * max(
                firstDirection.length,
                candidateDirection.length
            )
            if cross.length > minimumArea {
                candidateNormal = (cross, minimumArea)
                break
            }
        }
        guard let candidateNormal else { return nil }
        let unitNormal = try candidateNormal.vector.normalized(
            tolerance: candidateNormal.minimumArea
        )
        let exactNormal = try ExactExpansionArithmetic.difference(
            Point3D(x: unitNormal.x, y: unitNormal.y, z: unitNormal.z), .origin, using: &execution)
        for point in points {
            try execution.consumeWork(1)
            let offset = try ExactExpansionArithmetic.difference(point, origin, using: &execution)
            let dot = try ExactExpansionArithmetic.dot(offset, exactNormal, using: &execution)
            guard try ExactExpansionArithmetic.sign(dot, using: &execution) == .zero else { return nil }
        }
        try execution.checkpoint()
        return ResolvedPlaneGeometry(
            origin: origin,
            normal: unitNormal
        )
    }
}
