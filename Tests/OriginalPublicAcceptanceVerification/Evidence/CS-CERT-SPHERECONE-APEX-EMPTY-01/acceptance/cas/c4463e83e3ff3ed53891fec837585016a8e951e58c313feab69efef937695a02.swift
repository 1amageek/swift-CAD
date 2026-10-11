import CADCore

/// Imports only the fixed original analytic apex configuration, without fitting geometry.
public struct OriginalCertifiedSphereConeApexSnapshotProvider: OriginalSourceSnapshotting {
    public let field: OriginalPhysicalAngleScalarDomain
    public let tolerance: ModelingTolerance
    public init(field: OriginalPhysicalAngleScalarDomain, tolerance: ModelingTolerance) {
        self.field = field; self.tolerance = tolerance
    }

    /// Representation selection only; this gate never substitutes for scalar proof.
    public static func supports(_ input: borrowing Curve3D) -> Bool {
        guard case let .certifiedIntersection(.sphereCone(curve)) = copy input,
              curve.componentKind == .apexReducedAngularInterval,
              curve.lowerAngle.isFinite, curve.upperAngle.isFinite,
              curve.lowerAngle == 0, curve.upperAngle.bitPattern == Double.pi.bitPattern,
              case let .analytic(.sphere(center, radius)) = curve.sphereSurface,
              center == .origin, radius == 1,
              case let .analytic(.cone(apex, axis, angle)) = curve.coneSurface,
              apex == Point3D(x: 1, y: 0, z: 0), axis == .unitZ,
              angle.bitPattern == 0x3fddac670561bb50 else { return false }
        return true
    }

    public static func supportsPlane(_ input: borrowing Surface3D) -> Bool {
        let origin: Point3D, normal: Vector3D
        switch copy input {
        case .analytic(.plane(let point, let vector)): origin = point; normal = vector
        case .plane(let plane):
            guard plane.uDirection == nil else { return false }
            origin = plane.origin; normal = plane.normal
        default: return false
        }
        return origin == Point3D(x: 0, y: 0, z: 2) && normal == .unitZ
    }

    public func snapshot<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing Curve3D,
        limits: OriginalSourceIssuanceLimits, using admission: inout A
    ) throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<OriginalCertifiedSphereConeApexSnapshot> {
        do {
            try admission.checkpoint(); try admission.consumeWork(32)
            try tolerance.validate()
            // FIXME(INCOMPLETE_IMPLEMENTATION): Other certified branches and configurations
            // lack this whole-support source authority. Public source preparation must reject
            // them until their actual position laws and complete guards are certified.
            guard Self.supports(input), case let .certifiedIntersection(.sphereCone(curve)) = copy input else {
                throw OriginalSourceIssuanceFailure.unsupportedRepresentation
            }
            // Both selected analytic host surfaces are depth zero. Their retained certified
            // source-pair owner adds one edge; the Curve3D enum is not another source edge.
            guard limits.remainingSourceDepth >= 1 else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
            guard case let .analytic(.cone(_, _, angle)) = curve.coneSurface,
                  field.originalRadians.bitPattern == angle.bitPattern else {
                throw OriginalSourceIssuanceFailure.unsupportedCoefficientField
            }
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 1,
                of: OriginalCertifiedSphereConeApexSnapshot.self))
            let result = try curve.originalApexReducedSourceSnapshot(field: field, tolerance: tolerance)
            try admission.checkpoint()
            return .init(original: result, sourceDepth: 1)
        } catch { throw .init(preserving: error) }
    }
}
