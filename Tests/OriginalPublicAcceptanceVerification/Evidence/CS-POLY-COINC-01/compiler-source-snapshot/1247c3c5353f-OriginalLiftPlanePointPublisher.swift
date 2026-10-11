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

/// Exact parameter grouping and certified numerical publication of retained lift incidents.
struct OriginalLiftPlanePointPublisher {
    typealias F = OriginalExactScalarDomain
    typealias S = OriginalRetainedLiftPlanePublicProducer.Source
    typealias Geometry = OriginalLiftPlaneGeometricRelations<S,OriginalPlaneSnapshot>

    func publish<A: ExactScalarAdmission & ~Copyable>(_ geometry: Geometry,
        options:CurveSurfaceIntersectionOptions,tolerance:ModelingTolerance,
        limits:OriginalDomainIdentityLimits,maximumDepth:Int,using a:inout A)
        throws -> (points:[CurveSurfaceIntersection],receipt:OriginalIssuedNumericalCurveSurfacePoints) {
        let count = geometry.exactPoints.count
        guard count <= options.maximumCandidateCount else { throw ExactScalarFailure.resourceLimit(.work) }
        let total = count.multipliedReportingOverflow(by:6)
        guard !total.overflow else { throw ExactScalarFailure.countOverflow }
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:total.partialValue,of:ExactAlgebraicScalar<F>.self))
        var exact:[ExactAlgebraicScalar<F>] = [];exact.reserveCapacity(total.partialValue)
        for point in geometry.exactPoints {
            try a.consumeWork(1)
            guard point.firstParameters.count == 1,point.secondParameters.count == 2 else {
                throw ExactGeometricRelationFailure.invalidSourceBinding
            }
            exact.append(point.firstParameters[0]);exact.append(contentsOf:point.secondParameters)
            exact.append(point.position.x);exact.append(point.position.y);exact.append(point.position.z)
        }
        let transferred = try DefaultExactOriginalScalarTransporter().transfer(exact,into:geometry.original.first.family.field,using:&a)
        let f = transferred.field,values = transferred.values
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:count,of:Int.self))
        var ordinals:[Int] = [];ordinals.reserveCapacity(count)
        for index in 0..<count { try a.consumeWork(1);ordinals.append(index) }
        func order(_ left:Int,_ right:Int,_ a:inout A) throws -> ExactOrder {
            for axis in 0..<3 {
                let result = try f.compare(values[6*left+axis],values[6*right+axis],using:&a)
                if result != .equal { return result }
            }
            return .equal
        }
        // Index heap sort keeps one immutable coordinate buffer and bounded scratch.
        func sift(_ start:Int,_ end:Int,_ indices:inout [Int],_ a:inout A) throws {
            var parent = start
            while parent < end/2 {
                var child = parent*2+1
                if child+1 < end,try order(indices[child],indices[child+1],&a) == .less { child += 1 }
                if try order(indices[parent],indices[child],&a) != .less { return }
                indices.swapAt(parent,child);parent = child
            }
        }
        if count > 1 {
            for start in stride(from:count/2-1,through:0,by:-1) { try sift(start,count,&ordinals,&a) }
            for end in stride(from:count-1,through:1,by:-1) {
                ordinals.swapAt(0,end);try sift(0,end,&ordinals,&a)
            }
        }
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:count,of:Range<Int>.self))
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:count,of:CurveSurfaceIntersection.self))
        var ranges:[Range<Int>] = [];ranges.reserveCapacity(count)
        var points:[CurveSurfaceIntersection] = [];points.reserveCapacity(count)
        var start = 0
        while start < count {
            var end = start+1
            while end < count,try order(ordinals[start],ordinals[end],&a) == .equal { end += 1 }
            let range = start..<end
            let kind = try classify(geometry,ordinals:ordinals,range:range,tolerance:tolerance,using:&a)
            points.append(try representative(geometry,transfer:transferred,ordinals:ordinals,range:range,
                kind:kind,options:options,tolerance:tolerance,limits:limits,maximumDepth:maximumDepth,using:&a))
            ranges.append(range);start = end
        }
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalIssuedNumericalCurveSurfacePoints.self))
        let receipt = OriginalIssuedNumericalCurveSurfacePoints(geometry:geometry,coordinates:transferred,
            incidenceOrdinals:ordinals,incidenceRanges:ranges)
        try a.checkpoint();return (points,receipt)
    }

    private func classify<A:ExactScalarAdmission & ~Copyable>(_ geometry:Geometry,
        ordinals:[Int],range:Range<Int>,tolerance:ModelingTolerance,using a:inout A) throws -> CurveSurfaceIntersectionKind {
        let basis = geometry.original.second.original.law,base = basis.field
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:3,of:OriginalExactScalar.self))
        // The sealed orthonormal basis proves u x v parallel to the authored normal.
        // Angular classification is scale invariant; source/incidence retain the raw normal.
        let unitNormal = [
            try base.subtracting(base.multiplying(basis.u[1],basis.v[2],using:&a),base.multiplying(basis.u[2],basis.v[1],using:&a),using:&a),
            try base.subtracting(base.multiplying(basis.u[2],basis.v[0],using:&a),base.multiplying(basis.u[0],basis.v[2],using:&a),using:&a),
            try base.subtracting(base.multiplying(basis.u[0],basis.v[1],using:&a),base.multiplying(basis.u[1],basis.v[0],using:&a),using:&a)
        ]
        var answer:CurveSurfaceIntersectionKind?
        for index in range {
            let point = geometry.exactPoints[ordinals[index]],f = point.local.witness.field
            let pair = geometry.original.pairs[point.pairOrdinal]
            let graph = geometry.original.firstReductions[pair.firstGraphIndex].graph
            let p = try ExactPolynomialDomain(field:f,variableCount:1,using:&a)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:ExactAlgebraicScalar<F>.self))
            let t = [point.firstParameters[0]]
            let w = try lift(graph.homogeneous[3],ring:p,using:&a)
            let weight = try p.evaluated(w,at:t,using:&a).value
            let dw = try p.evaluated(p.differentiated(w,in:0,using:&a),at:t,using:&a).value
            var tangentSquared = try f.integer(0,using:&a),normalSquared = tangentSquared,dot = tangentSquared
            for axis in 0..<3 {
                let law = try lift(graph.homogeneous[axis],ring:p,using:&a)
                let value = try p.evaluated(law,at:t,using:&a).value
                let derivative = try p.evaluated(p.differentiated(law,in:0,using:&a),at:t,using:&a).value
                let tangent = try f.subtracting(f.multiplying(derivative,weight,using:&a),f.multiplying(value,dw,using:&a),using:&a)
                let normal = try f.importingBase(unitNormal[axis],using:&a)
                tangentSquared = try f.adding(tangentSquared,f.multiplying(tangent,tangent,using:&a),using:&a)
                normalSquared = try f.adding(normalSquared,f.multiplying(normal,normal,using:&a),using:&a)
                dot = try f.adding(dot,f.multiplying(tangent,normal,using:&a),using:&a)
            }
            let kind:CurveSurfaceIntersectionKind
            if try f.sign(of:tangentSquared,using:&a) == .zero || f.sign(of:normalSquared,using:&a) == .zero { kind = .mixed }
            else {
                let angle = try f.binary64(exactly:tolerance.angle,using:&a)
                let threshold = try f.multiplying(f.multiplying(tangentSquared,normalSquared,using:&a),f.multiplying(angle,angle,using:&a),using:&a)
                kind = try f.compare(f.multiplying(dot,dot,using:&a),threshold,using:&a) == .greater ? .transverse:.tangent
            }
            // FIXME(INCOMPLETE_IMPLEMENTATION): Ordinary retained-lift publication
            // currently requires all incident extensions to agree. Disagreeing
            // one-sided germs need their scoped classification receipt before success.
            guard answer == nil || answer == kind else { throw OriginalSourceIssuanceFailure.unsupportedRepresentation }
            answer = kind
        }
        guard let answer else { throw ExactGeometricRelationFailure.invalidCoverage }
        return answer
    }

    private func representative<A:ExactScalarAdmission & ~Copyable>(_ geometry:Geometry,
        transfer:ExactOriginalScalarTransferReceipt,ordinals:[Int],range:Range<Int>,kind:CurveSurfaceIntersectionKind,
        options:CurveSurfaceIntersectionOptions,tolerance:ModelingTolerance,limits:OriginalDomainIdentityLimits,
        maximumDepth:Int,using a:inout A) throws -> CurveSurfaceIntersection {
        let f = transfer.field,offset = ordinals[range.lowerBound]*6
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:6,of:OriginalSingularFieldValueIsolation.self))
        var isolations:[OriginalSingularFieldValueIsolation] = [];isolations.reserveCapacity(6)
        var inherited = ExactScalarDepth.zero
        for axis in 0..<6 {
            let value = transfer.values[offset+axis]
            inherited = try .init(value:max(inherited.value,value.depth.value),coefficient:max(inherited.coefficient,value.depth.coefficient))
        }
        let maximum = try ExactScalarDepth(value:maximumDepth,coefficient:maximumDepth)
        for axis in 0..<6 {
            let value = transfer.values[offset+axis]
            let seed = try ExactScalarNumericAccess.withAdmission(&a,original:value.depth,inherited:value.depth,maximum:maximum) { usage in
                try OriginalSingularFieldValueIsolation(original:value.original,inheritedDepth:value.depth.value,
                    maximumDepth:maximumDepth,usage:&usage)
            }
            inherited = try .init(value:max(inherited.value,seed.depth.value),coefficient:max(inherited.coefficient,seed.depth.coefficient))
            isolations.append(seed.value)
        }
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:6,of:OutwardScalarInterval.self))
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:6,of:Double.self))
        var bounds:[OutwardScalarInterval] = [];bounds.reserveCapacity(6)
        var numbers:[Double] = [];numbers.reserveCapacity(6)
        let epsilon = try f.binary64(exactly:tolerance.distance,using:&a),squared = try f.multiplying(epsilon,epsilon,using:&a)
        var width = ExactRationalCoefficient.one
        for iteration in 0..<options.maximumIterations {
            bounds.removeAll(keepingCapacity:true);numbers.removeAll(keepingCapacity:true)
            for axis in 0..<6 {
                let isolation = isolations[axis]
                let refinementDepth = try ExactScalarDepth(value:isolation.sourceDepth,coefficient:transfer.values[offset+axis].depth.coefficient)
                let refined = try ExactScalarNumericAccess.withAdmission(&a,original:refinementDepth,inherited:refinementDepth,maximum:maximum) { usage in
                    let next = try isolation.refined(maximumWidth:width,maximumDepth:maximumDepth,usage:&usage)
                    return (next,try next.enclosure(usage:&usage))
                }
                inherited = try .init(value:max(inherited.value,refined.depth.value),coefficient:max(inherited.coefficient,refined.depth.coefficient))
                isolations[axis] = refined.value.0;bounds.append(refined.value.1)
                var value = refined.value.1.lower*0.5+refined.value.1.upper*0.5
                if axis == 0 { value = max(options.curveRange?.lower ?? 0,min(options.curveRange?.upper ?? 1,value)) }
                if axis == 1,let request = options.surfaceURange { value = max(request.lower,min(request.upper,value)) }
                if axis == 2,let request = options.surfaceVRange { value = max(request.lower,min(request.upper,value)) }
                guard value.isFinite,value >= bounds[axis].lower,value <= bounds[axis].upper else {
                    throw ExactGeometricRelationFailure.invalidCoverage
                }
                numbers.append(value)
            }
            if bounds.allSatisfy({ $0.upper-$0.lower <= tolerance.distance }) {
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:6,of:OriginalExactScalar.self))
                var numeric:[OriginalExactScalar] = [];numeric.reserveCapacity(6)
                for number in numbers { numeric.append(try f.binary64(exactly:number,using:&a)) }
                var parametersValid = true
                for axis in 0..<3 {
                    let delta = try f.subtracting(transfer.values[offset+axis],numeric[axis],using:&a)
                    if try f.compare(f.multiplying(delta,delta,using:&a),squared,using:&a) == .greater { parametersValid = false }
                }
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:6,of:OriginalExactScalar.self))
                let point = [numeric[3],numeric[4],numeric[5]]
                let exactPosition = [transfer.values[offset+3],transfer.values[offset+4],transfer.values[offset+5]]
                let basis = geometry.original.second.original.law
                let bf = basis.field
                let target = try basis.position(u:bf.binary64(exactly:numbers[1],using:&a),
                    v:bf.binary64(exactly:numbers[2],using:&a),limits:limits,using:&a)
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:3,of:OriginalExactScalar.self))
                var surface:[OriginalExactScalar] = [];surface.reserveCapacity(3)
                for coordinate in target { surface.append(try f.importing(coordinate,using:&a)) }
                for incident in range {
                    let raw = geometry.exactPoints[ordinals[incident]],pair = geometry.original.pairs[raw.pairOrdinal]
                    let graph = geometry.original.firstReductions[pair.firstGraphIndex].graph,gf = graph.field
                    try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalExactScalar.self))
                    let t = [try gf.binary64(exactly:numbers[0],using:&a)]
                    guard try graph.admits(t,limits:limits.source,using:&a) else { continue }
                    let weight = try graph.polynomials.evaluated(graph.homogeneous[3],at:t,using:&a).value
                    try a.retainStorage(bytes:exactScalarPayloadBytes(count:3,of:OriginalExactScalar.self))
                    var curve:[OriginalExactScalar] = [];curve.reserveCapacity(3)
                    for axis in 0..<3 {
                        curve.append(try f.importing(gf.dividing(graph.polynomials.evaluated(graph.homogeneous[axis],at:t,using:&a).value,weight,using:&a),using:&a))
                    }
                    if parametersValid,try within(exactPosition,point,squared:squared,field:f,using:&a),
                        try within(curve,surface,squared:squared,field:f,using:&a),
                        try within(curve,point,squared:squared,field:f,using:&a),
                        try within(surface,point,squared:squared,field:f,using:&a) {
                        return try .init(point:.init(x:numbers[3],y:numbers[4],z:numbers[5]),curveParameter:numbers[0],
                            surfaceU:numbers[1],surfaceV:numbers[2],kind:kind,residual:tolerance.distance,iterations:iteration)
                    }
                }
            }
            width = try ExactScalarNumericAccess.withAdmission(&a,inherited:inherited,maximum:maximum) { usage in
                try width.divided(by:.natural(2,usage:&usage),usage:&usage)
            }.value
        }
        throw KernelError(phase:.geometry,code:.resourceLimitExceeded,tolerance:tolerance,
            message:"Original lift/plane publication exhausted the caller's refinement iterations.")
    }

    private func lift<A:ExactScalarAdmission & ~Copyable>(_ law:ExactPolynomial<F>,
        ring:ExactPolynomialDomain<ExactAlgebraicScalarDomain<F>>,using a:inout A)
        throws -> ExactPolynomial<ExactAlgebraicScalarDomain<F>> {
        try a.admitDepth(value:law.depth.value,coefficient:law.depth.coefficient)
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:law.terms.count,of:ExactPolynomialTerm<ExactAlgebraicScalar<F>>.self))
        var terms:[ExactPolynomialTerm<ExactAlgebraicScalar<F>>] = [];terms.reserveCapacity(law.terms.count)
        for term in law.terms {
            terms.append(.init(powers:term.powers,coefficient:try ring.field.importingBase(term.coefficient,using:&a)))
        }
        return try ring.polynomial(terms:terms,using:&a)
    }

    private func within<A:ExactScalarAdmission & ~Copyable>(_ first:[OriginalExactScalar],_ second:[OriginalExactScalar],
        squared:OriginalExactScalar,field:F,using a:inout A) throws -> Bool {
        var total = try field.integer(0,using:&a)
        for axis in 0..<3 {
            let delta = try field.subtracting(first[axis],second[axis],using:&a)
            total = try field.adding(total,field.multiplying(delta,delta,using:&a),using:&a)
        }
        return try field.compare(total,squared,using:&a) != .greater
    }
}
