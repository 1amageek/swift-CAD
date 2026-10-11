import CADCore
@testable import CADGeometry
@testable import PolylineLiftAdapters
@testable import PublicLiftPlane
import enum PublicLiftPlane.NativeExactGeometryPublicationFailure
import enum PublicLiftPlane.GeometryExactScalarFailure
import struct PublicLiftPlane.DefaultExactOriginalScalarTransporter
import class PublicLiftPlane.ExactAlgebraicCalculation
import struct PublicLiftPlane.ExactAlgebraicEmbedding
import protocol PublicLiftPlane.ExactAlgebraicExtending
import struct PublicLiftPlane.ExactAlgebraicExtension
import struct PublicLiftPlane.ExactAlgebraicScalar
import struct PublicLiftPlane.ExactAlgebraicScalarDomain
import struct PublicLiftPlane.ExactOriginalScalarTransferReceipt
import protocol PublicLiftPlane.ExactOriginalScalarTransferring
import struct PublicLiftPlane.ExactRealRoot
import enum PublicLiftPlane.ExactRealRootBound
import enum PublicLiftPlane.ExactRealRootClassification
import struct PublicLiftPlane.ExactRealRootCount
import struct PublicLiftPlane.ExactRealRootDomain
import enum PublicLiftPlane.ExactRealRootFailure
import struct PublicLiftPlane.ExactRealRootInterval
import struct PublicLiftPlane.ExactRealRootLimits
import protocol PublicLiftPlane.ExactRealRootPreparing
import protocol PublicLiftPlane.ExactRealRootProducing
import protocol PublicLiftPlane.ExactRealRootQuerying
import struct PublicLiftPlane.ExactRealRootSeparation
import struct PublicLiftPlane.ExactRealRootSet
import struct PublicLiftPlane.ExactRealRootSigns
import struct PublicLiftPlane.ExactRealRootSource
import struct PublicLiftPlane.ExactRealRootTransport
import protocol PublicLiftPlane.ExactRealRootTransporting
import struct PublicLiftPlane.ExactRealCellBoundaryRoot
import struct PublicLiftPlane.ExactRealCellCondition
import struct PublicLiftPlane.ExactRealCellDefinition
import struct PublicLiftPlane.ExactRealCellDefinitionStep
import protocol PublicLiftPlane.ExactRealCellDescribing
import struct PublicLiftPlane.ExactRealCellDomain
import enum PublicLiftPlane.ExactRealCellFailure
import struct PublicLiftPlane.ExactRealCellID
import enum PublicLiftPlane.ExactRealCellInstruction
import enum PublicLiftPlane.ExactRealCellKind
import struct PublicLiftPlane.ExactRealCellLimits
import struct PublicLiftPlane.ExactRealCellPartition
import struct PublicLiftPlane.ExactRealCellPredicate
import protocol PublicLiftPlane.ExactRealCellPreparing
import protocol PublicLiftPlane.ExactRealCellProducing
import struct PublicLiftPlane.ExactRealCellProjectionBinding
import struct PublicLiftPlane.ExactRealCellProjectionEvidence
import enum PublicLiftPlane.ExactRealCellProjectionWitness
import protocol PublicLiftPlane.ExactRealCellQuerying
import struct PublicLiftPlane.ExactRealCellSample
import protocol PublicLiftPlane.ExactRealCellSelecting
import struct PublicLiftPlane.ExactRealCellSelection
import struct PublicLiftPlane.ExactRealCellSignInvariant
import enum PublicLiftPlane.ExactRealCellSignRelation
import struct PublicLiftPlane.ExactRealCellSource
import struct PublicLiftPlane.ExactRealCellStackEvidence
import protocol PublicLiftPlane.ExactRealCellTraversing
import struct PublicLiftPlane.ExactRealCellView
import struct PublicLiftPlane.ExactRealAttachment
import struct PublicLiftPlane.ExactRealCellPullback
import protocol PublicLiftPlane.ExactRealCellPullbackResolving
import struct PublicLiftPlane.ExactRealClosure
import protocol PublicLiftPlane.ExactRealClosureProducing
import enum PublicLiftPlane.ExactRealClosureProof
import enum PublicLiftPlane.ExactRealClosureStrategy
import struct PublicLiftPlane.ExactRealComponents
import protocol PublicLiftPlane.ExactRealComponentsProducing
import struct PublicLiftPlane.ExactRealIncidence
import struct PublicLiftPlane.ExactRealIncidencePair
import protocol PublicLiftPlane.ExactRealIncidenceProducing
import struct PublicLiftPlane.ExactRealProjection
import struct PublicLiftPlane.ExactRealProjectionLifts
import protocol PublicLiftPlane.ExactRealProjectionProducing
import typealias PublicLiftPlane.ExactRealTopology
import struct PublicLiftPlane.ExactRealTopologyDomain
import struct PublicLiftPlane.ExactRealTopologyElimination
import struct PublicLiftPlane.ExactRealTopologyFactor
import enum PublicLiftPlane.ExactRealTopologyFailure
import struct PublicLiftPlane.ExactRealTopologyLimits
import protocol PublicLiftPlane.ExactRealTopologyQuerying
import struct PublicLiftPlane.ExactRealTopologyReduction
import struct PublicLiftPlane.ExactRealTopologyRegion
import struct PublicLiftPlane.ExactRealTopologySignInvariant
import struct PublicLiftPlane.ExactParametricConstraintDivision
import struct PublicLiftPlane.ExactParametricGraph
import protocol PublicLiftPlane.ExactParametricGraphConstructing
import struct PublicLiftPlane.ExactParametricGraphRelation
import struct PublicLiftPlane.ExactParametricGraphRelationSource
import protocol PublicLiftPlane.ExactParametricGraphResolving
import struct PublicLiftPlane.ExactParametricGuardDivision
import struct PublicLiftPlane.ExactParametricGuardRemainder
import struct PublicLiftPlane.ExactParametricMap
import struct PublicLiftPlane.ExactParametricRelation
import protocol PublicLiftPlane.ExactParametricRelationConstructing
import struct PublicLiftPlane.ExactParametricRelationDomain
import enum PublicLiftPlane.ExactParametricRelationFailure
import enum PublicLiftPlane.ExactParametricRelationKind
import protocol PublicLiftPlane.ExactParametricRelationResolving
import struct PublicLiftPlane.ExactParametricRelationSource
import struct PublicLiftPlane.ExactParametricSquareReduction
import struct PublicLiftPlane.DefaultExactGeometricGraphRelationResolver
import struct PublicLiftPlane.DefaultExactGeometricRelationResolver
import enum PublicLiftPlane.ExactCurveParameterBoundary
import struct PublicLiftPlane.ExactCurveParameterSpan
import enum PublicLiftPlane.ExactGeometricEvidenceKind
import struct PublicLiftPlane.ExactGeometricFiber
import struct PublicLiftPlane.ExactGeometricGraphFiber
import struct PublicLiftPlane.ExactGeometricGraphPoint
import struct PublicLiftPlane.ExactGeometricGraphRelation
import protocol PublicLiftPlane.ExactGeometricGraphRelationResolving
import struct PublicLiftPlane.ExactGeometricRelation
import enum PublicLiftPlane.ExactGeometricRelationFailure
import struct PublicLiftPlane.ExactGeometricRelationLimits
import protocol PublicLiftPlane.ExactGeometricRelationQuerying
import protocol PublicLiftPlane.ExactGeometricRelationResolving
import enum PublicLiftPlane.ExactGeometricStation
import struct PublicLiftPlane.ExactGeometricStratumID
import struct PublicLiftPlane.ExactGeometricStratumRecord
import struct PublicLiftPlane.ExactGeometricStratumView
import struct PublicLiftPlane.ExactUV
import struct PublicLiftPlane.ExactXYZ
import struct PublicLiftPlane.DefaultOriginalIssuedGraphCompiler
import struct PublicLiftPlane.DefaultOriginalIssuedGraphParameterRefiner
import struct PublicLiftPlane.DefaultOriginalIssuedGraphRelationResolver
import enum PublicLiftPlane.NativeExactRelationFailure
import protocol PublicLiftPlane.OriginalIssuedGraphCompiling
import struct PublicLiftPlane.OriginalIssuedGraphFamily
import protocol PublicLiftPlane.OriginalIssuedGraphFamilyPreparing
import struct PublicLiftPlane.OriginalIssuedGraphParameterRefinement
import protocol PublicLiftPlane.OriginalIssuedGraphParameterRefining
import struct PublicLiftPlane.OriginalIssuedGraphPreparation
import protocol PublicLiftPlane.OriginalIssuedGraphRelationOwning
import struct PublicLiftPlane.OriginalIssuedGraphRelationPair
import protocol PublicLiftPlane.OriginalIssuedGraphRelationResolving
import struct PublicLiftPlane.OriginalIssuedGraphRelations
import struct PublicLiftPlane.DefaultOriginalIssuedGeometricRelationResolver
import enum PublicLiftPlane.NativeExactGeometricRelationFailure
import struct PublicLiftPlane.OriginalIssuedExactIntersectionPoint
import struct PublicLiftPlane.OriginalIssuedGeometricRelationPair
import protocol PublicLiftPlane.OriginalIssuedGeometricRelationReading
import protocol PublicLiftPlane.OriginalIssuedGeometricRelationResolving
import struct PublicLiftPlane.OriginalIssuedGeometricRelations
import struct PublicLiftPlane.OriginalLiftPlaneParameterRestriction
import protocol PublicLiftPlane.OriginalPlaneGraphCompiling
import struct PublicLiftPlane.OriginalIssuedPlaneGraph
import struct PublicLiftPlane.DefaultOriginalPlaneGraphCompiler
import struct PublicLiftPlane.OriginalLiftPlaneRelations
import protocol PublicLiftPlane.OriginalLiftPlaneRelationResolving
import struct PublicLiftPlane.DefaultOriginalLiftPlaneRelationResolver
import struct PublicLiftPlane.OriginalLiftPlaneGeometricRelations
import CADCore


import PublicCoonsSelf

import struct PolylineLiftAdapters.OriginalFiniteBSplineCharts

import struct PolylineLiftAdapters.OriginalBSplineSurfaceSnapshotProvider

#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
#endif

/// Original offset construction retaining its child and exact distance bits.
public protocol OriginalOffsetSourceReading:Sendable {
    associatedtype Child:Sendable
    var originalChild:OriginalSourceBinding<Child> { get }
    var originalDistance:Double { get }
}

import CADCore

/// Retains actual construction; numerical query tolerance remains caller-owned.
public struct OriginalOffsetSnapshot<Child:Sendable>:OriginalOffsetSourceReading {
    public let original:OffsetSurface3D
    public let originalChild:OriginalSourceBinding<Child>
    public var originalDistance:Double { original.distance }
    init(original:OffsetSurface3D,originalChild:OriginalSourceBinding<Child>) {
        self.original=original;self.originalChild=originalChild
    }
}

import CADCore

public struct OriginalOffsetSnapshotProvider<Child:OriginalSourceSnapshotting>:OriginalSourceSnapshotting where Child.Input == Surface3D {
    public let child:Child
    public init(child:Child) { self.child=child }
    public func snapshot<A:ExactScalarAdmission & ~Copyable>(_ input:borrowing OffsetSurface3D,
        limits:OriginalSourceIssuanceLimits,using a:inout A) throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<OriginalOffsetSnapshot<Child.Source>> {
        do {
            try a.checkpoint();try a.consumeWork(1)
            guard input.distance.isFinite else { throw GeometryError.invalidDistance(input.distance) }
            guard limits.remainingSourceDepth>0 else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
            let binding=try DefaultOriginalSourceBindingIssuer(provider:child).bind(input.source,
                limits:.init(remainingSourceDepth:limits.remainingSourceDepth-1),using:&a)
            let depth=binding.sourceDepth.addingReportingOverflow(1)
            guard !depth.overflow else { throw OriginalSourceIssuanceFailure.countOverflow }
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalOffsetSnapshot<Child.Source>.self))
            let result=OriginalOffsetSnapshot(original:copy input,originalChild:binding)
            try a.checkpoint();return .init(original:result,sourceDepth:depth.partialValue)
        } catch { throw .init(preserving:error) }
    }
}

import CADCore

/// The Native surface capability is explicit; other families use their own provider.
public struct OriginalNativeSurfaceFamilySnapshotProvider: OriginalSourceSnapshotting {
    public let tolerance: ModelingTolerance
    public init(tolerance: ModelingTolerance) { self.tolerance = tolerance }
    public func snapshot<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing Surface3D,
        limits: OriginalSourceIssuanceLimits, using admission: inout A
    ) throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<BSplineSurface3D> {
        guard case .bSpline(let source) = copy input else { throw .unsupportedRepresentation }
        return try OriginalBSplineSurfaceSnapshotProvider(tolerance: tolerance)
            .snapshot(source, limits: limits, using: &admission)
    }
}

#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

public protocol OriginalOffsetLawIssuing {
    associatedtype Source:OriginalOffsetSourceReading
    associatedtype ChildSelection:Sendable
    associatedtype Field:ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting where Field.Source == Field.Value
    func issue<A:ExactScalarAdmission & ~Copyable>(source:borrowing OriginalSourceBinding<Source>,
        child:borrowing OriginalRationalChartReceipt<Source.Child,ChildSelection,Field>,field:borrowing Field,
        limits:OriginalSourceIssuanceLimits,using a:inout A) throws(OriginalSourceIssuanceFailure)
        -> OriginalOffsetLawReceipt<Source,ChildSelection,Field>
}

#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Original offset relation in (authored U, authored V, positive q).
public struct OriginalOffsetLawReceipt<S:OriginalOffsetSourceReading,C:Sendable,
    F:ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>:Sendable where F.Source == F.Value {
    public let source:OriginalSourceBinding<S>
    public let child:OriginalRationalChartReceipt<S.Child,C,F>
    public let field:F
    public let polynomials:ExactPolynomialDomain<F>
    public let homogeneous:[ExactPolynomial<F>]
    public let normalSquared:ExactPolynomial<F>
    /// q^2-normalSquared==0 together with q>0 defines the unique original normal length.
    public let positiveRootEquation:ExactPolynomial<F>
    /// Internal knot upper faces are retained chart limits, not owning offset values.
    public let ownsUpperBoundary:[Bool]
    public let proofDepth:ExactScalarDepth
    public var positiveRootVariable:Int { 2 }
    /// Enclosing chart extent only; D!=0 and normalSquared>0 remain mandatory.
    public var enclosingSupport:[OriginalSourceParameterInterval<F.Value>] { child.support }
    public var denominator:ExactPolynomial<F> { homogeneous[3] }
    init(source:OriginalSourceBinding<S>,child:OriginalRationalChartReceipt<S.Child,C,F>,field:F,
        polynomials:ExactPolynomialDomain<F>,homogeneous:[ExactPolynomial<F>],normalSquared:ExactPolynomial<F>,
        positiveRootEquation:ExactPolynomial<F>,ownsUpperBoundary:[Bool],proofDepth:ExactScalarDepth) {
        self.source=source;self.child=child;self.field=field;self.polynomials=polynomials
        self.homogeneous=homogeneous;self.normalSquared=normalSquared
        self.positiveRootEquation=positiveRootEquation;self.ownsUpperBoundary=ownsUpperBoundary;self.proofDepth=proofDepth
    }
    public func admitProof<A:ExactScalarAdmission & ~Copyable>(limits:OriginalSourceIssuanceLimits,
        using a:inout A) throws(OriginalSourceIssuanceFailure) {
        do {
            try a.checkpoint();try source.require(limits)
            try a.admitDepth(value:proofDepth.value,coefficient:proofDepth.coefficient)
            try child.admitProof(using:&a)
            for law in homogeneous { _ = try polynomials.degree(of:law,in:2,using:&a) }
            _ = try polynomials.degree(of:positiveRootEquation,in:2,using:&a)
            try a.checkpoint()
        } catch { throw .init(preserving:error) }
    }
    /// The root sign and equation are source predicates, not a free extra parameter.
    public func admitsLiftedPosition<A:ExactScalarAdmission & ~Copyable>(at coordinates:[F.Value],
        limits:OriginalSourceIssuanceLimits,using a:inout A) throws(OriginalSourceIssuanceFailure) -> Bool {
        do {
            guard coordinates.count==3 else { throw OriginalSourceIssuanceFailure.invalidChart }
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:F.Value.self))
            guard try admitsPosition(at:[coordinates[0],coordinates[1]],limits:limits,using:&a),
                try field.sign(of:coordinates[2],using:&a) == .positive else { return false }
            let relation=try polynomials.evaluated(positiveRootEquation,at:coordinates,using:&a).value
            let valid=try field.sign(of:relation,using:&a) == .zero
            try a.checkpoint();return valid
        } catch { throw .init(preserving:error) }
    }
    /// Exact source-domain membership; no numerical query-tolerance claim.
    public func admitsPosition<A:ExactScalarAdmission & ~Copyable>(at parameters:[F.Value],
        limits:OriginalSourceIssuanceLimits,using a:inout A) throws(OriginalSourceIssuanceFailure) -> Bool {
        do {
            try admitProof(limits:limits,using:&a)
            guard parameters.count==2 else { throw OriginalSourceIssuanceFailure.invalidChart }
            for axis in 0..<2 {
                if try field.compare(parameters[axis],child.support[axis].lower,using:&a) == .less { return false }
                let upperOrder=try field.compare(parameters[axis],child.support[axis].upper,using:&a)
                if upperOrder == .greater || (upperOrder == .equal && !ownsUpperBoundary[axis]) { return false }
            }
            let d=try child.polynomials.evaluated(child.denominator,at:parameters,using:&a).value
            if try field.sign(of:d,using:&a) == .zero { return false }
            for guardLaw in child.parameterTransport.denominators {
                let guardValue=try child.polynomials.evaluated(guardLaw,at:parameters,using:&a).value
                if try field.sign(of:guardValue,using:&a) == .zero { return false }
            }
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:3,of:F.Value.self))
            let values=[parameters[0],parameters[1],try field.integer(0,using:&a)]
            let square=try polynomials.evaluated(normalSquared,at:values,using:&a).value
            let valid=try field.sign(of:square,using:&a) == .positive
            try a.checkpoint();return valid
        } catch { throw .init(preserving:error) }
    }
}

#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Exact original rational-child differential normal; no root approximation.
public struct DefaultOriginalOffsetLawIssuer<S:OriginalOffsetSourceReading,C:Sendable,
    F:ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>:OriginalOffsetLawIssuing where F.Source == F.Value,S.Child:OriginalBSplineSourceReading {
    public typealias Source=S
    public typealias ChildSelection=C
    public typealias Field=F
    public init() {}
    public func issue<A:ExactScalarAdmission & ~Copyable>(source:borrowing OriginalSourceBinding<S>,
        child:borrowing OriginalRationalChartReceipt<S.Child,C,F>,field:borrowing F,
        limits:OriginalSourceIssuanceLimits,using a:inout A) throws(OriginalSourceIssuanceFailure) -> OriginalOffsetLawReceipt<S,C,F> {
        let source=copy source,child=copy child,field=copy field
        do {
            return try OriginalSourceProofAdmission<A>.withBorrow(&a) { usage in
                try compose(source:source,child:child,field:field,limits:limits,using:&usage)
            }
        } catch { throw .init(preserving:error) }
    }
    private func compose<A:ExactScalarAdmission & ~Copyable>(source:OriginalSourceBinding<S>,
        child:OriginalRationalChartReceipt<S.Child,C,F>,field f:F,limits:OriginalSourceIssuanceLimits,
        using a:inout OriginalSourceProofAdmission<A>) throws -> OriginalOffsetLawReceipt<S,C,F> {
        try a.checkpoint();try source.require(limits)
        guard limits.remainingSourceDepth>0 else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
        try child.source.require(.init(remainingSourceDepth:limits.remainingSourceDepth-1))
        guard source.original.originalChild.owns(child.chart) else { throw OriginalSourceIssuanceFailure.foreignBinding }
        guard child.polynomials.variableCount==2,child.support.count==2,child.homogeneous.count==4,
            child.parameterTransport.numerators.count==2,child.parameterTransport.denominators.count==2 else { throw OriginalSourceIssuanceFailure.invalidChart }
        let original=child.source.original
        guard original.parameterCount==2 else { throw OriginalSourceIssuanceFailure.invalidChart }
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:Bool.self))
        var ownsUpper:[Bool]=[];ownsUpper.reserveCapacity(2)
        for axis in 0..<2 {
            try a.consumeWork(1)
            let end=try f.binary64(exactly:original.knot(at:original.controlCount(in:axis),in:axis),using:&a)
            // The original periodic evaluator wraps the upper endpoint to the lower side.
            let final = try f.compare(child.support[axis].upper,end,using:&a) == .equal
            ownsUpper.append(!original.isPeriodic(in:axis) && final)
        }
        try child.admitProof(using:&a)
        let r=try ExactPolynomialDomain(field:f,variableCount:2,using:&a)
        for axis in 0..<2 {
            let n=try r.importing(child.parameterTransport.numerators[axis],using:&a)
            let d=try r.importing(child.parameterTransport.denominators[axis],using:&a)
            guard try !r.isZero(d,using:&a),
                try r.isZero(r.subtracting(n,r.multiplying(r.variable(axis,using:&a),d,using:&a),using:&a),using:&a) else {
                throw OriginalSourceIssuanceFailure.unsupportedRepresentation
            }
        }
        let ring=try ExactPolynomialDomain(field:f,variableCount:3,using:&a)
        func embed(_ p:ExactPolynomial<F>,_ a:inout OriginalSourceProofAdmission<A>) throws -> ExactPolynomial<F> {
            try a.admitDepth(value:p.depth.value,coefficient:p.depth.coefficient)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:p.termCount,of:ExactPolynomialTerm<F.Value>.self))
            var terms:[ExactPolynomialTerm<F.Value>]=[];terms.reserveCapacity(p.termCount)
            for term in p.terms {
                try a.consumeWork(1);try a.retainStorage(bytes:exactScalarPayloadBytes(count:3,of:Int.self))
                terms.append(.init(powers:[term.powers[0],term.powers[1],0],coefficient:try f.importing(term.coefficient,using:&a)))
            }
            return try ring.polynomial(orderedTerms:terms,using:&a)
        }
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:20,of:ExactPolynomial<F>.self))
        let d=try embed(child.denominator,&a),du=try ring.differentiated(d,in:0,using:&a),dv=try ring.differentiated(d,in:1,using:&a)
        guard try !ring.isZero(d,using:&a) else { throw OriginalSourceIssuanceFailure.invalidChart }
        var n:[ExactPolynomial<F>]=[],tu:[ExactPolynomial<F>]=[],tv:[ExactPolynomial<F>]=[]
        for i in 0..<3 {
            let value=try embed(child.homogeneous[i],&a);n.append(value)
            tu.append(try ring.subtracting(ring.multiplying(ring.differentiated(value,in:0,using:&a),d,using:&a),ring.multiplying(value,du,using:&a),using:&a))
            tv.append(try ring.subtracting(ring.multiplying(ring.differentiated(value,in:1,using:&a),d,using:&a),ring.multiplying(value,dv,using:&a),using:&a))
        }
        var cross:[ExactPolynomial<F>]=[]
        var square=try ring.constant(f.integer(0,using:&a),using:&a)
        for i in 0..<3 {
            let j=(i+1)%3,k=(i+2)%3
            let value=try ring.subtracting(ring.multiplying(tu[j],tv[k],using:&a),ring.multiplying(tu[k],tv[j],using:&a),using:&a)
            cross.append(value);square=try ring.adding(square,ring.multiplying(value,value,using:&a),using:&a)
        }
        let q=try ring.variable(2,using:&a),distance=try f.binary64(exactly:source.original.originalDistance,using:&a)
        var position:[ExactPolynomial<F>]=[]
        for i in 0..<3 {
            position.append(try ring.adding(ring.multiplying(q,n[i],using:&a),ring.scaled(ring.multiplying(d,cross[i],using:&a),by:distance,using:&a),using:&a))
        }
        position.append(try ring.multiplying(q,d,using:&a))
        let equation=try ring.subtracting(ring.multiplying(q,q,using:&a),square,using:&a)
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalOffsetLawReceipt<S,C,F>.self))
        let result=OriginalOffsetLawReceipt(source:source,child:child,field:f,polynomials:ring,homogeneous:position,
            normalSquared:square,positiveRootEquation:equation,ownsUpperBoundary:ownsUpper,proofDepth:try a.depth)
        try a.checkpoint();return result
    }
}

#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Whole finite Native child coverage with mandatory per-chart offset guards.
public struct OriginalFiniteNativeOffsetLawFamily<S:OriginalOffsetSourceReading>:Sendable where S.Child:OriginalBSplineSourceReading {
    public let source:OriginalSourceBinding<S>
    public let child:OriginalFiniteBSplineCharts<S.Child>
    public let laws:[OriginalOffsetLawReceipt<S,OriginalBSplineChartSelection,OriginalExactScalarDomain>]
    public let proofDepth:ExactScalarDepth
    public var field:OriginalExactScalarDomain { child.field }
    /// Full child extent, not a Cartesian assertion about offset position support.
    public var enclosingSupport:[OriginalSourceParameterInterval<OriginalExactScalar>] { child.support }
    init(source:OriginalSourceBinding<S>,child:OriginalFiniteBSplineCharts<S.Child>,
        laws:[OriginalOffsetLawReceipt<S,OriginalBSplineChartSelection,OriginalExactScalarDomain>],proofDepth:ExactScalarDepth) {
        self.source=source;self.child=child;self.laws=laws;self.proofDepth=proofDepth
    }
    public func admitProof<A:ExactScalarAdmission & ~Copyable>(limits:OriginalSourceIssuanceLimits,
        using a:inout A) throws(OriginalSourceIssuanceFailure) {
        do {
            try a.checkpoint();try source.require(limits)
            try a.admitDepth(value:proofDepth.value,coefficient:proofDepth.coefficient)
            for law in laws { try a.consumeWork(1);try law.admitProof(limits:limits,using:&a) }
            try a.checkpoint()
        } catch { throw .init(preserving:error) }
    }
}

#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

public protocol OriginalFiniteNativeOffsetLawPreparing {
    associatedtype Source:OriginalOffsetSourceReading where Source.Child:OriginalBSplineSourceReading
    func prepare<A:ExactScalarAdmission & ~Copyable>(source:borrowing OriginalSourceBinding<Source>,
        child:borrowing OriginalFiniteBSplineCharts<Source.Child>,maximumCharts:Int,
        limits:OriginalSourceIssuanceLimits,using a:inout A) throws(OriginalSourceIssuanceFailure)
        -> OriginalFiniteNativeOffsetLawFamily<Source>
}

#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

public struct DefaultOriginalFiniteNativeOffsetLawPreparer<S:OriginalOffsetSourceReading>:OriginalFiniteNativeOffsetLawPreparing where S.Child:OriginalBSplineSourceReading {
    public typealias Source=S
    public init() {}
    public func prepare<A:ExactScalarAdmission & ~Copyable>(source:borrowing OriginalSourceBinding<S>,
        child:borrowing OriginalFiniteBSplineCharts<S.Child>,maximumCharts:Int,limits:OriginalSourceIssuanceLimits,
        using a:inout A) throws(OriginalSourceIssuanceFailure) -> OriginalFiniteNativeOffsetLawFamily<S> {
        let source=copy source,child=copy child
        do {
            return try OriginalSourceProofAdmission<A>.withBorrow(&a) { a in
                try a.checkpoint();try source.require(limits)
                guard source.original.originalChild.owner === child.source.owner else { throw OriginalSourceIssuanceFailure.foreignBinding }
                guard child.support.count==2,child.source.original.parameterCount==2,!child.laws.isEmpty else { throw OriginalSourceIssuanceFailure.invalidChart }
                guard maximumCharts>=0,child.laws.count<=maximumCharts else { throw OriginalSourceIssuanceFailure.chartLimit }
                typealias Law=OriginalOffsetLawReceipt<S,OriginalBSplineChartSelection,OriginalExactScalarDomain>
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:child.laws.count,of:Law.self))
                var laws:[Law]=[];laws.reserveCapacity(child.laws.count)
                let issuer=DefaultOriginalOffsetLawIssuer<S,OriginalBSplineChartSelection,OriginalExactScalarDomain>()
                for law in child.laws {
                    try a.consumeWork(1)
                    laws.append(try issuer.issue(source:source,child:law,field:child.field,limits:limits,using:&a))
                }
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalFiniteNativeOffsetLawFamily<S>.self))
                let result=OriginalFiniteNativeOffsetLawFamily(source:source,child:child,laws:laws,proofDepth:try a.depth)
                try a.checkpoint();return result
            }
        } catch { throw .init(preserving:error) }
    }
}

#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Transfers the existing original positive-normal-length relation without another producer.
public struct DefaultOriginalOffsetGraphIssuer<S:OriginalOffsetSourceReading,C:Sendable,F:ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>:OriginalParametricGraphIssuing where F.Source==F.Value {
    public typealias Source=S
    public typealias Field=F
    public typealias Evidence=OriginalOffsetLawReceipt<S,C,F>
    public init() {}
    public func issue<A: ExactScalarAdmission & ~Copyable>(_ evidence:borrowing Evidence,limits:OriginalSourceIssuanceLimits,
        using admission:inout A)
        throws(OriginalSourceIssuanceFailure)->OriginalParametricGraphReceipt<S,F,Evidence> {
        let law=copy evidence
        do {
            return try OriginalSourceProofAdmission<A>.withBorrow(&admission) { a in
                try law.admitProof(limits:limits,using:&a)
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:3,of:Int.self))
                let layout=try OriginalParametricVariableLayout.checked(variableCount:3,parameters:[0,1],auxiliaries:[2],using:&a)
                let ring=law.polynomials
                let size=law.child.parameterTransport.denominators.count.addingReportingOverflow(5)
                guard !size.overflow else { throw OriginalSourceIssuanceFailure.countOverflow };let count=size.partialValue
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:count,of:OriginalParametricGraphCondition<F>.self))
                var guards:[OriginalParametricGraphCondition<F>]=[];guards.reserveCapacity(count)
                guards.append(.init(law.positiveRootEquation,.equal))
                guards.append(.init(try ring.variable(2,using:&a),.positive))
                guards.append(.init(law.normalSquared,.positive))
                guards.append(.init(law.denominator,.notEqual))
                for ordinal in 0...law.child.parameterTransport.denominators.count {
                    let polynomial = ordinal == 0 ? law.child.denominator : law.child.parameterTransport.denominators[ordinal-1]
                    try a.retainStorage(bytes:exactScalarPayloadBytes(count:polynomial.termCount,of:ExactPolynomialTerm<F.Value>.self))
                    var terms:[ExactPolynomialTerm<F.Value>]=[];terms.reserveCapacity(polynomial.termCount)
                    for term in polynomial.terms {
                        try a.consumeWork(1);try a.retainStorage(bytes:exactScalarPayloadBytes(count:3,of:Int.self))
                        terms.append(.init(powers:[term.powers[0],term.powers[1],0],coefficient:try law.field.importing(term.coefficient,using:&a)))
                    }
                    guards.append(.init(try ring.polynomial(terms:terms,using:&a),.notEqual))
                }
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalParametricGraphReceipt<S,F,Evidence>.self))
                let result=OriginalParametricGraphReceipt(source:law.source,evidence:law,field:law.field,polynomials:ring,
                    homogeneous:law.homogeneous,support:law.enclosingSupport,includesUpperBoundary:law.ownsUpperBoundary,
                    layout:layout,conditions:guards,parameterTransport:law.child.parameterTransport,proofDepth:try a.depth)
                try a.checkpoint();return result
            }
        } catch { throw .init(preserving:error) }
    }
}

#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

/// Enclosing chart selection plus the retained mandatory original source guard.
public struct OriginalNativeOffsetChartOccurrence<S: OriginalOffsetSourceReading>: Sendable where S.Child: OriginalBSplineSourceReading {
    public let family: OriginalFiniteNativeOffsetLawFamily<S>
    public let template: Int
    public let enclosingSelection: OriginalParameterSelection<S,OriginalExactScalarDomain>
    public var law: OriginalOffsetLawReceipt<S,OriginalBSplineChartSelection,OriginalExactScalarDomain> { family.laws[template] }
    init(family: OriginalFiniteNativeOffsetLawFamily<S>,template: Int,
        enclosingSelection: OriginalParameterSelection<S,OriginalExactScalarDomain>) {
        self.family = family;self.template = template;self.enclosingSelection = enclosingSelection
    }
}

#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

/// Complete requested guarded domain retaining every original child chart.
public struct OriginalNativeOffsetDomainCover<S: OriginalOffsetSourceReading>: OriginalGuardedChartFamilyQuerying where S.Child: OriginalBSplineSourceReading {
    public typealias Source = S
    public typealias Field = OriginalExactScalarDomain
    public typealias Occurrence = OriginalNativeOffsetChartOccurrence<S>
    public let family: OriginalFiniteNativeOffsetLawFamily<S>
    public let enclosingSupport: OriginalParameterSelection<S,Field>
    public let request: OriginalParameterSelection<S,Field>
    public let effectiveEnclosure: OriginalParameterSelection<S,Field>
    public var source: OriginalSourceBinding<S> { family.source }
    public var templateCount: Int { family.laws.count }
    init(family: OriginalFiniteNativeOffsetLawFamily<S>,enclosingSupport: OriginalParameterSelection<S,Field>,
        request: OriginalParameterSelection<S,Field>,effectiveEnclosure: OriginalParameterSelection<S,Field>) {
        self.family = family;self.enclosingSupport = enclosingSupport;self.request = request;self.effectiveEnclosure = effectiveEnclosure
    }
    func occurrence<A: ExactScalarAdmission & ~Copyable>(template: Int,limits: OriginalDomainIdentityLimits,
        _ a: inout A) throws -> Occurrence {
        guard family.laws.indices.contains(template) else { throw OriginalDomainIdentityFailure.invalidDomain }
        let law = family.laws[template],issuer = DefaultOriginalNativeOffsetDomainIssuer<S>()
        let enclosure = try enclosingSupport.frame.selection(intervals:issuer.intervals(law.enclosingSupport,
            field:family.field,depth:law.proofDepth,&a),limits:limits,using:&a)
        return .init(family:family,template:template,
            enclosingSelection:try enclosure.intersection(effectiveEnclosure,limits:limits,using:&a))
    }
    public func member<A: ExactScalarAdmission & ~Copyable>(template: Int,limits: OriginalDomainIdentityLimits,
        using admission: inout A) throws(OriginalDomainIdentityFailure) -> Occurrence {
        return try OriginalDomainAccess.run(&admission) { a in
            try DefaultOriginalNativeOffsetDomainIssuer<S>().admitted(family,limits:limits,&a)
            return try occurrence(template:template,limits:limits,&a)
        }
    }
    func incidents<A: ExactScalarAdmission & ~Copyable>(tuple: [OriginalExactScalar],lifted: Bool,
        limits: OriginalDomainIdentityLimits,_ a: inout A) throws -> [Occurrence] {
        try DefaultOriginalNativeOffsetDomainIssuer<S>().admitted(family,limits:limits,&a)
        guard tuple.count == (lifted ? 3 : 2) else { throw OriginalDomainIdentityFailure.invalidDomain }
        try OriginalDomainAccess.storage(2,OriginalExactScalar.self,&a)
        let parameters = [tuple[0],tuple[1]]
        guard try effectiveEnclosure.contains(parameters,limits:limits,using:&a) else { return [] }
        var result: [Occurrence] = []
        for template in family.laws.indices {
            try a.consumeWork(1)
            let law = family.laws[template]
            let included = try lifted ? law.admitsLiftedPosition(at:tuple,limits:limits.source,using:&a)
                : law.admitsPosition(at:parameters,limits:limits.source,using:&a)
            if included {
                guard result.count < limits.maximumCharts else { throw OriginalDomainIdentityFailure.chartLimit }
                try OriginalDomainAccess.storage(1,Occurrence.self,&a)
                result.append(try occurrence(template:template,limits:limits,&a))
            }
        }
        return result
    }
    public func positionIncidents<A: ExactScalarAdmission & ~Copyable>(at tuple: borrowing [OriginalExactScalar],
        limits: OriginalDomainIdentityLimits,using admission: inout A)
        throws(OriginalDomainIdentityFailure) -> [Occurrence] {
        let tuple = copy tuple
        return try OriginalDomainAccess.run(&admission) { a in try incidents(tuple:tuple,lifted:false,limits:limits,&a) }
    }
    public func liftedPositionIncidents<A: ExactScalarAdmission & ~Copyable>(at tuple: borrowing [OriginalExactScalar],
        limits: OriginalDomainIdentityLimits,using admission: inout A)
        throws(OriginalDomainIdentityFailure) -> [Occurrence] {
        let tuple = copy tuple
        return try OriginalDomainAccess.run(&admission) { a in try incidents(tuple:tuple,lifted:true,limits:limits,&a) }
    }
}

#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

public protocol OriginalNativeOffsetDomainIssuing: Sendable {
    associatedtype Source: OriginalOffsetSourceReading where Source.Child: OriginalBSplineSourceReading
    func frame<A: ExactScalarAdmission & ~Copyable>(family: borrowing OriginalFiniteNativeOffsetLawFamily<Source>,
        limits: OriginalDomainIdentityLimits,using admission: inout A)
        throws(OriginalDomainIdentityFailure) -> OriginalParameterFrame<Source,OriginalExactScalarDomain>
    func issue<A: ExactScalarAdmission & ~Copyable>(request: borrowing OriginalParameterSelection<Source,OriginalExactScalarDomain>,
        family: borrowing OriginalFiniteNativeOffsetLawFamily<Source>,limits: OriginalDomainIdentityLimits,using admission: inout A)
        throws(OriginalDomainIdentityFailure) -> OriginalNativeOffsetDomainCover<Source>
}

#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

public struct DefaultOriginalNativeOffsetDomainIssuer<S: OriginalOffsetSourceReading>: OriginalNativeOffsetDomainIssuing where S.Child: OriginalBSplineSourceReading {
    public typealias Source = S
    public init() {}
    func admitted<A: ExactScalarAdmission & ~Copyable>(_ family: OriginalFiniteNativeOffsetLawFamily<S>,
        limits: OriginalDomainIdentityLimits,_ a: inout A) throws {
        guard family.laws.count <= limits.maximumCharts else { throw OriginalDomainIdentityFailure.chartLimit }
        try family.admitProof(limits:limits.source,using:&a)
    }
    func intervals<A: ExactScalarAdmission & ~Copyable>(_ bounds: [OriginalSourceParameterInterval<OriginalExactScalar>],
        field: OriginalExactScalarDomain,depth: ExactScalarDepth,_ a: inout A)
        throws -> [[ExactParameterInterval<OriginalExactScalar>]] {
        guard bounds.count == 2 else { throw OriginalDomainIdentityFailure.invalidDomain }
        try OriginalDomainAccess.storage(2,[ExactParameterInterval<OriginalExactScalar>].self,&a)
        try OriginalDomainAccess.storage(2,ExactParameterInterval<OriginalExactScalar>.self,&a)
        var result: [[ExactParameterInterval<OriginalExactScalar>]] = [];result.reserveCapacity(2)
        for bound in bounds {
            try a.consumeWork(1)
            result.append([try .checked(field:field,lower:.finite(bound.lower),upper:.finite(bound.upper),depth:depth,using:&a)])
        }
        return result
    }
    public func frame<A: ExactScalarAdmission & ~Copyable>(family: borrowing OriginalFiniteNativeOffsetLawFamily<S>,
        limits: OriginalDomainIdentityLimits,using admission: inout A)
        throws(OriginalDomainIdentityFailure) -> OriginalParameterFrame<S,OriginalExactScalarDomain> {
        let family = copy family
        return try OriginalDomainAccess.run(&admission) { a in
            try admitted(family,limits:limits,&a)
            try OriginalDomainAccess.storage(2,OriginalCoordinateSemantics.self,&a)
            return try DefaultOriginalParameterTransporter<S,OriginalExactScalarDomain>().frame(source:family.source,
                field:family.field,support:intervals(family.enclosingSupport,field:family.field,depth:family.proofDepth,&a),
                semantics:[.authoredScalar,.authoredScalar],limits:limits,using:&a)
        }
    }
    public func issue<A: ExactScalarAdmission & ~Copyable>(request: borrowing OriginalParameterSelection<S,OriginalExactScalarDomain>,
        family: borrowing OriginalFiniteNativeOffsetLawFamily<S>,limits: OriginalDomainIdentityLimits,using admission: inout A)
        throws(OriginalDomainIdentityFailure) -> OriginalNativeOffsetDomainCover<S> {
        let request = copy request,family = copy family
        return try OriginalDomainAccess.run(&admission) { a in
            try admitted(family,limits:limits,&a)
            let anchor = try family.source.chart(0,limits:limits.source,using:&a)
            guard request.frame.source.owns(anchor) else { throw OriginalDomainIdentityFailure.foreignOwner }
            guard request.arity == 2 else { throw OriginalDomainIdentityFailure.invalidDomain }
            guard request.frame.coordinateSemantics[0] == .authoredScalar,
                request.frame.coordinateSemantics[1] == .authoredScalar else { throw OriginalDomainIdentityFailure.incompatibleCoordinateSemantics }
            let enclosure = try request.frame.selection(intervals:intervals(family.enclosingSupport,
                field:family.field,depth:family.proofDepth,&a),limits:limits,using:&a)
            guard try enclosure.equals(request.frame.fullSelection(limits:limits,using:&a),limits:limits,using:&a) else { throw OriginalDomainIdentityFailure.invalidDomain }
            return .init(family:family,enclosingSupport:enclosure,request:request,
                effectiveEnclosure:try enclosure.intersection(request,limits:limits,using:&a))
        }
    }
}

#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

/// Complete guarded source family; Cartesian enclosures never imply position membership.
public protocol OriginalGuardedChartFamilyQuerying: Sendable {
    associatedtype Source: Sendable
    associatedtype Field: ExactScalarArithmetic & ExactScalarOrdering
    associatedtype Occurrence: Sendable
    var source: OriginalSourceBinding<Source> { get }
    var enclosingSupport: OriginalParameterSelection<Source,Field> { get }
    var request: OriginalParameterSelection<Source,Field> { get }
    var effectiveEnclosure: OriginalParameterSelection<Source,Field> { get }
    var templateCount: Int { get }
    func member<A: ExactScalarAdmission & ~Copyable>(template: Int,limits: OriginalDomainIdentityLimits,
        using admission: inout A) throws(OriginalDomainIdentityFailure) -> Occurrence
    func positionIncidents<A: ExactScalarAdmission & ~Copyable>(at tuple: borrowing [Field.Value],
        limits: OriginalDomainIdentityLimits,using admission: inout A)
        throws(OriginalDomainIdentityFailure) -> [Occurrence]
    func liftedPositionIncidents<A: ExactScalarAdmission & ~Copyable>(at tuple: borrowing [Field.Value],
        limits: OriginalDomainIdentityLimits,using admission: inout A)
        throws(OriginalDomainIdentityFailure) -> [Occurrence]
}

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

public struct DefaultOriginalOffsetGraphFamilyPreparer<S:OriginalOffsetSourceReading>:OriginalIssuedGraphFamilyPreparing where S.Child:OriginalBSplineSourceReading {
    public typealias Source=S
    public typealias Evidence=OriginalOffsetLawReceipt<S,OriginalBSplineChartSelection,OriginalExactScalarDomain>
    public typealias Cover=OriginalNativeOffsetDomainCover<S>
    public init() {}
    public func prepare<A:ExactScalarAdmission & ~Copyable>(cover:borrowing Cover,field:borrowing ExactAlgebraicScalarDomain<OriginalExactScalarDomain>,
        maximumGraphs:Int,limits:OriginalDomainIdentityLimits,using admission:inout A)
        throws(NativeExactRelationFailure) -> OriginalIssuedGraphFamily<S,Evidence,Cover> {
        do {
            try admission.checkpoint();try cover.family.admitProof(limits:limits.source,using:&admission)
            guard maximumGraphs >= 0 else { throw NativeExactRelationFailure.invalidDomain }
            guard cover.templateCount <= limits.maximumCharts else { throw OriginalDomainIdentityFailure.chartLimit }
            _=try field.importingBase(cover.request.frame.scalarField.integer(0,using:&admission),using:&admission)
            let count=cover.effectiveEnclosure.isEmpty ? 0:cover.templateCount
            guard count <= maximumGraphs else { throw OriginalDomainIdentityFailure.chartLimit }
            try admission.retainStorage(bytes:exactScalarPayloadBytes(count:count,of:OriginalIssuedGraphPreparation<S,Evidence>.self))
            var graphs:[OriginalIssuedGraphPreparation<S,Evidence>]=[];graphs.reserveCapacity(count)
            var v=cover.family.proofDepth.value,c=cover.family.proofDepth.coefficient
            for axis in cover.request.frame.axes { try admission.consumeWork(1);v=max(v,axis.depth.value);c=max(c,axis.depth.coefficient) }
            for axis in cover.request.axes { try admission.consumeWork(1);v=max(v,axis.depth.value);c=max(c,axis.depth.coefficient) }
            for template in 0..<count {
                try admission.consumeWork(1)
                let occurrence=try cover.member(template:template,limits:limits,using:&admission)
                let graph=try DefaultOriginalOffsetGraphIssuer().issue(occurrence.law,limits:limits.source,using:&admission)
                let binding=try DefaultOriginalParametricGraphDomainBinder().bind(graph:graph,request:cover.request,limits:limits,using:&admission)
                let prepared=try DefaultOriginalIssuedGraphCompiler().compile(binding:binding,field:copy field,limits:limits,using:&admission)
                v=max(v,prepared.depth.value);c=max(c,prepared.depth.coefficient);graphs.append(prepared)
            }
            let depth=try ExactScalarDepth(value:v,coefficient:c);try admission.admitDepth(value:v,coefficient:c)
            try admission.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalIssuedGraphFamily<S,Evidence,Cover>.self))
            let result=OriginalIssuedGraphFamily(coverage:copy cover,source:cover.source,field:copy field,graphs:graphs,parameterCount:2,templateCount:cover.templateCount,depth:depth)
            try admission.checkpoint();return result
        } catch { throw .preserving(error) }
    }
}

extension OriginalNativeOffsetDomainCover: OriginalIssuedGraphSelfContactRequestReading {
    public var selfContactRequest: OriginalParameterSelection<S,OriginalExactScalarDomain> { request }
}
