#if SOURCE_ISSUED_MAP_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
import DI0
import DI
import SourceIssuer
#endif

/// Whole pair authority; singleton graphs are restrictions of the retained full sources.
public final class OriginalAngularPlaneRelations<S: OriginalAnalyticCoordinateReading,
    P: OriginalPlaneSourceReading>: Sendable {
    public typealias Base = OriginalPiScalarDomain
    public typealias CurveCover = OriginalAnalyticDomainCover<S,Base>
    public typealias PlaneCover = OriginalPrimitiveDomainCover<P,Base,OriginalPlaneBasisReceipt<P,Base>>
    public struct RootDecision: Sendable {
        public let rootOrdinal: Int
        public let uv: [OriginalPiValue]
        public let planePosition: [OriginalPiValue]
        public let transverse: OriginalPiValue
        public let curveIncidents: [OriginalParameterTransport<S,Base>]
        public let planeIncidents: [OriginalParameterTransport<P,Base>]
        public let selected: Bool
    }
    public struct Pair: Sendable {
        public let rootOrdinal: Int
        public let first: ExactParametricGraph<Base>
        public let second: ExactParametricGraph<Base>
        public let relation: ExactParametricGraphRelation<Base>
    }
    public let curve: CurveCover
    public let plane: PlaneCover
    public let zeros: OriginalAnalyticCosineZeroReceipt<S,Base>
    public let incidence: ExactPolynomial<Base>
    public let cosineMultiple: ExactPolynomial<Base>
    public let incidenceResidual: ExactPolynomial<Base>
    public let coefficient: OriginalPiValue
    public let decisions: [RootDecision]
    public let pairs: [Pair]
    public let depth: ExactScalarDepth

    init(curve: CurveCover,plane: PlaneCover,zeros: OriginalAnalyticCosineZeroReceipt<S,Base>,
        incidence: ExactPolynomial<Base>,cosineMultiple: ExactPolynomial<Base>,
        incidenceResidual: ExactPolynomial<Base>,coefficient: OriginalPiValue,
        decisions: [RootDecision],pairs: [Pair],depth: ExactScalarDepth) {
        self.curve=curve;self.plane=plane;self.zeros=zeros;self.incidence=incidence
        self.cosineMultiple=cosineMultiple;self.incidenceResidual=incidenceResidual
        self.coefficient=coefficient;self.decisions=decisions;self.pairs=pairs;self.depth=depth
    }

    public func admitProof<A: ExactScalarAdmission & ~Copyable>(limits: OriginalDomainIdentityLimits,
        using a: inout A) throws {
        try a.checkpoint();try a.admitDepth(value:depth.value,coefficient:depth.coefficient)
        try zeros.admitProof(limits:limits.source,using:&a)
        guard limits.maximumCharts >= curve.templateCount,limits.maximumCharts >= plane.templateCount else {
            throw OriginalDomainIdentityFailure.chartLimit
        }
        guard limits.maximumFamilies >= curve.integerFamilyRank,limits.maximumFamilies >= plane.integerFamilyRank else {
            throw OriginalDomainIdentityFailure.familyLimit
        }
        let f=curve.law.field,ring=curve.law.polynomials
        let curveTransporter=DefaultOriginalParameterTransporter<S,Base>()
        let planeTransporter=DefaultOriginalParameterTransporter<P,Base>()
        guard try f.sign(of:coefficient,using:&a) != .zero,
            try ring.isZero(incidenceResidual,using:&a),
            try ring.equals(incidence,cosineMultiple,using:&a) else { throw NativeExactRelationFailure.invalidDomain }
        _=try plane.law.position(u:f.integer(0,using:&a),v:f.integer(0,using:&a),limits:limits,using:&a)
        for decision in decisions {
            try a.consumeWork(1)
            for incident in decision.curveIncidents {
                try a.consumeWork(1);try curveTransporter.admitted(incident,limits:limits,using:&a)
            }
            for incident in decision.planeIncidents {
                try a.consumeWork(1);try planeTransporter.admitted(incident,limits:limits,using:&a)
            }
            _=try f.sign(of:decision.transverse,using:&a)
            for value in decision.uv { _=try f.sign(of:value,using:&a) }
            for value in decision.planePosition { _=try f.sign(of:value,using:&a) }
        }
        for pair in pairs { try a.consumeWork(1);try pair.relation.admitProof(using:&a) }
        try a.checkpoint()
    }
}
