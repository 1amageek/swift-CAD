import CADCore

public struct CertifiedAnalyticAnalyticIntersectionCurve: Codable, Hashable, Sendable {
    public enum Definition: Codable, Hashable, Sendable {
        case planeTorus(CertifiedPlaneTorusIntersectionCurve)
        case coneCone(CertifiedConeConeIntersectionCurve)
        case cylinderCylinder(CertifiedCylinderCylinderIntersectionCurve)
        case sphereCylinder(CertifiedSphereCylinderIntersectionCurve)
        case sphereCone(CertifiedSphereConeIntersectionCurve)
        case coneCylinder(CertifiedConeCylinderIntersectionCurve)
        case sphereTorus(CertifiedSphereTorusIntersectionCurve)
        case parallelTorusCylinder(CertifiedParallelTorusCylinderIntersectionCurve)
        case generalTorusCylinder(CertifiedGeneralTorusCylinderIntersectionCurve)
        case generalConeTorus(CertifiedGeneralConeTorusIntersectionCurve)
        case parallelTorusTorus(CertifiedParallelTorusTorusIntersectionCurve)
        case congruentTorusTorus(CertifiedCongruentTorusTorusIntersectionCurve)
        case generalTorusTorus(CertifiedGeneralTorusTorusIntersectionCurve)
        case boundedPlaneCone(CertifiedBoundedPlaneConeIntersectionCurve)

        private enum CodingKeys: String, CodingKey {
            case kind
            case planeTorus
            case coneCone
            case cylinderCylinder
            case sphereCylinder
            case sphereCone
            case coneCylinder
            case sphereTorus
            case parallelTorusCylinder
            case generalTorusCylinder
            case generalConeTorus
            case parallelTorusTorus
            case congruentTorusTorus
            case generalTorusTorus
            case boundedPlaneCone
        }

        private enum Kind: String, Codable {
            case planeTorus
            case coneCone
            case cylinderCylinder
            case sphereCylinder
            case sphereCone
            case coneCylinder
            case sphereTorus
            case parallelTorusCylinder
            case generalTorusCylinder
            case generalConeTorus
            case parallelTorusTorus
            case congruentTorusTorus
            case generalTorusTorus
            case boundedPlaneCone
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            switch try container.decode(Kind.self, forKey: .kind) {
            case .planeTorus:
                try container.validateOnlyExpectedKeys([.kind, .planeTorus], in: decoder)
                self = .planeTorus(try container.decode(
                    CertifiedPlaneTorusIntersectionCurve.self,
                    forKey: .planeTorus
                ))
            case .coneCone:
                try container.validateOnlyExpectedKeys([.kind, .coneCone], in: decoder)
                self = .coneCone(try container.decode(
                    CertifiedConeConeIntersectionCurve.self,
                    forKey: .coneCone
                ))
            case .cylinderCylinder:
                try container.validateOnlyExpectedKeys(
                    [.kind, .cylinderCylinder],
                    in: decoder
                )
                self = .cylinderCylinder(try container.decode(
                    CertifiedCylinderCylinderIntersectionCurve.self,
                    forKey: .cylinderCylinder
                ))
            case .sphereCylinder:
                try container.validateOnlyExpectedKeys(
                    [.kind, .sphereCylinder],
                    in: decoder
                )
                self = .sphereCylinder(try container.decode(
                    CertifiedSphereCylinderIntersectionCurve.self,
                    forKey: .sphereCylinder
                ))
            case .sphereCone:
                try container.validateOnlyExpectedKeys(
                    [.kind, .sphereCone],
                    in: decoder
                )
                self = .sphereCone(try container.decode(
                    CertifiedSphereConeIntersectionCurve.self,
                    forKey: .sphereCone
                ))
            case .coneCylinder:
                try container.validateOnlyExpectedKeys(
                    [.kind, .coneCylinder],
                    in: decoder
                )
                self = .coneCylinder(try container.decode(
                    CertifiedConeCylinderIntersectionCurve.self,
                    forKey: .coneCylinder
                ))
            case .sphereTorus:
                try container.validateOnlyExpectedKeys(
                    [.kind, .sphereTorus],
                    in: decoder
                )
                self = .sphereTorus(try container.decode(
                    CertifiedSphereTorusIntersectionCurve.self,
                    forKey: .sphereTorus
                ))
            case .parallelTorusCylinder:
                try container.validateOnlyExpectedKeys(
                    [.kind, .parallelTorusCylinder],
                    in: decoder
                )
                self = .parallelTorusCylinder(try container.decode(
                    CertifiedParallelTorusCylinderIntersectionCurve.self,
                    forKey: .parallelTorusCylinder
                ))
            case .generalTorusCylinder:
                try container.validateOnlyExpectedKeys(
                    [.kind, .generalTorusCylinder],
                    in: decoder
                )
                self = .generalTorusCylinder(try container.decode(
                    CertifiedGeneralTorusCylinderIntersectionCurve.self,
                    forKey: .generalTorusCylinder
                ))
            case .generalConeTorus:
                try container.validateOnlyExpectedKeys(
                    [.kind, .generalConeTorus],
                    in: decoder
                )
                self = .generalConeTorus(try container.decode(
                    CertifiedGeneralConeTorusIntersectionCurve.self,
                    forKey: .generalConeTorus
                ))
            case .parallelTorusTorus:
                try container.validateOnlyExpectedKeys(
                    [.kind, .parallelTorusTorus],
                    in: decoder
                )
                self = .parallelTorusTorus(try container.decode(
                    CertifiedParallelTorusTorusIntersectionCurve.self,
                    forKey: .parallelTorusTorus
                ))
            case .congruentTorusTorus:
                try container.validateOnlyExpectedKeys(
                    [.kind, .congruentTorusTorus],
                    in: decoder
                )
                self = .congruentTorusTorus(try container.decode(
                    CertifiedCongruentTorusTorusIntersectionCurve.self,
                    forKey: .congruentTorusTorus
                ))
            case .generalTorusTorus:
                try container.validateOnlyExpectedKeys(
                    [.kind, .generalTorusTorus],
                    in: decoder
                )
                self = .generalTorusTorus(try container.decode(
                    CertifiedGeneralTorusTorusIntersectionCurve.self,
                    forKey: .generalTorusTorus
                ))
            case .boundedPlaneCone:
                try container.validateOnlyExpectedKeys(
                    [.kind, .boundedPlaneCone],
                    in: decoder
                )
                self = .boundedPlaneCone(try container.decode(
                    CertifiedBoundedPlaneConeIntersectionCurve.self,
                    forKey: .boundedPlaneCone
                ))
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case let .planeTorus(curve):
                try container.encode(Kind.planeTorus, forKey: .kind)
                try container.encode(curve, forKey: .planeTorus)
            case let .coneCone(curve):
                try container.encode(Kind.coneCone, forKey: .kind)
                try container.encode(curve, forKey: .coneCone)
            case let .cylinderCylinder(curve):
                try container.encode(Kind.cylinderCylinder, forKey: .kind)
                try container.encode(curve, forKey: .cylinderCylinder)
            case let .sphereCylinder(curve):
                try container.encode(Kind.sphereCylinder, forKey: .kind)
                try container.encode(curve, forKey: .sphereCylinder)
            case let .sphereCone(curve):
                try container.encode(Kind.sphereCone, forKey: .kind)
                try container.encode(curve, forKey: .sphereCone)
            case let .coneCylinder(curve):
                try container.encode(Kind.coneCylinder, forKey: .kind)
                try container.encode(curve, forKey: .coneCylinder)
            case let .sphereTorus(curve):
                try container.encode(Kind.sphereTorus, forKey: .kind)
                try container.encode(curve, forKey: .sphereTorus)
            case let .parallelTorusCylinder(curve):
                try container.encode(Kind.parallelTorusCylinder, forKey: .kind)
                try container.encode(curve, forKey: .parallelTorusCylinder)
            case let .generalTorusCylinder(curve):
                try container.encode(Kind.generalTorusCylinder, forKey: .kind)
                try container.encode(curve, forKey: .generalTorusCylinder)
            case let .generalConeTorus(curve):
                try container.encode(Kind.generalConeTorus, forKey: .kind)
                try container.encode(curve, forKey: .generalConeTorus)
            case let .parallelTorusTorus(curve):
                try container.encode(Kind.parallelTorusTorus, forKey: .kind)
                try container.encode(curve, forKey: .parallelTorusTorus)
            case let .congruentTorusTorus(curve):
                try container.encode(Kind.congruentTorusTorus, forKey: .kind)
                try container.encode(curve, forKey: .congruentTorusTorus)
            case let .generalTorusTorus(curve):
                try container.encode(Kind.generalTorusTorus, forKey: .kind)
                try container.encode(curve, forKey: .generalTorusTorus)
            case let .boundedPlaneCone(curve):
                try container.encode(Kind.boundedPlaneCone, forKey: .kind)
                try container.encode(curve, forKey: .boundedPlaneCone)
            }
        }
    }

    public struct DifferentialGeometry: Hashable, Sendable {
        public let position: Point3D
        public let firstDerivative: Vector3D
        public let secondDerivative: Vector3D
    }

    public let definition: Definition
    public let firstSurface: Surface3D
    public let secondSurface: Surface3D

    public var planeTorusCurve: CertifiedPlaneTorusIntersectionCurve? {
        guard case let .planeTorus(curve) = definition else { return nil }
        return curve
    }

    public var coneConeCurve: CertifiedConeConeIntersectionCurve? {
        guard case let .coneCone(curve) = definition else { return nil }
        return curve
    }

    public var cylinderCylinderCurve: CertifiedCylinderCylinderIntersectionCurve? {
        guard case let .cylinderCylinder(curve) = definition else { return nil }
        return curve
    }

    public var sphereCylinderCurve: CertifiedSphereCylinderIntersectionCurve? {
        guard case let .sphereCylinder(curve) = definition else { return nil }
        return curve
    }

    public var sphereConeCurve: CertifiedSphereConeIntersectionCurve? {
        guard case let .sphereCone(curve) = definition else { return nil }
        return curve
    }

    public var coneCylinderCurve: CertifiedConeCylinderIntersectionCurve? {
        guard case let .coneCylinder(curve) = definition else { return nil }
        return curve
    }

    public var sphereTorusCurve: CertifiedSphereTorusIntersectionCurve? {
        guard case let .sphereTorus(curve) = definition else { return nil }
        return curve
    }

    public var parallelTorusCylinderCurve:
        CertifiedParallelTorusCylinderIntersectionCurve? {
        guard case let .parallelTorusCylinder(curve) = definition else { return nil }
        return curve
    }

    public var generalTorusCylinderCurve:
        CertifiedGeneralTorusCylinderIntersectionCurve? {
        guard case let .generalTorusCylinder(curve) = definition else { return nil }
        return curve
    }

    public var generalConeTorusCurve: CertifiedGeneralConeTorusIntersectionCurve? {
        guard case let .generalConeTorus(curve) = definition else { return nil }
        return curve
    }

    public var parallelTorusTorusCurve:
        CertifiedParallelTorusTorusIntersectionCurve? {
        guard case let .parallelTorusTorus(curve) = definition else { return nil }
        return curve
    }

    public var generalTorusTorusCurve:
        CertifiedGeneralTorusTorusIntersectionCurve? {
        guard case let .generalTorusTorus(curve) = definition else { return nil }
        return curve
    }

    public var congruentTorusTorusCurve:
        CertifiedCongruentTorusTorusIntersectionCurve? {
        guard case let .congruentTorusTorus(curve) = definition else { return nil }
        return curve
    }

    public var boundedPlaneConeCurve:
        CertifiedBoundedPlaneConeIntersectionCurve? {
        guard case let .boundedPlaneCone(curve) = definition else { return nil }
        return curve
    }

    public var usesDerivedSurfaceParameterCurves: Bool {
        switch definition {
        case .planeTorus, .congruentTorusTorus, .boundedPlaneCone:
            false
        case let .coneCylinder(curve):
            curve.componentKind != .apexLowerNodeInterval
                && curve.componentKind != .apexUpperNodeInterval
        case let .parallelTorusTorus(curve):
            curve.componentKind != .nearNodalClosedLoop
        case let .generalConeTorus(curve):
            curve.apexReduction == nil
        case .coneCone, .cylinderCylinder, .sphereCylinder, .sphereCone,
             .sphereTorus, .parallelTorusCylinder,
             .generalTorusCylinder, .generalTorusTorus:
            true
        }
    }

    public var curve: Curve3D {
        switch definition {
        case let .planeTorus(curve):
            return .analytic(.planeTorus(curve))
        case let .coneCone(curve):
            if curve.componentKind == .apexReducedAngularInterval {
                return .certifiedIntersection(.coneCone(curve))
            }
            let role: SurfaceIntersectionSurfaceRole = isEquivalent(
                firstSurface,
                to: curve.parameterizedSurface
            ) ? .first : .second
            return .surfaceLift(SurfaceLiftCurve3D(
                surface: surface(for: role),
                parameterCurve: parameterCurve(for: role)
            ))
        case let .cylinderCylinder(curve):
            let role: SurfaceIntersectionSurfaceRole = firstSurface
                == curve.parameterizedSurface ? .first : .second
            return .surfaceLift(SurfaceLiftCurve3D(
                surface: surface(for: role),
                parameterCurve: parameterCurve(for: role)
            ))
        case let .sphereCylinder(curve):
            let role: SurfaceIntersectionSurfaceRole = firstSurface
                == curve.cylinderSurface ? .first : .second
            return .surfaceLift(SurfaceLiftCurve3D(
                surface: surface(for: role),
                parameterCurve: parameterCurve(for: role)
            ))
        case let .sphereCone(curve):
            if curve.componentKind == .apexReducedAngularInterval {
                return .certifiedIntersection(.sphereCone(curve))
            }
            let role: SurfaceIntersectionSurfaceRole = firstSurface
                == curve.coneSurface ? .first : .second
            return .surfaceLift(SurfaceLiftCurve3D(
                surface: surface(for: role),
                parameterCurve: parameterCurve(for: role)
            ))
        case let .coneCylinder(curve):
            if curve.componentKind == .apexLowerNodeInterval
                || curve.componentKind == .apexUpperNodeInterval {
                return .certifiedIntersection(.coneCylinder(curve))
            }
            let role: SurfaceIntersectionSurfaceRole = firstSurface
                == curve.cylinderSurface ? .first : .second
            return .surfaceLift(SurfaceLiftCurve3D(
                surface: surface(for: role),
                parameterCurve: parameterCurve(for: role)
            ))
        case let .sphereTorus(curve):
            let role: SurfaceIntersectionSurfaceRole = firstSurface
                == curve.torusSurface ? .first : .second
            return .surfaceLift(SurfaceLiftCurve3D(
                surface: surface(for: role),
                parameterCurve: parameterCurve(for: role)
            ))
        case let .parallelTorusCylinder(curve):
            let role: SurfaceIntersectionSurfaceRole = firstSurface
                == curve.cylinderSurface ? .first : .second
            return .surfaceLift(SurfaceLiftCurve3D(
                surface: surface(for: role),
                parameterCurve: parameterCurve(for: role)
            ))
        case let .generalTorusCylinder(curve):
            let role: SurfaceIntersectionSurfaceRole = firstSurface
                == curve.cylinderSurface ? .first : .second
            return .surfaceLift(SurfaceLiftCurve3D(
                surface: surface(for: role),
                parameterCurve: parameterCurve(for: role)
            ))
        case let .generalConeTorus(curve):
            if curve.apexReduction != nil {
                return .certifiedIntersection(.coneTorus(curve))
            }
            let role: SurfaceIntersectionSurfaceRole = firstSurface
                == curve.coneSurface ? .first : .second
            return .surfaceLift(SurfaceLiftCurve3D(
                surface: surface(for: role),
                parameterCurve: parameterCurve(for: role)
            ))
        case let .parallelTorusTorus(curve):
            if curve.componentKind == .nearNodalClosedLoop {
                return .certifiedIntersection(.parallelTorusTorus(curve))
            }
            let role: SurfaceIntersectionSurfaceRole = firstSurface
                == curve.primarySurface ? .first : .second
            return .surfaceLift(SurfaceLiftCurve3D(
                surface: surface(for: role),
                parameterCurve: parameterCurve(for: role)
            ))
        case let .congruentTorusTorus(curve):
            return .analytic(.planeTorus(curve.sectionCurve))
        case let .generalTorusTorus(curve):
            let role: SurfaceIntersectionSurfaceRole = firstSurface
                == curve.parameterizedSurface ? .first : .second
            return .surfaceLift(SurfaceLiftCurve3D(
                surface: surface(for: role),
                parameterCurve: parameterCurve(for: role)
            ))
        case let .boundedPlaneCone(curve):
            let role: SurfaceIntersectionSurfaceRole = firstSurface
                == curve.planeSurface ? .first : .second
            return .surfaceLift(SurfaceLiftCurve3D(
                surface: surface(for: role),
                parameterCurve: parameterCurve(for: role)
            ))
        }
    }

    public var certificationTolerance: ModelingTolerance {
        switch definition {
        case let .planeTorus(curve):
            curve.certificationTolerance
        case let .coneCone(curve):
            curve.certificationTolerance
        case let .cylinderCylinder(curve):
            curve.certificationTolerance
        case let .sphereCylinder(curve):
            curve.certificationTolerance
        case let .sphereCone(curve):
            curve.certificationTolerance
        case let .coneCylinder(curve):
            curve.certificationTolerance
        case let .sphereTorus(curve):
            curve.certificationTolerance
        case let .parallelTorusCylinder(curve):
            curve.certificationTolerance
        case let .generalTorusCylinder(curve):
            curve.certificationTolerance
        case let .generalConeTorus(curve):
            curve.certificationTolerance
        case let .parallelTorusTorus(curve):
            curve.certificationTolerance
        case let .congruentTorusTorus(curve):
            curve.certificationTolerance
        case let .generalTorusTorus(curve):
            curve.certificationTolerance
        case let .boundedPlaneCone(curve):
            curve.certificationTolerance
        }
    }

    public var maximumResidualUpperBound: Double {
        switch definition {
        case let .planeTorus(curve):
            curve.maximumResidualUpperBound
        case let .coneCone(curve):
            curve.maximumResidualUpperBound
        case let .cylinderCylinder(curve):
            curve.maximumResidualUpperBound
        case let .sphereCylinder(curve):
            curve.maximumResidualUpperBound
        case let .sphereCone(curve):
            curve.maximumResidualUpperBound
        case let .coneCylinder(curve):
            curve.maximumResidualUpperBound
        case let .sphereTorus(curve):
            curve.maximumResidualUpperBound
        case let .parallelTorusCylinder(curve):
            curve.maximumResidualUpperBound
        case let .generalTorusCylinder(curve):
            curve.maximumResidualUpperBound
        case let .generalConeTorus(curve):
            curve.maximumResidualUpperBound
        case let .parallelTorusTorus(curve):
            curve.maximumResidualUpperBound
        case let .congruentTorusTorus(curve):
            curve.maximumResidualUpperBound
        case let .generalTorusTorus(curve):
            curve.maximumResidualUpperBound
        case let .boundedPlaneCone(curve):
            curve.maximumResidualUpperBound
        }
    }

    public var firstSurfaceParameterCurve: SurfaceParameterCurve {
        parameterCurve(for: .first)
    }

    public var secondSurfaceParameterCurve: SurfaceParameterCurve {
        parameterCurve(for: .second)
    }

    public init(
        planeTorusCurve: CertifiedPlaneTorusIntersectionCurve,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws {
        definition = .planeTorus(planeTorusCurve)
        self.firstSurface = firstSurface
        self.secondSurface = secondSurface
        try validate(tolerance: tolerance)
    }

    public init(
        coneConeCurve: CertifiedConeConeIntersectionCurve,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws {
        definition = .coneCone(coneConeCurve)
        self.firstSurface = firstSurface
        self.secondSurface = secondSurface
        try validate(tolerance: tolerance)
    }

    public init(
        cylinderCylinderCurve: CertifiedCylinderCylinderIntersectionCurve,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws {
        definition = .cylinderCylinder(cylinderCylinderCurve)
        self.firstSurface = firstSurface
        self.secondSurface = secondSurface
        try validate(tolerance: tolerance)
    }

    public init(
        sphereCylinderCurve: CertifiedSphereCylinderIntersectionCurve,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws {
        definition = .sphereCylinder(sphereCylinderCurve)
        self.firstSurface = firstSurface
        self.secondSurface = secondSurface
        try validate(tolerance: tolerance)
    }

    public init(
        sphereConeCurve: CertifiedSphereConeIntersectionCurve,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws {
        definition = .sphereCone(sphereConeCurve)
        self.firstSurface = firstSurface
        self.secondSurface = secondSurface
        try validate(tolerance: tolerance)
    }

    public init(
        coneCylinderCurve: CertifiedConeCylinderIntersectionCurve,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws {
        definition = .coneCylinder(coneCylinderCurve)
        self.firstSurface = firstSurface
        self.secondSurface = secondSurface
        try validate(tolerance: tolerance)
    }

    public init(
        sphereTorusCurve: CertifiedSphereTorusIntersectionCurve,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws {
        definition = .sphereTorus(sphereTorusCurve)
        self.firstSurface = firstSurface
        self.secondSurface = secondSurface
        try validate(tolerance: tolerance)
    }

    public init(
        parallelTorusCylinderCurve: CertifiedParallelTorusCylinderIntersectionCurve,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws {
        definition = .parallelTorusCylinder(parallelTorusCylinderCurve)
        self.firstSurface = firstSurface
        self.secondSurface = secondSurface
        try validate(tolerance: tolerance)
    }

    public init(
        generalTorusCylinderCurve: CertifiedGeneralTorusCylinderIntersectionCurve,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws {
        definition = .generalTorusCylinder(generalTorusCylinderCurve)
        self.firstSurface = firstSurface
        self.secondSurface = secondSurface
        try validate(tolerance: tolerance)
    }

    public init(
        generalConeTorusCurve: CertifiedGeneralConeTorusIntersectionCurve,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws {
        definition = .generalConeTorus(generalConeTorusCurve)
        self.firstSurface = firstSurface
        self.secondSurface = secondSurface
        try validate(tolerance: tolerance)
    }

    public init(
        parallelTorusTorusCurve: CertifiedParallelTorusTorusIntersectionCurve,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws {
        definition = .parallelTorusTorus(parallelTorusTorusCurve)
        self.firstSurface = firstSurface
        self.secondSurface = secondSurface
        try validate(tolerance: tolerance)
    }

    public init(
        congruentTorusTorusCurve: CertifiedCongruentTorusTorusIntersectionCurve,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws {
        definition = .congruentTorusTorus(congruentTorusTorusCurve)
        self.firstSurface = firstSurface
        self.secondSurface = secondSurface
        try validate(tolerance: tolerance)
    }

    public init(
        generalTorusTorusCurve: CertifiedGeneralTorusTorusIntersectionCurve,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws {
        definition = .generalTorusTorus(generalTorusTorusCurve)
        self.firstSurface = firstSurface
        self.secondSurface = secondSurface
        try validate(tolerance: tolerance)
    }

    public init(
        boundedPlaneConeCurve: CertifiedBoundedPlaneConeIntersectionCurve,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws {
        definition = .boundedPlaneCone(boundedPlaneConeCurve)
        self.firstSurface = firstSurface
        self.secondSurface = secondSurface
        try validate(tolerance: tolerance)
    }

    public func surface(for role: SurfaceIntersectionSurfaceRole) -> Surface3D {
        role == .first ? firstSurface : secondSurface
    }

    public func point(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> Point3D {
        switch definition {
        case let .planeTorus(curve):
            return try curve.point(
                at: try planeTorusParameter(fraction, tolerance: tolerance),
                tolerance: tolerance
            )
        case let .coneCone(curve):
            return try curve.point(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
        case let .cylinderCylinder(curve):
            return try curve.point(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
        case let .sphereCylinder(curve):
            return try curve.point(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
        case let .sphereCone(curve):
            return try curve.point(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
        case let .coneCylinder(curve):
            return try curve.point(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
        case let .sphereTorus(curve):
            return try curve.point(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
        case let .parallelTorusCylinder(curve):
            return try curve.point(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
        case let .generalTorusCylinder(curve):
            return try curve.point(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
        case let .generalConeTorus(curve):
            return try curve.point(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
        case let .parallelTorusTorus(curve):
            return try curve.point(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
        case let .congruentTorusTorus(curve):
            return try curve.point(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
        case let .generalTorusTorus(curve):
            return try curve.point(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
        case let .boundedPlaneCone(curve):
            return try curve.point(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
        }
    }

    public func differential(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> DifferentialGeometry {
        switch definition {
        case let .planeTorus(curve):
            let geometry = try curve.differentialGeometry(
                at: try planeTorusParameter(fraction, tolerance: tolerance),
                tolerance: tolerance
            )
            let scale = 2.0 * Double.pi
            return DifferentialGeometry(
                position: geometry.position,
                firstDerivative: geometry.firstDerivative * scale,
                secondDerivative: geometry.secondDerivative * (scale * scale)
            )
        case let .coneCone(curve):
            let geometry = try curve.differential(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            return DifferentialGeometry(
                position: geometry.position,
                firstDerivative: geometry.firstDerivative,
                secondDerivative: geometry.secondDerivative
            )
        case let .cylinderCylinder(curve):
            let geometry = try curve.differential(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            return DifferentialGeometry(
                position: geometry.position,
                firstDerivative: geometry.firstDerivative,
                secondDerivative: geometry.secondDerivative
            )
        case let .sphereCylinder(curve):
            let geometry = try curve.differential(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            return DifferentialGeometry(
                position: geometry.position,
                firstDerivative: geometry.firstDerivative,
                secondDerivative: geometry.secondDerivative
            )
        case let .sphereCone(curve):
            let geometry = try curve.differential(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            return DifferentialGeometry(
                position: geometry.position,
                firstDerivative: geometry.firstDerivative,
                secondDerivative: geometry.secondDerivative
            )
        case let .coneCylinder(curve):
            let geometry = try curve.differential(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            return DifferentialGeometry(
                position: geometry.position,
                firstDerivative: geometry.firstDerivative,
                secondDerivative: geometry.secondDerivative
            )
        case let .sphereTorus(curve):
            let geometry = try curve.differential(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            return DifferentialGeometry(
                position: geometry.position,
                firstDerivative: geometry.firstDerivative,
                secondDerivative: geometry.secondDerivative
            )
        case let .parallelTorusCylinder(curve):
            let geometry = try curve.differential(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            return DifferentialGeometry(
                position: geometry.position,
                firstDerivative: geometry.firstDerivative,
                secondDerivative: geometry.secondDerivative
            )
        case let .generalTorusCylinder(curve):
            let geometry = try curve.differential(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            return DifferentialGeometry(
                position: geometry.position,
                firstDerivative: geometry.firstDerivative,
                secondDerivative: geometry.secondDerivative
            )
        case let .generalConeTorus(curve):
            let geometry = try curve.differential(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            return DifferentialGeometry(
                position: geometry.position,
                firstDerivative: geometry.firstDerivative,
                secondDerivative: geometry.secondDerivative
            )
        case let .parallelTorusTorus(curve):
            let geometry = try curve.differential(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            return DifferentialGeometry(
                position: geometry.position,
                firstDerivative: geometry.firstDerivative,
                secondDerivative: geometry.secondDerivative
            )
        case let .congruentTorusTorus(curve):
            let geometry = try curve.differential(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            return DifferentialGeometry(
                position: geometry.position,
                firstDerivative: geometry.firstDerivative,
                secondDerivative: geometry.secondDerivative
            )
        case let .generalTorusTorus(curve):
            let geometry = try curve.differential(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            return DifferentialGeometry(
                position: geometry.position,
                firstDerivative: geometry.firstDerivative,
                secondDerivative: geometry.secondDerivative
            )
        case let .boundedPlaneCone(curve):
            let geometry = try curve.differential(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            return DifferentialGeometry(
                position: geometry.position,
                firstDerivative: geometry.firstDerivative,
                secondDerivative: geometry.secondDerivative
            )
        }
    }

    public func internalParameter(
        for role: SurfaceIntersectionSurfaceRole,
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameter {
        switch definition {
        case let .planeTorus(curve):
            let parameters = try curve.surfaceParameters(
                at: try planeTorusParameter(fraction, tolerance: tolerance),
                tolerance: tolerance
            )
            let planeIsFirst = firstSurface == curve.planeSurface
            if planeIsFirst {
                return role == .first ? parameters.plane : parameters.torus
            }
            return role == .first ? parameters.torus : parameters.plane
        case let .coneCone(curve):
            return try curve.parameter(
                on: surface(for: role),
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
        case let .cylinderCylinder(curve):
            return try curve.parameter(
                on: surface(for: role),
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
        case let .sphereCylinder(curve):
            return try curve.parameter(
                on: surface(for: role),
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
        case let .sphereCone(curve):
            return try curve.parameter(
                on: surface(for: role),
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
        case let .coneCylinder(curve):
            return try curve.parameter(
                on: surface(for: role),
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
        case let .sphereTorus(curve):
            return try curve.parameter(
                on: surface(for: role),
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
        case let .parallelTorusCylinder(curve):
            return try curve.parameter(
                on: surface(for: role),
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
        case let .generalTorusCylinder(curve):
            return try curve.parameter(
                on: surface(for: role),
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
        case let .generalConeTorus(curve):
            return try curve.parameter(
                on: surface(for: role),
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
        case let .parallelTorusTorus(curve):
            return try curve.parameter(
                on: surface(for: role),
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
        case let .congruentTorusTorus(curve):
            return try curve.parameter(
                on: surface(for: role),
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
        case let .generalTorusTorus(curve):
            return try curve.parameter(
                on: surface(for: role),
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
        case let .boundedPlaneCone(curve):
            return try curve.parameter(
                on: surface(for: role),
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
        }
    }

    public func boundingBox(tolerance: ModelingTolerance) throws -> BoundingBox3D {
        switch definition {
        case let .planeTorus(curve):
            return try curve.boundingBox(tolerance: tolerance)
        case let .coneCone(curve):
            return try curve.boundingBox(tolerance: tolerance)
        case let .cylinderCylinder(curve):
            return try curve.boundingBox(tolerance: tolerance)
        case let .sphereCylinder(curve):
            return try curve.boundingBox(tolerance: tolerance)
        case let .sphereCone(curve):
            return try curve.boundingBox(tolerance: tolerance)
        case let .coneCylinder(curve):
            return try curve.boundingBox(tolerance: tolerance)
        case let .sphereTorus(curve):
            return try curve.boundingBox(tolerance: tolerance)
        case let .parallelTorusCylinder(curve):
            return try curve.boundingBox(tolerance: tolerance)
        case let .generalTorusCylinder(curve):
            return try curve.boundingBox(tolerance: tolerance)
        case let .generalConeTorus(curve):
            return try curve.boundingBox(tolerance: tolerance)
        case let .parallelTorusTorus(curve):
            return try curve.boundingBox(tolerance: tolerance)
        case let .congruentTorusTorus(curve):
            return try curve.boundingBox(tolerance: tolerance)
        case let .generalTorusTorus(curve):
            return try curve.boundingBox(tolerance: tolerance)
        case let .boundedPlaneCone(curve):
            return try curve.boundingBox(tolerance: tolerance)
        }
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        try firstSurface.validate(tolerance: tolerance)
        try secondSurface.validate(tolerance: tolerance)
        switch definition {
        case let .planeTorus(curve):
            try curve.validate(tolerance: tolerance)
            guard (firstSurface == curve.planeSurface
                && secondSurface == curve.torusSurface)
                || (firstSurface == curve.torusSurface
                    && secondSurface == curve.planeSurface) else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "A stored plane-torus curve changed source-surface order."
                )
            }
        case let .coneCone(curve):
            try curve.validate(tolerance: tolerance)
            let firstMatchesReference = isEquivalent(firstSurface, to: curve.referenceSurface)
            let firstMatchesParameterized = isEquivalent(
                firstSurface,
                to: curve.parameterizedSurface
            )
            let secondMatchesReference = isEquivalent(secondSurface, to: curve.referenceSurface)
            let secondMatchesParameterized = isEquivalent(
                secondSurface,
                to: curve.parameterizedSurface
            )
            guard (firstMatchesReference && secondMatchesParameterized)
                    || (firstMatchesParameterized && secondMatchesReference) else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "A stored cone-cone curve changed source-surface identity."
                )
            }
        case let .cylinderCylinder(curve):
            try curve.validate(tolerance: tolerance)
            guard (firstSurface == curve.referenceSurface
                && secondSurface == curve.parameterizedSurface)
                || (firstSurface == curve.parameterizedSurface
                    && secondSurface == curve.referenceSurface) else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "A stored cylinder-cylinder curve changed source-surface identity."
                )
            }
        case let .sphereCylinder(curve):
            try curve.validate(tolerance: tolerance)
            guard (firstSurface == curve.sphereSurface
                && secondSurface == curve.cylinderSurface)
                || (firstSurface == curve.cylinderSurface
                    && secondSurface == curve.sphereSurface) else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "A stored sphere-cylinder curve changed source-surface identity."
                )
            }
        case let .sphereCone(curve):
            try curve.validate(tolerance: tolerance)
            guard (firstSurface == curve.sphereSurface
                && secondSurface == curve.coneSurface)
                || (firstSurface == curve.coneSurface
                    && secondSurface == curve.sphereSurface) else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "A stored sphere-cone curve changed source-surface identity."
                )
            }
        case let .coneCylinder(curve):
            try curve.validate(tolerance: tolerance)
            guard (firstSurface == curve.coneSurface
                && secondSurface == curve.cylinderSurface)
                || (firstSurface == curve.cylinderSurface
                    && secondSurface == curve.coneSurface) else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "A stored cone-cylinder curve changed source-surface identity."
                )
            }
        case let .sphereTorus(curve):
            try curve.validate(tolerance: tolerance)
            guard (firstSurface == curve.sphereSurface
                && secondSurface == curve.torusSurface)
                || (firstSurface == curve.torusSurface
                    && secondSurface == curve.sphereSurface) else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "A stored sphere-torus curve changed source-surface identity."
                )
            }
        case let .parallelTorusCylinder(curve):
            try curve.validate(tolerance: tolerance)
            guard (firstSurface == curve.torusSurface
                && secondSurface == curve.cylinderSurface)
                || (firstSurface == curve.cylinderSurface
                    && secondSurface == curve.torusSurface) else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "A stored parallel torus-cylinder curve changed source-surface identity."
                )
            }
        case let .generalTorusCylinder(curve):
            try curve.validate(tolerance: tolerance)
            guard (firstSurface == curve.torusSurface
                && secondSurface == curve.cylinderSurface)
                || (firstSurface == curve.cylinderSurface
                    && secondSurface == curve.torusSurface) else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "A stored general torus-cylinder curve changed source-surface identity."
                )
            }
        case let .generalConeTorus(curve):
            try curve.validate(tolerance: tolerance)
            guard (firstSurface == curve.coneSurface
                && secondSurface == curve.torusSurface)
                || (firstSurface == curve.torusSurface
                    && secondSurface == curve.coneSurface) else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "A stored general cone-torus curve changed source-surface identity."
                )
            }
        case let .parallelTorusTorus(curve):
            try curve.validate(tolerance: tolerance)
            guard (firstSurface == curve.primarySurface
                && secondSurface == curve.secondarySurface)
                || (firstSurface == curve.secondarySurface
                    && secondSurface == curve.primarySurface) else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "A stored parallel torus-torus curve changed source-surface identity."
                )
            }
        case let .congruentTorusTorus(curve):
            try curve.validate(tolerance: tolerance)
            guard (firstSurface == curve.primarySurface
                && secondSurface == curve.secondarySurface)
                || (firstSurface == curve.secondarySurface
                    && secondSurface == curve.primarySurface) else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "A stored congruent torus-torus curve changed source-surface identity."
                )
            }
        case let .generalTorusTorus(curve):
            try curve.validate(tolerance: tolerance)
            guard (firstSurface == curve.parameterizedSurface
                && secondSurface == curve.referenceSurface)
                || (firstSurface == curve.referenceSurface
                    && secondSurface == curve.parameterizedSurface) else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "A stored general torus-torus curve changed source-surface identity."
                )
            }
        case let .boundedPlaneCone(curve):
            try curve.validate(tolerance: tolerance)
            guard (firstSurface == curve.planeSurface
                && secondSurface == curve.coneSurface)
                || (firstSurface == curve.coneSurface
                    && secondSurface == curve.planeSurface) else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "A stored bounded plane-cone curve changed source-surface identity."
                )
            }
        }
    }

    private func parameterCurve(
        for role: SurfaceIntersectionSurfaceRole
    ) -> SurfaceParameterCurve {
        .certifiedAnalyticPair(CertifiedAnalyticPairSurfaceParameterCurve(
            validatedIntersection: self,
            role: role,
            startFraction: 0.0,
            endFraction: 1.0
        ))
    }

    private func planeTorusParameter(
        _ fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> Double {
        guard fraction.isFinite,
              fraction >= -tolerance.relative,
              fraction <= 1.0 + tolerance.relative else {
            throw GeometryError.invalidDistance(fraction)
        }
        return min(max(fraction, 0.0), 1.0) * 2.0 * Double.pi
    }

    private func isEquivalent(_ first: Surface3D, to second: Surface3D) -> Bool {
        if first == second { return true }
        guard case let .cone(firstCone) = CanonicalAnalyticSurface(first),
              case let .cone(secondCone) = CanonicalAnalyticSurface(second) else {
            return false
        }
        return firstCone.apex == secondCone.apex
            && firstCone.halfAngle == secondCone.halfAngle
            && (firstCone.axis == secondCone.axis || firstCone.axis == -secondCone.axis)
    }

    private enum CodingKeys: String, CodingKey {
        case definition
        case firstSurface
        case secondSurface
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [.definition, .firstSurface, .secondSurface],
            in: decoder
        )
        let definition = try container.decode(Definition.self, forKey: .definition)
        let firstSurface = try container.decode(Surface3D.self, forKey: .firstSurface)
        let secondSurface = try container.decode(Surface3D.self, forKey: .secondSurface)
        switch definition {
        case let .planeTorus(curve):
            try self.init(
                planeTorusCurve: curve,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                tolerance: curve.certificationTolerance
            )
        case let .coneCone(curve):
            try self.init(
                coneConeCurve: curve,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                tolerance: curve.certificationTolerance
            )
        case let .cylinderCylinder(curve):
            try self.init(
                cylinderCylinderCurve: curve,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                tolerance: curve.certificationTolerance
            )
        case let .sphereCylinder(curve):
            try self.init(
                sphereCylinderCurve: curve,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                tolerance: curve.certificationTolerance
            )
        case let .sphereCone(curve):
            try self.init(
                sphereConeCurve: curve,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                tolerance: curve.certificationTolerance
            )
        case let .coneCylinder(curve):
            try self.init(
                coneCylinderCurve: curve,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                tolerance: curve.certificationTolerance
            )
        case let .sphereTorus(curve):
            try self.init(
                sphereTorusCurve: curve,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                tolerance: curve.certificationTolerance
            )
        case let .parallelTorusCylinder(curve):
            try self.init(
                parallelTorusCylinderCurve: curve,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                tolerance: curve.certificationTolerance
            )
        case let .generalTorusCylinder(curve):
            try self.init(
                generalTorusCylinderCurve: curve,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                tolerance: curve.certificationTolerance
            )
        case let .generalConeTorus(curve):
            try self.init(
                generalConeTorusCurve: curve,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                tolerance: curve.certificationTolerance
            )
        case let .parallelTorusTorus(curve):
            try self.init(
                parallelTorusTorusCurve: curve,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                tolerance: curve.certificationTolerance
            )
        case let .congruentTorusTorus(curve):
            try self.init(
                congruentTorusTorusCurve: curve,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                tolerance: curve.certificationTolerance
            )
        case let .generalTorusTorus(curve):
            try self.init(
                generalTorusTorusCurve: curve,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                tolerance: curve.certificationTolerance
            )
        case let .boundedPlaneCone(curve):
            try self.init(
                boundedPlaneConeCurve: curve,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                tolerance: curve.certificationTolerance
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: certificationTolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(definition, forKey: .definition)
        try container.encode(firstSurface, forKey: .firstSurface)
        try container.encode(secondSurface, forKey: .secondSurface)
    }
}
