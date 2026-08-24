/// The topological relation proven by one certified analytic intersection
/// family. A caller may use this relation without comparing a derived spline
/// cache or re-intersecting either curve with the surfaces that define it.
package enum CertifiedIntersectionComponentRelation: Equatable, Sendable {
    case sameEmbeddedComponent(isClosed: Bool)
    case disjointComponents
}

extension CertifiedAnalyticAnalyticIntersectionCurve {
    /// Returns a relation only when both curves carry the same deterministic
    /// component-completeness certificate. The relation is derived from the
    /// certified family's component discriminator, never from its fitted
    /// representation or from coordinate proximity.
    package func componentRelation(
        to other: CertifiedAnalyticAnalyticIntersectionCurve
    ) -> CertifiedIntersectionComponentRelation? {
        switch (definition, other.definition) {
        case let (.planeTorus(first), .planeTorus(second)):
            guard first.belongsToSameCertifiedFamily(as: second) else {
                return nil
            }
            let same = first.componentKind == second.componentKind
                && first.lowerMinorAngle == second.lowerMinorAngle
                && first.upperMinorAngle == second.upperMinorAngle
            let isClosed: Bool
            switch first.parameterDomain {
            case .periodic:
                isClosed = true
            case .bounded, .unbounded:
                isClosed = false
            }
            return same
                ? .sameEmbeddedComponent(isClosed: isClosed)
                : .disjointComponents
        case let (.coneCone(first), .coneCone(second)):
            guard first.belongsToSameCertifiedFamily(as: second),
                  first.componentKind != .apexReducedAngularInterval,
                  second.componentKind != .apexReducedAngularInterval else {
                return nil
            }
            let same = first.componentKind == second.componentKind
                && first.lowerAngle == second.lowerAngle
                && first.upperAngle == second.upperAngle
            return same
                ? .sameEmbeddedComponent(isClosed: true)
                : .disjointComponents
        case let (.cylinderCylinder(first), .cylinderCylinder(second)):
            guard first.belongsToSameCertifiedFamily(as: second) else {
                return nil
            }
            let same = first.componentKind == second.componentKind
                && first.lowerAngle == second.lowerAngle
                && first.upperAngle == second.upperAngle
            return same
                ? .sameEmbeddedComponent(isClosed: true)
                : .disjointComponents
        case let (.sphereCylinder(first), .sphereCylinder(second)):
            guard first.belongsToSameCertifiedFamily(as: second) else {
                return nil
            }
            let same = first.componentKind == second.componentKind
                && first.lowerAngle == second.lowerAngle
                && first.upperAngle == second.upperAngle
            let isClosed = first.componentKind != .negativeOpenAngularInterval
                && first.componentKind != .positiveOpenAngularInterval
            return same
                ? .sameEmbeddedComponent(isClosed: isClosed)
                : .disjointComponents
        case let (.sphereCone(first), .sphereCone(second)):
            guard first.belongsToSameCertifiedFamily(as: second),
                  first.componentKind != .apexReducedAngularInterval,
                  second.componentKind != .apexReducedAngularInterval else {
                return nil
            }
            let same = first.componentKind == second.componentKind
                && first.lowerAngle == second.lowerAngle
                && first.upperAngle == second.upperAngle
            let isClosed = first.componentKind != .negativeOpenAngularInterval
                && first.componentKind != .positiveOpenAngularInterval
            return same
                ? .sameEmbeddedComponent(isClosed: isClosed)
                : .disjointComponents
        case let (.coneCylinder(first), .coneCylinder(second)):
            guard first.belongsToSameCertifiedFamily(as: second),
                  first.componentKind != .apexLowerNodeInterval,
                  first.componentKind != .apexUpperNodeInterval,
                  second.componentKind != .apexLowerNodeInterval,
                  second.componentKind != .apexUpperNodeInterval else {
                return nil
            }
            let same = first.componentKind == second.componentKind
                && first.lowerAngle == second.lowerAngle
                && first.upperAngle == second.upperAngle
            let isClosed = first.componentKind != .rulingParallelLinear
            return same
                ? .sameEmbeddedComponent(isClosed: isClosed)
                : .disjointComponents
        case let (.sphereTorus(first), .sphereTorus(second)):
            guard first.belongsToSameCertifiedFamily(as: second) else {
                return nil
            }
            let same = first.componentKind == second.componentKind
                && first.lowerAngle == second.lowerAngle
                && first.upperAngle == second.upperAngle
            let isClosed = first.componentKind != .negativeOpenAngularInterval
                && first.componentKind != .positiveOpenAngularInterval
            return same
                ? .sameEmbeddedComponent(isClosed: isClosed)
                : .disjointComponents
        case let (.parallelTorusCylinder(first), .parallelTorusCylinder(second)):
            guard first.belongsToSameCertifiedFamily(as: second),
                  first.componentKind != .negativeInternalTangencyInterval,
                  first.componentKind != .positiveInternalTangencyInterval,
                  second.componentKind != .negativeInternalTangencyInterval,
                  second.componentKind != .positiveInternalTangencyInterval else {
                return nil
            }
            let same = first.componentKind == second.componentKind
                && first.lowerAngle == second.lowerAngle
                && first.upperAngle == second.upperAngle
            return same
                ? .sameEmbeddedComponent(isClosed: true)
                : .disjointComponents
        case let (.generalTorusCylinder(first), .generalTorusCylinder(second)):
            guard first.belongsToSameCertifiedFamily(as: second) else {
                return nil
            }
            return first.branchIndex == second.branchIndex
                ? .sameEmbeddedComponent(isClosed: true)
                : .disjointComponents
        case let (.generalTorusTorus(first), .generalTorusTorus(second)):
            guard first.belongsToSameCertifiedFamily(as: second) else {
                return nil
            }
            return first.componentIndex == second.componentIndex
                ? .sameEmbeddedComponent(isClosed: true)
                : .disjointComponents
        case let (.generalConeTorus(first), .generalConeTorus(second)):
            guard first.apexReduction == nil,
                  second.apexReduction == nil,
                  first.belongsToSameCertifiedFamily(as: second) else {
                return nil
            }
            return first.branchIndex == second.branchIndex
                ? .sameEmbeddedComponent(isClosed: true)
                : .disjointComponents
        case let (.parallelTorusTorus(first), .parallelTorusTorus(second)):
            guard first.belongsToSameCertifiedFamily(as: second) else {
                return nil
            }
            let same = first.componentKind == second.componentKind
                && first.branchIndex == second.branchIndex
            return same
                ? .sameEmbeddedComponent(isClosed: true)
                : .disjointComponents
        case let (.congruentTorusTorus(first), .congruentTorusTorus(second)):
            guard first.belongsToSameCertifiedFamily(as: second) else {
                return nil
            }
            let same = first.bisectorPlaneKind == second.bisectorPlaneKind
                && first.branchIndex == second.branchIndex
            return same
                ? .sameEmbeddedComponent(isClosed: true)
                : .disjointComponents
        case let (.boundedPlaneCone(first), .boundedPlaneCone(second)):
            guard first == second else { return nil }
            return .sameEmbeddedComponent(isClosed: false)
        default:
            return nil
        }
    }
}

private extension CertifiedPlaneTorusIntersectionCurve {
    func belongsToSameCertifiedFamily(
        as other: CertifiedPlaneTorusIntersectionCurve
    ) -> Bool {
        planeSurface == other.planeSurface
            && torusSurface == other.torusSurface
            && certificationTolerance == other.certificationTolerance
            && maximumResidualUpperBound == other.maximumResidualUpperBound
    }
}

private extension CertifiedGeneralTorusTorusIntersectionCurve {
    func belongsToSameCertifiedFamily(
        as other: CertifiedGeneralTorusTorusIntersectionCurve
    ) -> Bool {
        parameterizedSurface == other.parameterizedSurface
            && referenceSurface == other.referenceSurface
            && componentCount == other.componentCount
            && maximumSubdivisionDepth == other.maximumSubdivisionDepth
            && maximumIterations == other.maximumIterations
            && maximumSeedCount == other.maximumSeedCount
            && certificationTolerance == other.certificationTolerance
            && maximumResidualUpperBound == other.maximumResidualUpperBound
    }
}

private extension CertifiedConeConeIntersectionCurve {
    func belongsToSameCertifiedFamily(
        as other: CertifiedConeConeIntersectionCurve
    ) -> Bool {
        referenceSurface == other.referenceSurface
            && parameterizedSurface == other.parameterizedSurface
            && certificationTolerance == other.certificationTolerance
            && maximumResidualUpperBound == other.maximumResidualUpperBound
    }
}

private extension CertifiedCylinderCylinderIntersectionCurve {
    func belongsToSameCertifiedFamily(
        as other: CertifiedCylinderCylinderIntersectionCurve
    ) -> Bool {
        referenceSurface == other.referenceSurface
            && parameterizedSurface == other.parameterizedSurface
            && certificationTolerance == other.certificationTolerance
            && maximumResidualUpperBound == other.maximumResidualUpperBound
    }
}

private extension CertifiedSphereCylinderIntersectionCurve {
    func belongsToSameCertifiedFamily(
        as other: CertifiedSphereCylinderIntersectionCurve
    ) -> Bool {
        sphereSurface == other.sphereSurface
            && cylinderSurface == other.cylinderSurface
            && certificationTolerance == other.certificationTolerance
            && maximumResidualUpperBound == other.maximumResidualUpperBound
    }
}

private extension CertifiedSphereConeIntersectionCurve {
    func belongsToSameCertifiedFamily(
        as other: CertifiedSphereConeIntersectionCurve
    ) -> Bool {
        sphereSurface == other.sphereSurface
            && coneSurface == other.coneSurface
            && certificationTolerance == other.certificationTolerance
            && maximumResidualUpperBound == other.maximumResidualUpperBound
    }
}

private extension CertifiedConeCylinderIntersectionCurve {
    func belongsToSameCertifiedFamily(
        as other: CertifiedConeCylinderIntersectionCurve
    ) -> Bool {
        coneSurface == other.coneSurface
            && cylinderSurface == other.cylinderSurface
            && certificationTolerance == other.certificationTolerance
            && maximumResidualUpperBound == other.maximumResidualUpperBound
    }
}

private extension CertifiedSphereTorusIntersectionCurve {
    func belongsToSameCertifiedFamily(
        as other: CertifiedSphereTorusIntersectionCurve
    ) -> Bool {
        sphereSurface == other.sphereSurface
            && torusSurface == other.torusSurface
            && certificationTolerance == other.certificationTolerance
            && maximumResidualUpperBound == other.maximumResidualUpperBound
    }
}

private extension CertifiedParallelTorusCylinderIntersectionCurve {
    func belongsToSameCertifiedFamily(
        as other: CertifiedParallelTorusCylinderIntersectionCurve
    ) -> Bool {
        torusSurface == other.torusSurface
            && cylinderSurface == other.cylinderSurface
            && certificationTolerance == other.certificationTolerance
            && maximumResidualUpperBound == other.maximumResidualUpperBound
    }
}

private extension CertifiedGeneralTorusCylinderIntersectionCurve {
    func belongsToSameCertifiedFamily(
        as other: CertifiedGeneralTorusCylinderIntersectionCurve
    ) -> Bool {
        torusSurface == other.torusSurface
            && cylinderSurface == other.cylinderSurface
            && branchCount == other.branchCount
            && maximumSubdivisionDepth == other.maximumSubdivisionDepth
            && maximumCellCount == other.maximumCellCount
            && certificationTolerance == other.certificationTolerance
            && maximumResidualUpperBound == other.maximumResidualUpperBound
    }
}

private extension CertifiedGeneralConeTorusIntersectionCurve {
    func belongsToSameCertifiedFamily(
        as other: CertifiedGeneralConeTorusIntersectionCurve
    ) -> Bool {
        coneSurface == other.coneSurface
            && torusSurface == other.torusSurface
            && branchCount == other.branchCount
            && maximumSubdivisionDepth == other.maximumSubdivisionDepth
            && maximumCellCount == other.maximumCellCount
            && certificationTolerance == other.certificationTolerance
            && maximumResidualUpperBound == other.maximumResidualUpperBound
    }
}

private extension CertifiedParallelTorusTorusIntersectionCurve {
    func belongsToSameCertifiedFamily(
        as other: CertifiedParallelTorusTorusIntersectionCurve
    ) -> Bool {
        primarySurface == other.primarySurface
            && secondarySurface == other.secondarySurface
            && branchCount == other.branchCount
            && maximumSubdivisionDepth == other.maximumSubdivisionDepth
            && maximumCellCount == other.maximumCellCount
            && certificationTolerance == other.certificationTolerance
            && maximumResidualUpperBound == other.maximumResidualUpperBound
    }
}

private extension CertifiedCongruentTorusTorusIntersectionCurve {
    func belongsToSameCertifiedFamily(
        as other: CertifiedCongruentTorusTorusIntersectionCurve
    ) -> Bool {
        primarySurface == other.primarySurface
            && secondarySurface == other.secondarySurface
            && branchCount == other.branchCount
            && certificationTolerance == other.certificationTolerance
            && maximumResidualUpperBound == other.maximumResidualUpperBound
    }
}
