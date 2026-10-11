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

import CADCore

/// One original lift/plane solve under the composing public caller allowance.
struct OriginalRetainedLiftPlanePublicProducer {
    func resolve(curve: Curve3D, surface: Surface3D, options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance, invocation: CurveSurfaceQueryInvocation? = nil,
        retainingRelations: Bool = false) throws -> CurveSurfaceIntersectionResult? {
        guard case .surfaceLift(let input) = curve, input.exactBSplineImage == nil,
            case .polyline = input.parameterCurve else { return nil }
        let normal: Vector3D
        switch surface {
        case .plane(let plane) where plane.uDirection == nil: normal = plane.normal
        case .analytic(.plane(_,let n)): normal = n
        default: return nil
        }
        // FIXME(INCOMPLETE_IMPLEMENTATION): The ordinary lift/plane dispatcher
        // presently issues an exact basis for axis normals only. General normals
        // require their original algebraic lengths before this family is complete.
        let length: Double
        if normal.x != 0 && normal.y == 0 && normal.z == 0 { length = abs(normal.x) }
        else if normal.y != 0 && normal.x == 0 && normal.z == 0 { length = abs(normal.y) }
        else if normal.z != 0 && normal.x == 0 && normal.y == 0 { length = abs(normal.z) }
        else { return nil }
        switch input.surface {
        case .procedural(.originalCoons):
            return try resolve(input:input,surface:surface,options:options,tolerance:tolerance,
                invocation:invocation,retainingRelations:retainingRelations,length:length,
                host:{ OriginalCoonsAtlasSnapshotProvider(field:$0,tolerance:tolerance) })
        case .procedural(.originalBoundaryCorrected):
            return try resolve(input:input,surface:surface,options:options,tolerance:tolerance,
                invocation:invocation,retainingRelations:retainingRelations,length:length,
                host:{ OriginalBoundaryCorrectionSnapshotProvider(field:$0,tolerance:tolerance) })
        default: return nil
        }
    }

    private func resolve<P: OriginalRetainedLiftHostSnapshotting>(input:SurfaceLiftCurve3D,
        surface:Surface3D,options:CurveSurfaceIntersectionOptions,tolerance:ModelingTolerance,
        invocation:CurveSurfaceQueryInvocation?,retainingRelations:Bool,length:Double,
        host makeHost:(OriginalExactScalarDomain) -> P) throws -> CurveSurfaceIntersectionResult {
        typealias Source = OriginalPolylineRetainedAtlasLiftSnapshot<P.Source>
        do {
            try options.validate(tolerance:tolerance)
            let usage = try NativeCurveSurfacePointAllowance(options:options,invocation:invocation)
            let depth = usage.maximumAlgebraicDepth
            var a = NativeExactPublicAdmission(usage:usage,maximumDepth:depth)
            try a.checkpoint();try invocation?.consume(depth:0)
            let sourceLimits = try OriginalSourceIssuanceLimits(
                remainingSourceDepth:invocation?.remainingSourceDepth ?? options.maximumSubdivisionDepth)
            let charts = min(invocation?.maximumSpanCount ?? options.maximumSubdivisionCells,
                options.maximumSubdivisionCells)
            let limits = try OriginalDomainIdentityLimits(source:sourceLimits,maximumTransportDepth:depth,
                maximumCharts:charts,maximumFamilies:2,maximumIdentityProofs:0)
            let pcurve = try DefaultOriginalSourceBindingIssuer(provider:OriginalPolylinePcurveSnapshotProvider(
                maximumValueDepth:depth,maximumCoefficientDepth:depth))
                .bind(input.parameterCurve,limits:sourceLimits,using:&a)
            let f = pcurve.original.originalField
            let provider = OriginalPolylineRetainedAtlasLiftSnapshotProvider(
                host:makeHost(f),pcurve:pcurve)
            let source = try DefaultOriginalSourceBindingIssuer(provider:provider).bind(input,limits:sourceLimits,using:&a)
            let host = try DefaultOriginalFiniteRetainedSurfaceChartPreparer<P.Source>()
                .prepare(source:source.original.originalSurface,maximumCharts:charts,limits:sourceLimits,using:&a)
            let pc = try DefaultOriginalFiniteRetainedCurveChartPreparer<OriginalPolylinePcurveSnapshot>()
                .prepare(source:pcurve,maximumCharts:charts,limits:sourceLimits,using:&a)
            let family = try DefaultOriginalFiniteRetainedSurfaceLiftGraphPreparer<Source>()
                .prepare(source:source,surface:host,pcurve:pc,maximumCharts:charts,limits:sourceLimits,using:&a)
            for graph in family.graphs {
                for law in graph.homogeneous {
                    for term in law.terms {
                        try a.consumeWork(1)
                        guard term.powers.allSatisfy({ $0 <= options.maximumPolynomialDegree }) else {
                            throw ExactScalarFailure.resourceLimit(.work)
                        }
                    }
                }
            }
            let issuer = DefaultOriginalRetainedSurfaceLiftDomainIssuer<Source>()
            let frame = try issuer.frame(family:family,limits:limits,using:&a)
            let selection = try options.curveRange.map { range in
                try frame.selection(intervals:[[interval(range,field:f,using:&a)]],limits:limits,using:&a)
            } ?? frame.fullSelection(limits:limits,using:&a)
            let lift = try issuer.issue(request:selection,family:family,limits:limits,using:&a)
            let plane = try DefaultOriginalSourceBindingIssuer(provider:OriginalPlaneSnapshotProvider(tolerance:tolerance))
                .bind(surface,limits:sourceLimits,using:&a)
            let exactLength = try f.binary64(exactly:length,using:&a)
            let basis = try DefaultOriginalPlaneBasisIssuer<OriginalPlaneSnapshot,OriginalExactScalarDomain>()
                .issue(source:plane,field:f,firstLength:exactLength,normalLength:exactLength,limits:sourceLimits,using:&a)
            let domain = DefaultOriginalPlaneDomainIssuer<OriginalPlaneSnapshot,OriginalExactScalarDomain>()
            let planeFrame = try domain.frame(basis:basis,limits:limits,using:&a)
            let full = try planeFrame.fullSelection(limits:limits,using:&a)
            let planeRequest: OriginalParameterSelection<OriginalPlaneSnapshot,OriginalExactScalarDomain>
            if options.surfaceURange != nil || options.surfaceVRange != nil {
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:[ExactParameterInterval<OriginalExactScalar>].self))
                var intervals:[[ExactParameterInterval<OriginalExactScalar>]] = [];intervals.reserveCapacity(2)
                for axis in 0..<2 {
                    let selected = axis == 0 ? options.surfaceURange:options.surfaceVRange
                    if let selected {
                        try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:ExactParameterInterval<OriginalExactScalar>.self))
                        intervals.append([try interval(selected,field:f,using:&a)])
                    } else {
                        let retained = full.axes[axis].intervals
                        try a.retainStorage(bytes:exactScalarPayloadBytes(count:retained.count,of:ExactParameterInterval<OriginalExactScalar>.self))
                        intervals.append(Array(retained))
                    }
                }
                planeRequest = try planeFrame.selection(intervals:intervals,limits:limits,using:&a)
            } else { planeRequest = full }
            let cover = try domain.issue(request:planeRequest,basis:basis,limits:limits,using:&a)
            let field = try ExactAlgebraicScalarDomain.base(field:f,maximumExtensionLevel:Int.max,using:&a)
            let target = try DefaultOriginalPlaneGraphCompiler<OriginalPlaneSnapshot>().compile(cover:cover,field:field,limits:limits,using:&a)
            // FIXME(INCOMPLETE_IMPLEMENTATION): Contained-family publication currently
            // accepts the full authored curve and whole plane. Clipped/singular request
            // publication must retain every exact preimage before this branch is general.
            if options.curveRange == nil, options.surfaceURange == nil, options.surfaceVRange == nil,
                let contained = try DefaultOriginalContainedLiftPlaneResolver().resolve(lift:lift,plane:target,
                    maximumPieces:options.maximumCandidateCount,limits:limits,using:&a) {
                if !retainingRelations && contained.hasPositiveDimensionalSolutions {
                    throw KernelError(phase:.geometry,code:.nonDiscreteIntersection,tolerance:tolerance,
                        message:"The original lift lies in the plane over a positive-dimensional domain.")
                }
                // FIXME(INCOMPLETE_IMPLEMENTATION): The bare ordinary CS API needs a
                // numerical point publisher for isolated-only contained families. Until
                // every singleton is published it must fail, never return an empty array.
                if !retainingRelations && !contained.isEmpty {
                    throw KernelError(phase:.geometry,code:.unsupportedCapability,tolerance:tolerance,
                        message:"Isolated contained-family contacts require exact point publication.")
                }
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:CurveSurfaceIntersectionResult.self))
                let result = CurveSurfaceIntersectionResult(points:[],overlaps:[],originalContainedLiftPlaneFamily:contained)
                try a.checkpoint();return result
            }
            let unbounded = try NativeExactPublicLimits.unboundedStructure()
            let topology = unbounded.topology
            let geometry = try ExactGeometricRelationLimits(cells:unbounded.cells,
                topology:.init(maximumGeneratedCells:topology.maximumGeneratedCells,maximumRootsPerStack:topology.maximumRootsPerStack,
                    maximumClosures:min(topology.maximumClosures,options.maximumCandidateCount),
                    maximumAttachmentPieces:topology.maximumAttachmentPieces,maximumComponents:topology.maximumComponents),
                maximumStrata:unbounded.maximumStrata,maximumProjectionSpans:unbounded.maximumProjectionSpans)
            let original = try DefaultOriginalLiftPlaneRelationResolver().resolve(lift:lift,plane:target,
                maximumPairs:charts,limits:limits,cellLimits:geometry.cells,topologyLimits:geometry.topology,using:&a)
            var selected = 0,components = 0
            for pair in original.pairs {
                try a.consumeWork(1)
                let nextSelected = selected.addingReportingOverflow(pair.relation.selection.cells.count)
                let nextComponents = components.addingReportingOverflow(pair.relation.components.count)
                guard !nextSelected.overflow,!nextComponents.overflow,
                    nextSelected.partialValue <= options.maximumCandidateCount,nextComponents.partialValue <= options.maximumCandidateCount else {
                    throw ExactScalarFailure.resourceLimit(.work)
                }
                selected = nextSelected.partialValue;components = nextComponents.partialValue
            }
            let publication = try OriginalIssuedGeometricPublication.resolve(original,geometryLimits:geometry,
                maximumPoints:options.maximumCandidateCount,
                transports:{ pair in (original.firstGraphs[pair.firstGraphIndex].original.graph.parameterTransport,nil) },
                firstCoordinates:{ pair in original.firstReductions[pair.firstGraphIndex].originalCoordinates },using:&a)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalLiftPlaneGeometricRelations<Source,OriginalPlaneSnapshot>.self))
            let receipt = OriginalLiftPlaneGeometricRelations(original:original,pairs:publication.pairs,exactPoints:publication.points)
            guard retainingRelations || !receipt.hasPositiveDimensionalSolutions else {
                throw KernelError(phase:.geometry,code:.nonDiscreteIntersection,tolerance:tolerance,
                    message:"The original lift/plane relation contains a positive-dimensional intersection.")
            }
            let numeric = try OriginalLiftPlanePointPublisher<Source>().publish(receipt,options:options,tolerance:tolerance,
                limits:limits,maximumDepth:depth,using:&a)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:CurveSurfaceIntersectionResult.self))
            let result = CurveSurfaceIntersectionResult(points:numeric.points,overlaps:[],
                originalIssuedGeometricRelation:numeric.receipt.geometry,originalIssuedNumericalPoints:numeric.receipt)
            try a.checkpoint();return result
        } catch { throw NativeExactGeometryPublicationFailure.published(error,tolerance:tolerance) }
    }

    private func interval<A: ExactScalarAdmission & ~Copyable>(_ range: ScalarInterval,
        field:OriginalExactScalarDomain,using a:inout A) throws -> ExactParameterInterval<OriginalExactScalar> {
        let lower = try field.binary64(exactly:range.lower,using:&a),upper = try field.binary64(exactly:range.upper,using:&a)
        return try .checked(field:field,lower:.finite(lower),upper:.finite(upper),includesLower:true,includesUpper:true,
            depth:.init(value:max(lower.depth.value,upper.depth.value),coefficient:max(lower.depth.coefficient,upper.depth.coefficient)),using:&a)
    }
}
