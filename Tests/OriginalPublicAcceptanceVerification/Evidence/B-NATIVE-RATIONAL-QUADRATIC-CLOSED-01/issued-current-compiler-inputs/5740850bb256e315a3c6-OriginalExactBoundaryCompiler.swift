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


@testable import CADKernel
import HashTreeCollections
#if NATIVE_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
import DI0
import DI
import SourceIssuer
import SourceGeometryAdapters
import QuadraticBoundarySources
import struct CADGeometry.BSplineCurve2D
import struct CADGeometry.BSplineCurve3D
import struct CADGeometry.BSplineSurface3D
import enum CADGeometry.SurfaceParameterCurve
@testable import class CADGeometry.OriginalNativeBoundaryDomain
#endif

import CADCore

/// Query-local exact winding compilation in the retained L5 parameter ring.
struct OriginalExactBoundaryCompiler<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>
    where Base.Source == Base.Value {
    typealias Field = ExactAlgebraicScalarDomain<Base>
    typealias Polynomial = ExactPolynomial<Field>
    enum Node { case literal(Bool),sign(Int,ExactRealCellSignRelation),not(Int),and(Int,Int),or(Int,Int) }
    struct Segment: Sendable {
        let first: [Field.Value],last: [Field.Value]
        let reference: OriginalNativeBoundaryDomain.SpanReference
        let quadratic: OriginalRationalQuadraticBoundaryReceipt<BSplineCurve2D,Field>?
    }
    struct Loop: Sendable {
        let isInner: Bool
        let segments: [Segment]
    }
    struct Factorization: Sendable {
        let original: Polynomial
        let factor: Polynomial
        let quotient: Polynomial
        let remainder: Polynomial
    }
    let cells: ExactRealCellDomain<Base>
    let field: Field
    var laws: [Polynomial] = []
    private(set) var factorizations: [Factorization] = []
    private var nodes: [Node] = []
    private var boundaryNodes: [Int] = []
    private var references: [OriginalNativeBoundaryDomain.SpanReference] = []

    init<A: ExactScalarAdmission & ~Copyable>(_ raw: ExactParametricRelation<Base>,using a: inout A) throws {
        cells = try .init(retaining:raw.original.predicate.source,using:&a)
        field = try cells.coefficientField(of:raw.original.predicate.source,using:&a)
    }
    init<A: ExactScalarAdmission & ~Copyable>(selection: ExactRealCellSelection<Base>,using a: inout A) throws {
        cells = try .init(retaining:selection.predicate.source,using:&a)
        field = try cells.coefficientField(of:selection.predicate.source,using:&a)
    }
    init<A: ExactScalarAdmission & ~Copyable>(field: Field,using a: inout A) throws {
        self.field = field;cells = try .init(field:field,variableCount:2,using:&a)
    }
    func prepare<A: ExactScalarAdmission & ~Copyable>(_ loops: [OriginalNativeBoundaryDomain.Loop],using a: inout A) throws -> [Loop] {
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:loops.count,of:Loop.self))
        var prepared: [Loop] = [];prepared.reserveCapacity(loops.count)
        for (index,loop) in loops.enumerated() {
            try a.consumeWork(1)
            prepared.append(.init(isInner:loop.isInner,segments:try segments(loop,ordinal:index,&a)))
        }
        try a.checkpoint();return prepared
    }
    mutating func node<A: ExactScalarAdmission & ~Copyable>(_ value: Node,_ a: inout A) throws -> Int {
        try a.consumeWork(1)
        guard !nodes.count.addingReportingOverflow(1).overflow else { throw ExactScalarFailure.countOverflow }
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Node.self))
        nodes.append(value);return nodes.count-1
    }
    mutating func and<A: ExactScalarAdmission & ~Copyable>(_ left: Int,_ right: Int,_ a: inout A) throws -> Int {
        if left == right { return left }
        if case .literal(let value) = nodes[left] { return value ? right:left }
        if case .literal(let value) = nodes[right] { return value ? left:right }
        return try node(.and(left,right),&a)
    }
    mutating func or<A: ExactScalarAdmission & ~Copyable>(_ left: Int,_ right: Int,_ a: inout A) throws -> Int {
        if left == right { return left }
        if case .literal(let value) = nodes[left] { return value ? left:right }
        if case .literal(let value) = nodes[right] { return value ? right:left }
        return try node(.or(left,right),&a)
    }
    mutating func not<A: ExactScalarAdmission & ~Copyable>(_ index: Int,_ a: inout A) throws -> Int {
        if case .literal(let value) = nodes[index] { return try node(.literal(!value),&a) }
        return try node(.not(index),&a)
    }
    mutating func atom<A: ExactScalarAdmission & ~Copyable>(_ law: Polynomial,_ sign: ExactRealCellSignRelation,_ a: inout A) throws -> Int {
        for index in laws.indices {
            try a.consumeWork(1)
            if try cells.polynomials.equals(law,laws[index],using:&a) { return try node(.sign(index,sign),&a) }
        }
        guard !laws.count.addingReportingOverflow(1).overflow else { throw ExactScalarFailure.countOverflow }
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Polynomial.self))
        laws.append(law);return try node(.sign(laws.count-1,sign),&a)
    }
    private func scalar<A: ExactScalarAdmission & ~Copyable>(_ value: Double,_ a: inout A) throws -> Field.Value {
        try field.binary64(exactly:value,using:&a)
    }
    private func point<A: ExactScalarAdmission & ~Copyable>(_ u: Double,_ v: Double,_ a: inout A) throws -> [Field.Value] {
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:Field.Value.self))
        return [try scalar(u,&a),try scalar(v,&a)]
    }
    private func totalDegree<A: ExactScalarAdmission & ~Copyable>(_ polynomial: Polynomial,_ a: inout A) throws -> Int? {
        try a.admitDepth(value:polynomial.depth.value,coefficient:polynomial.depth.coefficient)
        var result: Int? = nil
        for term in polynomial.terms {
            var degree = 0
            for power in term.powers {
                try a.consumeWork(1)
                let sum = degree.addingReportingOverflow(power)
                guard !sum.overflow else { throw ExactScalarFailure.countOverflow }
                degree = sum.partialValue
            }
            result = max(result ?? 0,degree)
        }
        return result
    }
    private func factorization<A: ExactScalarAdmission & ~Copyable>(of conic: Polynomial,
        quadratic: OriginalRationalQuadraticBoundaryReceipt<BSplineCurve2D,Field>,
        numerators uv: [Polynomial],denominator: Polynomial?,_ a: inout A) throws -> Factorization? {
        guard try totalDegree(conic,&a) == 2 else { return nil }
        let law = quadratic.law,ring = cells.polynomials
        let support = law.support[0]
        let midpoint = try field.dividing(field.adding(support.lower,support.upper,using:&a),field.integer(2,using:&a),using:&a)
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Field.Value.self))
        let coordinates = [midpoint]
        let u = try law.polynomials.evaluated(law.homogeneous[0],at:coordinates,using:&a)
        let v = try law.polynomials.evaluated(law.homogeneous[1],at:coordinates,using:&a)
        let w = try law.polynomials.evaluated(law.denominator,at:coordinates,using:&a)
        for axis in 0..<2 {
            try a.consumeWork(1)
            let coordinate = try field.dividing(axis == 0 ? u.value:v.value,w.value,using:&a)
            let constant = try ring.constant(coordinate,using:&a)
            let scaled = try denominator.map { try ring.multiplying(constant,$0,using:&a) } ?? constant
            let factor = try ring.subtracting(uv[axis],scaled,using:&a)
            guard try totalDegree(factor,&a) == 1 else { continue }
            let division = try ring.divided(conic,by:factor,using:&a)
            // The midpoint supplies a candidate; the whole polynomial identity supplies authority.
            guard try ring.isZero(division.remainder,using:&a),
                (try totalDegree(division.quotient,&a) ?? -1) <= 1,
                try ring.equals(conic,ring.multiplying(factor,division.quotient,using:&a),using:&a) else { continue }
            try a.checkpoint()
            return .init(original:conic,factor:factor,quotient:division.quotient,remainder:division.remainder)
        }
        try a.checkpoint();return nil
    }
    private func segments<A: ExactScalarAdmission & ~Copyable>(_ loop: OriginalNativeBoundaryDomain.Loop,
        ordinal: Int,_ a: inout A) throws -> [Segment] {
        var result: [Segment] = []
        func append(_ first: [Field.Value],_ last: [Field.Value],curve: Int,segment: Int,
            quadratic: OriginalRationalQuadraticBoundaryReceipt<BSplineCurve2D,Field>? = nil) throws {
            try a.consumeWork(1)
            guard try field.compare(first[0],last[0],using:&a) != .equal || field.compare(first[1],last[1],using:&a) != .equal else {
                throw NativeExactRelationFailure.invalidDomain
            }
            if let previous = result.last {
                guard try field.compare(previous.last[0],first[0],using:&a) == .equal,
                    try field.compare(previous.last[1],first[1],using:&a) == .equal else { throw NativeExactRelationFailure.invalidDomain }
            }
            guard !result.count.addingReportingOverflow(1).overflow else { throw ExactScalarFailure.countOverflow }
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Segment.self))
            result.append(.init(first:first,last:last,reference:.init(loopOrdinal:ordinal,curveOrdinal:curve,segmentOrdinal:segment),quadratic:quadratic))
        }
        for (index,curve) in loop.curves.enumerated() {
            try a.consumeWork(1)
            switch curve {
            case .constantU(let u,let start,let end): try append(point(u,start,&a),point(u,end,&a),curve:index,segment:0)
            case .constantV(let v,let start,let end): try append(point(start,v,&a),point(end,v,&a),curve:index,segment:0)
            case .affine(let origin,let direction,let start,let end):
                let o = try point(origin.x,origin.y,&a),d = try point(direction.x,direction.y,&a)
                let low = try scalar(start,&a),high = try scalar(end,&a)
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:4,of:Field.Value.self))
                let first = [try field.adding(o[0],field.multiplying(d[0],low,using:&a),using:&a),
                    try field.adding(o[1],field.multiplying(d[1],low,using:&a),using:&a)]
                let last = [try field.adding(o[0],field.multiplying(d[0],high,using:&a),using:&a),
                    try field.adding(o[1],field.multiplying(d[1],high,using:&a),using:&a)]
                try append(first,last,curve:index,segment:0)
            case .polyline(let values):
                guard values.count >= 2 else { throw NativeExactRelationFailure.invalidDomain }
                for segment in 0..<(values.count-1) {
                    try append(point(values[segment].u,values[segment].v,&a),point(values[segment+1].u,values[segment+1].v,&a),curve:index,segment:segment)
                }
            case .bSpline(let original):
                // FIXME(INCOMPLETE_IMPLEMENTATION): Exact Native and issued-face clipping
                // only consumes the complete positive single-span quadratic authority here.
                // General spline spans/degenerate arcs require their own complete winding
                // authority before these public routes may report successful clipping.
                let limits = try OriginalSourceIssuanceLimits(remainingSourceDepth:0)
                let source = try DefaultOriginalSourceBindingIssuer(provider:
                    OriginalBSplinePcurveSnapshotProvider(tolerance:.standard)).bind(original,limits:limits,using:&a)
                let quadratic = try DefaultOriginalRationalQuadraticBoundaryIssuer<BSplineCurve2D,Field>()
                    .issue(source:source,field:field,limits:limits,using:&a)
                try append(quadratic.first,quadratic.last,curve:index,segment:0,quadratic:quadratic)
            default:
                // FIXME(INCOMPLETE_IMPLEMENTATION): This additive Native L5 face consumer
                // requires an original winding law for the remaining implicit/nonrational pcurves.
                // It cannot report successful clipping until their whole directed cover is issued.
                throw NativeExactRelationFailure.unsupportedCoverage
            }
        }
        guard let first = result.first,let last = result.last,
            try field.compare(first.first[0],last.last[0],using:&a) == .equal,
            try field.compare(first.first[1],last.last[1],using:&a) == .equal else { throw NativeExactRelationFailure.invalidDomain }
        return result
    }
    mutating func boundary<A: ExactScalarAdmission & ~Copyable>(loops: [OriginalNativeBoundaryDomain.Loop],
        numerators uv: [Polynomial],denominator: Polynomial?,selection: OriginalNativeBoundaryDomain.Selection,
        _ a: inout A) throws -> Int {
        let prepared = try prepare(loops,using:&a)
        return try boundary(preparedLoops:prepared,numerators:uv,denominator:denominator,selection:selection,&a)
    }
    mutating func boundary<A: ExactScalarAdmission & ~Copyable>(preparedLoops loops: [Loop],
        numerators uv: [Polynomial],denominator: Polynomial?,selection: OriginalNativeBoundaryDomain.Selection,
        _ a: inout A) throws -> Int {
        guard uv.count == 2 else { throw NativeExactRelationFailure.invalidDomain }
        let ring = cells.polynomials
        func difference(_ coordinate: Polynomial,_ bound: Field.Value) throws -> Polynomial {
            let constant = try ring.constant(bound,using:&a)
            let scaled = try denominator.map { try ring.multiplying(constant,$0,using:&a) } ?? constant
            return try ring.subtracting(coordinate,scaled,using:&a)
        }
        func signed(_ numerator: Polynomial) throws -> Polynomial {
            if let denominator { return try ring.multiplying(numerator,denominator,using:&a) }
            return numerator
        }
        var outer = try node(.literal(false),&a),inner = try node(.literal(false),&a),anyBoundary = try node(.literal(false),&a)
        for loop in loops {
            let spans = loop.segments
            var capacity = spans.count
            for span in spans {
                try a.consumeWork(1)
                if span.quadratic != nil {
                    let next = capacity.addingReportingOverflow(1)
                    guard !next.overflow else { throw ExactScalarFailure.countOverflow }
                    capacity = next.partialValue
                }
            }
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:capacity,of:(Int,Int).self))
            var crossings: [(node:Int,delta:Int)] = []
            crossings.reserveCapacity(capacity)
            var loopBoundary = try node(.literal(false),&a)
            for span in spans {
                try a.consumeWork(1)
                let du = try field.subtracting(span.last[0],span.first[0],using:&a),dv = try field.subtracting(span.last[1],span.first[1],using:&a)
                let x = try difference(uv[0],span.first[0])
                let y = try difference(uv[1],span.first[1])
                let cross = try ring.subtracting(ring.scaled(y,by:du,using:&a),ring.scaled(x,by:dv,using:&a),using:&a)
                let on: Int
                if let quadratic = span.quadratic {
                    try quadratic.admitProof(limits:OriginalSourceIssuanceLimits(remainingSourceDepth:0),using:&a)
                    // Barycentric coefficients come from the retained original law proof.
                    // With UV=H/W, lambda numerators use W and conic signs use W squared.
                    try a.retainStorage(bytes:exactScalarPayloadBytes(count:3,of:Polynomial.self))
                    var lambda: [Polynomial] = [];lambda.reserveCapacity(3)
                    for row in quadratic.barycentricRows {
                        try a.consumeWork(1)
                        let constant = try ring.constant(row[2],using:&a)
                        let c = try denominator.map { try ring.multiplying(constant,$0,using:&a) } ?? constant
                        lambda.append(try ring.adding(ring.adding(ring.scaled(uv[0],by:row[0],using:&a),
                            ring.scaled(uv[1],by:row[1],using:&a),using:&a),c,using:&a))
                    }
                    let four = try field.integer(4,using:&a)
                    let firstWeight = try field.multiplying(four,field.multiplying(quadratic.weights[1],quadratic.weights[1],using:&a),using:&a)
                    let secondWeight = try field.multiplying(quadratic.weights[0],quadratic.weights[2],using:&a)
                    let conic = try ring.subtracting(ring.scaled(ring.multiplying(lambda[0],lambda[2],using:&a),by:firstWeight,using:&a),
                        ring.scaled(ring.multiplying(lambda[1],lambda[1],using:&a),by:secondWeight,using:&a),using:&a)
                    let conicEqual: Int,conicPositive: Int
                    if let proof = try factorization(of:conic,quadratic:quadratic,numerators:uv,denominator:denominator,&a) {
                        guard !factorizations.count.addingReportingOverflow(1).overflow else { throw ExactScalarFailure.countOverflow }
                        try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Factorization.self))
                        factorizations.append(proof)
                        conicEqual = try or(atom(proof.factor,.equal,&a),atom(proof.quotient,.equal,&a),&a)
                        let positive = try and(atom(proof.factor,.greater,&a),atom(proof.quotient,.greater,&a),&a)
                        let negative = try and(atom(proof.factor,.less,&a),atom(proof.quotient,.less,&a),&a)
                        conicPositive = try or(positive,negative,&a)
                    } else {
                        conicEqual = try atom(conic,.equal,&a)
                        conicPositive = try atom(conic,.greater,&a)
                    }
                    let ends = try and(atom(signed(lambda[0]),.greaterOrEqual,&a),atom(signed(lambda[2]),.greaterOrEqual,&a),&a)
                    let middle = try atom(signed(lambda[1]),.greaterOrEqual,&a)
                    let triangle = try and(ends,middle,&a)
                    on = try and(triangle,conicEqual,&a)
                    // The chord contributes crossings only; the actual arc owns boundary
                    // incidents. Its cap correction follows the existing half-open ray rule.
                    let verticalDirection = try field.sign(of:dv,using:&a)
                    let tie: Bool
                    if verticalDirection == .zero {
                        tie = try field.sign(of:field.multiplying(quadratic.determinant,du,using:&a),using:&a) == .negative
                    } else {
                        tie = try field.sign(of:field.multiplying(quadratic.determinant,dv,using:&a),using:&a) == .positive
                    }
                    let chordSide = tie ? middle : try atom(signed(lambda[1]),.greater,&a)
                    let cap = try and(and(ends,chordSide,&a),conicPositive,&a)
                    let orientation = try field.sign(of:quadratic.determinant,using:&a)
                    crossings.append((cap,orientation == .positive ? 1:-1))
                } else {
                    let vertical = try field.sign(of:du,using:&a) == .zero
                    let coordinate = vertical ? uv[1]:uv[0],start = span.first[vertical ? 1:0],end = span.last[vertical ? 1:0]
                    let ascending = try field.compare(start,end,using:&a) != .greater
                    let lower = try signed(difference(coordinate,ascending ? start:end))
                    let upper = try signed(difference(coordinate,ascending ? end:start))
                    on = try and(and(atom(cross,.equal,&a),atom(lower,.greaterOrEqual,&a),&a),atom(upper,.lessOrEqual,&a),&a)
                }
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Int.self))
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalNativeBoundaryDomain.SpanReference.self))
                boundaryNodes.append(on);references.append(span.reference)
                loopBoundary = try or(loopBoundary,on,&a)
                let direction = try field.sign(of:dv,using:&a)
                if direction != .zero {
                    let first = try signed(difference(uv[1],direction == .positive ? span.first[1]:span.last[1]))
                    let last = try signed(difference(uv[1],direction == .positive ? span.last[1]:span.first[1]))
                    let crossing = try and(and(atom(first,.greaterOrEqual,&a),atom(last,.less,&a),&a),
                        atom(signed(cross),direction == .positive ? .greater:.less,&a),&a)
                    crossings.append((crossing,direction == .positive ? 1:-1))
                }
            }
            let winding = try nonzeroWinding(crossings,&a)
            anyBoundary = try or(anyBoundary,loopBoundary,&a)
            if loop.isInner { inner = try or(inner,and(winding,not(loopBoundary,&a),&a),&a) }
            else { outer = try or(outer,or(winding,loopBoundary,&a),&a) }
        }
        var closed = try and(outer,not(inner,&a),&a)
        if let denominator { closed = try and(closed,atom(denominator,.notEqual,&a),&a) }
        switch selection {
        case .closed:return closed
        case .strictInterior:return try and(closed,not(anyBoundary,&a),&a)
        case .boundary:return try and(closed,anyBoundary,&a)
        }
    }
    private mutating func nonzeroWinding<A: ExactScalarAdmission & ~Copyable>(_ crossings: [(node:Int,delta:Int)],_ a: inout A) throws -> Int {
        let count = crossings.count,twice = count.multipliedReportingOverflow(by:2)
        let capacity = twice.partialValue.addingReportingOverflow(1)
        guard !twice.overflow,!capacity.overflow else { throw ExactScalarFailure.countOverflow }
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:capacity.partialValue,of:Int.self))
        var next: [Int] = [];next.reserveCapacity(capacity.partialValue)
        for sum in -count...count { next.append(try node(.literal(sum != 0),&a)) }
        if count == 0 { return next[0] }
        for index in crossings.indices.reversed() {
            let size = index*2+1
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:size,of:Int.self))
            var current: [Int] = [];current.reserveCapacity(size)
            let crossing = crossings[index],inverse = try not(crossing.node,&a)
            for sum in -index...index {
                let offset = index+1
                current.append(try or(and(crossing.node,next[sum+crossing.delta+offset],&a),and(inverse,next[sum+offset],&a),&a))
            }
            next = current
        }
        return next[0]
    }
    func instructions<A: ExactScalarAdmission & ~Copyable>(_ root: Int,_ a: inout A) throws -> [ExactRealCellInstruction] {
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:(Int,Bool).self))
        var pending: [(index:Int,finished:Bool)] = [(root,false)],result: [ExactRealCellInstruction] = []
        while let item = pending.popLast() {
            try a.consumeWork(1)
            let instruction: ExactRealCellInstruction?
            switch nodes[item.index] {
            case .literal(let value):instruction = .literal(value)
            case .sign(let index,let relation):instruction = .sign(polynomial:index,relation:relation)
            case .not(let child):
                if item.finished { instruction = .not }
                else { try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:(Int,Bool).self));pending.append((item.index,true));pending.append((child,false));instruction = nil }
            case .and(let left,let right),.or(let left,let right):
                if item.finished { if case .and = nodes[item.index] { instruction = .and } else { instruction = .or } }
                else { try a.retainStorage(bytes:exactScalarPayloadBytes(count:3,of:(Int,Bool).self));pending.append((item.index,true));pending.append((right,false));pending.append((left,false));instruction = nil }
            }
            if let instruction { try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:ExactRealCellInstruction.self));result.append(instruction) }
        }
        return result
    }
    func boundaryReferences<A: ExactScalarAdmission & ~Copyable>(in pullback: ExactRealCellPullback<Base>,
        using a: inout A) throws -> [[OriginalNativeBoundaryDomain.SpanReference]] {
        let region = pullback.region
        var included = false
        for value in region.included { try a.consumeWork(1);if value { included = true;break } }
        if !included {
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:region.cells.count,of:[OriginalNativeBoundaryDomain.SpanReference].self))
            return Array(repeating:[],count:region.cells.count)
        }
        let domain = try ExactRealCellDomain<Base>(retaining:region.partition.source,using:&a)
        try a.admitDepth(value:region.depth.value,coefficient:region.depth.coefficient)
        let scalar = try domain.coefficientField(of:region.partition.source,using:&a)
        let polynomials = domain.polynomials
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:laws.count,of:Int.self))
        var ordinals: [Int] = [];ordinals.reserveCapacity(laws.count)
        for law in laws {
            try a.consumeWork(1)
            var transported = try polynomials.importing(law,using:&a)
            // L4's sealed reductions certify ordinal-preserving substitutions over
            // this complete retained singleton box, not global polynomial equality.
            for proof in region.reductions {
                try a.consumeWork(1)
                guard let box = proof.domainRestriction,!box.isEmpty,box.includesLower,box.includesUpper,
                    proof.variable >= 0,proof.variable < region.partition.source.domains.count,
                    proof.originalAtoms.count == proof.derivedAtoms.count,
                    case .finite(let lo) = box.lower,case .finite(let hi) = box.upper,
                    try scalar.compare(lo,hi,using:&a) == .equal else { throw NativeExactRelationFailure.invalidDomain }
                let scope = region.partition.source.domains[proof.variable]
                guard !scope.isEmpty,scope.includesLower,scope.includesUpper,
                    case .finite(let scopeLo) = scope.lower,case .finite(let scopeHi) = scope.upper,
                    try scalar.compare(lo,scopeLo,using:&a) == .equal,
                    try scalar.compare(hi,scopeHi,using:&a) == .equal else { throw NativeExactRelationFailure.invalidDomain }
                var derived: Polynomial? = nil
                for index in proof.originalAtoms.indices {
                    try a.consumeWork(1)
                    if try polynomials.equals(transported,polynomials.importing(proof.originalAtoms[index],using:&a),using:&a) {
                        derived = try polynomials.importing(proof.derivedAtoms[index],using:&a)
                        break
                    }
                }
                guard let derived else { throw NativeExactRelationFailure.invalidDomain }
                transported = derived
            }
            var ordinal: Int? = nil
            for index in region.partition.source.polynomials.indices {
                try a.consumeWork(1)
                if try polynomials.equals(transported,region.partition.source.polynomials[index],using:&a) { ordinal = index;break }
            }
            guard let ordinal else { throw NativeExactRelationFailure.invalidDomain }
            ordinals.append(ordinal)
        }
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:region.cells.count,of:[OriginalNativeBoundaryDomain.SpanReference].self))
        var result: [[OriginalNativeBoundaryDomain.SpanReference]] = [];result.reserveCapacity(region.cells.count)
        for index in region.cells.indices {
            try a.consumeWork(1)
            var spans: [OriginalNativeBoundaryDomain.SpanReference] = []
            if region.included[index] {
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:ordinals.count,of:ExactSign.self))
                var signs: [ExactSign] = [];signs.reserveCapacity(ordinals.count)
                // Original input-law signs have L3's whole-cell lifting authority.
                // Auxiliary projection/derivative signs and samples are never used.
                for ordinal in ordinals {
                    try a.consumeWork(1)
                    guard region.cells[index].signs.indices.contains(ordinal) else { throw NativeExactRelationFailure.invalidDomain }
                    signs.append(region.cells[index].signs[ordinal])
                }
                let values = try values(signs,&a)
                for ordinal in references.indices where values[boundaryNodes[ordinal]] {
                    try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalNativeBoundaryDomain.SpanReference.self))
                    spans.append(references[ordinal])
                }
            }
            result.append(spans)
        }
        return result
    }
    private func values<A: ExactScalarAdmission & ~Copyable>(_ signs: [ExactSign],_ a: inout A) throws -> [Bool] {
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:nodes.count,of:Bool.self))
        var result: [Bool] = [];result.reserveCapacity(nodes.count)
        for node in nodes {
            try a.consumeWork(1)
            let value: Bool
            switch node {
            case .literal(let constant):value = constant
            case .sign(let index,let relation):
                switch relation {
                case .equal:value = signs[index] == .zero
                case .notEqual:value = signs[index] != .zero
                case .less:value = signs[index] == .negative
                case .lessOrEqual:value = signs[index] != .positive
                case .greater:value = signs[index] == .positive
                case .greaterOrEqual:value = signs[index] != .negative
                }
            case .not(let child):value = !result[child]
            case .and(let left,let right):value = result[left] && result[right]
            case .or(let left,let right):value = result[left] || result[right]
            }
            result.append(value)
        }
        return result
    }
}
