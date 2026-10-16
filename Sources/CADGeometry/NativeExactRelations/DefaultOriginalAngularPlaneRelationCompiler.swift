#if SOURCE_ISSUED_MAP_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
import DI0
import DI
@testable import SourceIssuer
#endif

/// Composes the source zero theorem with the actual plane's checked inverse.
public struct DefaultOriginalAngularPlaneRelationCompiler<S: OriginalAnalyticCoordinateReading,
    P: OriginalPlaneSourceReading>: Sendable {
    public typealias Result = OriginalAngularPlaneRelations<S,P>
    public typealias Base = OriginalPiScalarDomain
    public typealias Field = ExactAlgebraicScalarDomain<Base>
    public init() {}

    public func resolve<A: ExactScalarAdmission & ~Copyable>(curve: Result.CurveCover,
        plane: Result.PlaneCover,maximumPairs: Int,maximumExtensionLevel: Int,
        limits: OriginalDomainIdentityLimits,cellLimits: ExactRealCellLimits,
        topologyLimits: ExactRealTopologyLimits,using a: inout A) throws -> Result {
        try a.withProofScope() { tracked in
            try resolveTracked(curve:curve,plane:plane,maximumPairs:maximumPairs,
                maximumExtensionLevel:maximumExtensionLevel,limits:limits,
                cellLimits:cellLimits,topologyLimits:topologyLimits,using:&tracked)
        }
    }
    private func resolveTracked<A: ExactScalarAdmission & ~Copyable>(curve: Result.CurveCover,
        plane: Result.PlaneCover,maximumPairs: Int,maximumExtensionLevel: Int,
        limits: OriginalDomainIdentityLimits,cellLimits: ExactRealCellLimits,
        topologyLimits: ExactRealTopologyLimits,using a: inout A) throws -> Result {
        try a.checkpoint()
        guard maximumPairs >= 0 else { throw NativeExactRelationFailure.invalidDomain }
        let zeros=try DefaultOriginalAnalyticCosineZeroIssuer<S,Base>()
            .issue(law:curve.law,limits:limits.source,using:&a)
        let f=curve.law.field,ring=curve.law.polynomials,basis=plane.law
        let zero=try f.integer(0,using:&a),one=try f.integer(1,using:&a)
        _=try basis.position(u:zero,v:zero,limits:limits,using:&a)
        var incidence=try ring.zero(using:&a)
        for axis in 0..<3 {
            try a.consumeWork(1)
            incidence=try ring.adding(incidence,ring.scaled(ring.subtracting(curve.law.position[axis],
                ring.constant(basis.origin[axis],using:&a),using:&a),by:basis.normal[axis],using:&a),using:&a)
        }
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:OriginalPiValue.self))
        let evaluation=try ring.evaluated(incidence,at:[one,zero],using:&a)
        try a.admitDepth(value:evaluation.depth.value,coefficient:evaluation.depth.coefficient)
        let coefficient=evaluation.value
        let multiple=try ring.scaled(ring.variable(0,using:&a),by:coefficient,using:&a)
        let residual=try ring.subtracting(incidence,multiple,using:&a)
        guard try f.sign(of:coefficient,using:&a) != .zero,
            try ring.isZero(residual,using:&a),try ring.equals(incidence,multiple,using:&a) else {
            throw NativeExactRelationFailure.unsupportedCoverage
        }
        let field=try Field.base(field:f,maximumExtensionLevel:maximumExtensionLevel,using:&a)
        typealias Cells=ExactRealCellDomain<Base>
        let solver=ExactParametricRelationDomain<Base,Cells,ExactRealTopology<Base>>(
            cells:Cells.self,topology:.init(cells:Cells.self))
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:zeros.roots.count,of:Result.RootDecision.self))
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:min(zeros.roots.count,maximumPairs),of:Result.Pair.self))
        var decisions:[Result.RootDecision]=[],pairs:[Result.Pair]=[]
        decisions.reserveCapacity(zeros.roots.count);pairs.reserveCapacity(min(zeros.roots.count,maximumPairs))
        for index in zeros.roots.indices {
            try a.consumeWork(1)
            let root=zeros.roots[index]
            let uv=try basis.parameters(of:root.position,limits:limits,using:&a)
            let reconstructed=try basis.position(u:uv[0],v:uv[1],limits:limits,using:&a)
            var transverse=zero
            for axis in 0..<3 {
                try a.consumeWork(1)
                guard try f.compare(root.position[axis],reconstructed[axis],using:&a) == .equal else {
                    throw NativeExactRelationFailure.invalidDomain
                }
                transverse=try f.adding(transverse,f.multiplying(basis.normal[axis],root.derivative[axis],using:&a),using:&a)
            }
            guard try f.sign(of:transverse,using:&a) != .zero else { throw NativeExactRelationFailure.unsupportedCoverage }
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalPiValue.self))
            let tuple=[root.parameter]
            let curveIncluded=try curve.effective.contains(tuple,limits:limits,using:&a)
            let planeIncluded=try plane.effective.contains(uv,limits:limits,using:&a)
            let curveIncidents=try curve.incident(at:tuple,limits:limits,using:&a)
            let planeIncidents=try plane.incident(at:uv,limits:limits,using:&a)
            decisions.append(.init(rootOrdinal:index,uv:uv,planePosition:reconstructed,transverse:transverse,
                curveIncidents:curveIncidents,planeIncidents:planeIncidents,selected:curveIncluded && planeIncluded))
            if !curveIncluded || !planeIncluded { continue }
            guard pairs.count < maximumPairs else { throw NativeExactRelationFailure.resultLimit }
            let first=try graph(position:root.position,parameters:tuple,field:field,solver:solver,using:&a)
            let second=try graph(position:reconstructed,parameters:uv,field:field,solver:solver,using:&a)
            let input=try solver.compile(kind:.curveSurface,first:first,second:second,using:&a)
            let relation=try solver.resolve(input,cellLimits:cellLimits,topologyLimits:topologyLimits,using:&a)
            guard relation.selection.cells.count == 1,relation.selection.cells[0].dimension == 0 else {
                throw NativeExactRelationFailure.invalidDomain
            }
            pairs.append(.init(rootOrdinal:index,first:first,second:second,relation:relation))
        }
        let depth=try a.depth
        let headers=try exactScalarPayloadBytes(count:2,of:UInt.self)
        let payload=MemoryLayout<(Result.CurveCover,Result.PlaneCover,OriginalAnalyticCosineZeroReceipt<S,Base>,
            ExactPolynomial<Base>,ExactPolynomial<Base>,ExactPolynomial<Base>,OriginalPiValue,
            [Result.RootDecision],[Result.Pair],ExactScalarDepth)>.stride
        let bytes=headers.addingReportingOverflow(payload)
        guard !bytes.overflow else { throw ExactScalarFailure.countOverflow }
        try a.retainStorage(bytes:bytes.partialValue)
        let result=Result(curve:curve,plane:plane,zeros:zeros,incidence:incidence,cosineMultiple:multiple,
            incidenceResidual:residual,coefficient:coefficient,decisions:decisions,pairs:pairs,depth:depth)
        try a.checkpoint();return result
    }
    private func graph<A: ExactScalarAdmission & ~Copyable>(position:[OriginalPiValue],parameters:[OriginalPiValue],
        field:Field,solver:ExactParametricRelationDomain<Base,ExactRealCellDomain<Base>,ExactRealTopology<Base>>,
        using a:inout A) throws -> ExactParametricGraph<Base> {
        let cells=try ExactRealCellDomain<Base>(field:field,variableCount:parameters.count,using:&a)
        let ring=cells.polynomials,roots=try ExactRealRootDomain(field:field,using:&a)
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:4,of:ExactPolynomial<Field>.self))
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:parameters.count,of:ExactRealRootInterval<Field.Value>.self))
        var laws:[ExactPolynomial<Field>]=[],domains:[ExactRealRootInterval<Field.Value>]=[]
        laws.reserveCapacity(4);domains.reserveCapacity(parameters.count)
        for value in position { try a.consumeWork(1);laws.append(try ring.constant(field.importingBase(value,using:&a),using:&a)) }
        laws.append(try ring.constant(field.integer(1,using:&a),using:&a))
        for value in parameters {
            try a.consumeWork(1)
            let coordinate=try field.importingBase(value,using:&a)
            domains.append(try roots.domain(lower:.finite(coordinate),upper:.finite(coordinate),includesLower:true,includesUpper:true,using:&a))
        }
        let source=try cells.bind(polynomials:laws,domains:domains,using:&a)
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:ExactRealCellInstruction.self))
        let predicate=try cells.predicate(instructions:[.literal(true)],for:source,using:&a)
        return try solver.graph(from:predicate,parameterCount:parameters.count,using:&a)
    }
}
