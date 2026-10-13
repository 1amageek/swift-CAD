import CADCore

/// Selects the exact original quadratic, never the regenerated candidate metric.
public struct OriginalCertifiedCoaxialConeCylinderSnapshotProvider: OriginalSourceSnapshotting {
    public let field: OriginalPhysicalAngleScalarDomain
    public let tolerance: ModelingTolerance
    public init(field: OriginalPhysicalAngleScalarDomain, tolerance: ModelingTolerance) {
        self.field=field; self.tolerance=tolerance
    }

    public static func supports(_ curve: Curve3D) -> Bool {
        guard case .certifiedIntersection(.coneCylinder(let original))=curve,
            case .analytic(.cone(let apex,let coneAxis,_))=original.coneSurface,
            case .analytic(.cylinder(let origin,let cylinderAxis,let radius))=original.cylinderSurface,
            apex == .origin, origin == .origin, coneAxis == .unitZ, cylinderAxis == .unitZ,
            radius == 1, original.lowerAngle == 0, original.upperAngle == 2*Double.pi else { return false }
        switch original.componentKind {
        case .negativeFullBranch,.positiveFullBranch: return true
        default: return false
        }
    }

    public func snapshot<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing Curve3D,
        limits: OriginalSourceIssuanceLimits, using a: inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<OriginalCertifiedCoaxialConeCylinderSnapshot> {
        let input=copy input
        do {
            try a.checkpoint(); try a.consumeWork(1)
            guard Self.supports(input),
                case .certifiedIntersection(.coneCylinder(let original))=input,
                case .analytic(.cone(_,_,let angle))=original.coneSurface else {
                throw OriginalSourceIssuanceFailure.unsupportedRepresentation
            }
            guard limits.remainingSourceDepth>=1 else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
            guard angle==field.originalRadians else { throw OriginalSourceIssuanceFailure.foreignBinding }
            try original.validate(tolerance:tolerance)
            let sine=try field.sine(using:&a), cosine=try field.cosine(using:&a)
            guard try field.sign(of:sine,using:&a) == .positive,
                try field.sign(of:cosine,using:&a) == .positive else { throw OriginalSourceIssuanceFailure.invalidSource }
            let one=try field.integer(1,using:&a),zero=try field.integer(0,using:&a)
            let sign=try field.integer(original.componentKind == .negativeFullBranch ? 1:-1,using:&a)
            let slant=try field.dividing(sign,sine,using:&a)
            let height=try field.multiplying(cosine,slant,using:&a)
            let period=try field.binary64(exactly:2*Double.pi,using:&a)
            let offset=original.componentKind == .negativeFullBranch ? zero:
                try field.dividing(period,field.integer(2,using:&a),using:&a)
            // Verify the original cone metric and cylinder radius at the selected root.
            let radius=try field.multiplying(sine,slant,using:&a)
            guard try field.compare(field.multiplying(radius,radius,using:&a),one,using:&a) == .equal else {
                throw OriginalSourceIssuanceFailure.invalidSource
            }
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalCertifiedCoaxialConeCylinderSnapshot.self))
            let h=try height.depth, v=try slant.depth, p=try period.depth, o=try offset.depth
            let depth=try ExactScalarDepth(value:max(h.value,v.value,p.value,o.value),
                coefficient:max(h.coefficient,v.coefficient,p.coefficient,o.coefficient))
            try a.admitDepth(value:depth.value,coefficient:depth.coefficient)
            let result=OriginalCertifiedCoaxialConeCylinderSnapshot(original:original,field:field,
                height:height,coneSlant:slant,labelPeriod:period,conePhaseOffset:offset,proofDepth:depth)
            try a.checkpoint(); return .init(original:result,sourceDepth:1)
        } catch { throw .init(preserving:error) }
    }
}
