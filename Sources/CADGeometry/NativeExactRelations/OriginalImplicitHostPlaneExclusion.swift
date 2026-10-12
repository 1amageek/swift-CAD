/// Complete empty pair authority, retaining the source theorem and exact original requests.
public final class OriginalImplicitHostPlaneExclusion: Sendable {
    public typealias Base = OriginalExactScalarDomain
    public typealias Source = OriginalImplicitCurveSnapshot
    public typealias Interval = ExactParameterInterval<Base.Value>
    public typealias CurveSelection = OriginalParameterSelection<Source,Base>
    public typealias PlaneCover = OriginalPrimitiveDomainCover<OriginalPlaneSnapshot,Base,
        OriginalPlaneBasisReceipt<OriginalPlaneSnapshot,Base>>

    public let exclusion: OriginalImplicitHostPlaneSeparationReceipt
    public let support: CurveSelection
    public let request: CurveSelection
    public let effective: CurveSelection
    public let plane: PlaneCover
    public let proofDepth: ExactScalarDepth

    public var isEmpty: Bool { true }
    public var hasPositiveDimensionalSolutions: Bool { false }
    public var hasPositiveDimensionalImage: Bool { false }

    private init(exclusion: OriginalImplicitHostPlaneSeparationReceipt,
        support: CurveSelection,request: CurveSelection,effective: CurveSelection,
        plane: PlaneCover,proofDepth: ExactScalarDepth) {
        self.exclusion=exclusion;self.support=support;self.request=request
        self.effective=effective;self.plane=plane;self.proofDepth=proofDepth
    }

    static func resolve<A: ExactScalarAdmission & ~Copyable>(
        exclusion: OriginalImplicitHostPlaneSeparationReceipt,
        curveIntervals: borrowing [Interval],planeIntervals: borrowing [[Interval]],
        limits: OriginalDomainIdentityLimits,using a: inout A) throws -> OriginalImplicitHostPlaneExclusion {
        let curveIntervals=copy curveIntervals,planeIntervals=copy planeIntervals
        return try OriginalSourceProofAdmission<A>.withBorrow(&a) { a in
            try a.checkpoint();try exclusion.admitProof(maximumCells:limits.maximumCharts,limits:limits.source,using:&a)
            guard limits.maximumCharts >= exclusion.cellCount else { throw OriginalDomainIdentityFailure.chartLimit }
            let f=exclusion.field
            let authored=try Interval.checked(field:f,lower:.finite(exclusion.support.lower),
                upper:.finite(exclusion.support.upper),depth:exclusion.proofDepth,using:&a)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:[Interval].self))
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Interval.self))
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalCoordinateSemantics.self))
            let frame=try DefaultOriginalParameterTransporter<Source,Base>().frame(
                source:exclusion.source,field:f,support:[[authored]],semantics:[.authoredScalar],
                limits:limits,using:&a)
            let support=try frame.fullSelection(limits:limits,using:&a)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:[Interval].self))
            let request=try frame.selection(intervals:[curveIntervals],limits:limits,using:&a)
            let effective=try request.intersection(support,limits:limits,using:&a)
            let planeIssuer=DefaultOriginalPlaneDomainIssuer<OriginalPlaneSnapshot,Base>()
            let planeFrame=try planeIssuer.frame(basis:exclusion.plane,limits:limits,using:&a)
            let planeRequest=try planeFrame.selection(intervals:planeIntervals,limits:limits,using:&a)
            let plane=try planeIssuer.issue(request:planeRequest,basis:exclusion.plane,limits:limits,using:&a)
            let attained=try a.depth
            var value=max(exclusion.proofDepth.value,attained.value)
            var coefficient=max(exclusion.proofDepth.coefficient,attained.coefficient)
            try joinDepth(support,value:&value,coefficient:&coefficient,using:&a)
            try joinDepth(request,value:&value,coefficient:&coefficient,using:&a)
            try joinDepth(effective,value:&value,coefficient:&coefficient,using:&a)
            try joinDepth(plane.support,value:&value,coefficient:&coefficient,using:&a)
            try joinDepth(plane.request,value:&value,coefficient:&coefficient,using:&a)
            try joinDepth(plane.effective,value:&value,coefficient:&coefficient,using:&a)
            let depth=try ExactScalarDepth(value:value,coefficient:coefficient)
            try a.admitDepth(value:depth.value,coefficient:depth.coefficient)
            let header=try exactScalarPayloadBytes(count:2,of:UnsafeRawPointer.self)
            let payload=MemoryLayout<(OriginalImplicitHostPlaneSeparationReceipt,
                CurveSelection,CurveSelection,CurveSelection,PlaneCover,ExactScalarDepth)>.stride
            let bytes=header.addingReportingOverflow(payload)
            guard !bytes.overflow else { throw ExactScalarFailure.countOverflow }
            try a.retainStorage(bytes:bytes.partialValue)
            let result=OriginalImplicitHostPlaneExclusion(exclusion:exclusion,support:support,
                request:request,effective:effective,plane:plane,proofDepth:depth)
            try a.checkpoint();return result
        }
    }

    public func admitProof<A: ExactScalarAdmission & ~Copyable>(limits: OriginalDomainIdentityLimits,
        using a: inout A) throws {
        try a.checkpoint();try a.admitDepth(value:proofDepth.value,coefficient:proofDepth.coefficient)
        try exclusion.admitProof(maximumCells:limits.maximumCharts,limits:limits.source,using:&a)
        guard limits.maximumCharts >= plane.templateCount else { throw OriginalDomainIdentityFailure.chartLimit }
        guard limits.maximumFamilies >= plane.integerFamilyRank else { throw OriginalDomainIdentityFailure.familyLimit }
        try Self.admit(support,limits:limits,using:&a)
        try Self.admit(request,limits:limits,using:&a)
        try Self.admit(effective,limits:limits,using:&a)
        try Self.admit(plane.support,limits:limits,using:&a)
        try Self.admit(plane.request,limits:limits,using:&a)
        try Self.admit(plane.effective,limits:limits,using:&a)
        try a.checkpoint()
    }

    private static func joinDepth<S: Sendable,A: ExactScalarAdmission & ~Copyable>(
        _ selection: borrowing OriginalParameterSelection<S,Base>,value: inout Int,
        coefficient: inout Int,using a: inout A) throws {
        for axis in selection.axes {
            try a.consumeWork(1)
            value=max(value,axis.depth.value);coefficient=max(coefficient,axis.depth.coefficient)
        }
    }

    private static func admit<S: Sendable,A: ExactScalarAdmission & ~Copyable>(
        _ selection: borrowing OriginalParameterSelection<S,Base>,limits: OriginalDomainIdentityLimits,
        using a: inout A) throws {
        guard selection.frame.source.sourceDepth <= limits.source.remainingSourceDepth else {
            throw OriginalDomainIdentityFailure.sourceDepthLimit
        }
        let f=selection.frame.scalarField
        for axis in selection.axes {
            try a.consumeWork(1);try a.admitDepth(value:axis.depth.value,coefficient:axis.depth.coefficient)
            for interval in axis.intervals {
                try a.consumeWork(1)
                try a.admitDepth(value:interval.depth.value,coefficient:interval.depth.coefficient)
                if case .finite(let value)=interval.lower { _=try f.sign(of:value,using:&a) }
                if case .finite(let value)=interval.upper { _=try f.sign(of:value,using:&a) }
            }
        }
    }
}
