import CADCore
@testable import CADGeometry
@testable import PolylineLiftAdapters
@testable import PublicLiftPlane
@testable import PublicLiftPlanePort
import struct PolylineLiftAdapters.OriginalFiniteBSplineCharts
import struct PolylineLiftAdapters.DefaultOriginalFiniteBSplineChartPreparer
import struct PublicLiftPlanePort.DefaultCurveSurfaceIntersector
import struct PublicLiftPlanePort.CurveSurfaceIntersectionResult
import struct PolylineLiftAdapters.OriginalPolylinePcurveSnapshot
import struct PolylineLiftAdapters.OriginalPolylinePcurveSnapshotProvider
import struct PolylineLiftAdapters.OriginalPolylineSurfaceLiftSnapshot
import struct PolylineLiftAdapters.OriginalPolylineSurfaceLiftSnapshotProvider
import protocol PolylineLiftAdapters.OriginalRetainedCurveSourceReading
import struct PolylineLiftAdapters.OriginalFiniteRetainedCurveCharts
import protocol PolylineLiftAdapters.OriginalFiniteRetainedCurveChartPreparing
import struct PolylineLiftAdapters.DefaultOriginalFiniteRetainedCurveChartPreparer
import struct PolylineLiftAdapters.OriginalNativeSurfaceFamilySnapshotProvider
import struct PolylineLiftAdapters.OriginalBSplineSurfaceSnapshotProvider
import protocol PolylineLiftAdapters.OriginalLiftGraphSourceReading
import protocol PolylineLiftAdapters.OriginalLiftSourceReading
import protocol PolylineLiftAdapters.OriginalRetainedPcurveLiftSourceReading
import protocol PolylineLiftAdapters.OriginalRetainedSurfaceLiftSourceReading
import protocol PolylineLiftAdapters.OriginalRetainedSurfaceSourceReading
import struct PolylineLiftAdapters.OriginalFiniteRetainedSurfaceCharts
import protocol PolylineLiftAdapters.OriginalRetainedAtlasLiftSourceReading
import protocol PolylineLiftAdapters.OriginalNativePcurveRetainedAtlasLiftSourceReading
import protocol PolylineLiftAdapters.OriginalSurfaceLiftSourceReading
import struct PolylineLiftAdapters.OriginalFiniteRetainedSurfaceLiftGraphs
import struct PolylineLiftAdapters.OriginalSurfaceLiftGraphEvidence
import protocol PolylineLiftAdapters.OriginalFiniteRetainedSurfaceLiftGraphPreparing
import protocol PolylineLiftAdapters.OriginalFiniteRetainedAtlasLiftGraphPreparing
import protocol PolylineLiftAdapters.OriginalFiniteNativePcurveRetainedAtlasLiftGraphPreparing
import struct PolylineLiftAdapters.DefaultOriginalFiniteRetainedSurfaceLiftGraphPreparer
import struct PolylineLiftAdapters.OriginalParametricGraphReceipt
import struct PolylineLiftAdapters.OriginalParametricGraphCondition
import struct PolylineLiftAdapters.OriginalParametricVariableLayout
import protocol PolylineLiftAdapters.OriginalFiniteBSplineChartPreparing
import struct PolylineLiftAdapters.OriginalBSplineFundamentalCharts
import protocol PolylineLiftAdapters.OriginalBSplineFundamentalChartPreparing
import struct PolylineLiftAdapters.DefaultOriginalBSplineFundamentalChartPreparer
import struct PolylineLiftAdapters.OriginalPeriodicNativeSurfaceLiftGraphs
import protocol PolylineLiftAdapters.OriginalPeriodicNativeSurfaceLiftGraphQuerying
import protocol PolylineLiftAdapters.OriginalPeriodicNativeSurfaceLiftGraphPreparing
import protocol PolylineLiftAdapters.OriginalPeriodicRetainedSurfaceLiftGraphPreparing
import struct PolylineLiftAdapters.DefaultOriginalPeriodicNativeSurfaceLiftGraphPreparer
import protocol PolylineLiftAdapters.OriginalParametricGraphDomainBinding
import struct PolylineLiftAdapters.OriginalDomainBoundParametricGraph
import struct PolylineLiftAdapters.DefaultOriginalParametricGraphDomainBinder
import protocol PolylineLiftAdapters.OriginalRetainedSurfaceLiftDomainIssuing
import struct PolylineLiftAdapters.OriginalRetainedSurfaceLiftDomainCover
import struct PolylineLiftAdapters.DefaultOriginalRetainedSurfaceLiftDomainIssuer
import struct PolylineLiftAdapters.OriginalPeriodicNativeSurfaceLiftDomainSpace
import protocol PolylineLiftAdapters.OriginalPeriodicNativeSurfaceLiftDomainIssuing
import struct PolylineLiftAdapters.OriginalPeriodicNativeSurfaceLiftDomainCover
import protocol PolylineLiftAdapters.OriginalPeriodicNativeSurfaceLiftDomainQuerying
import struct PolylineLiftAdapters.OriginalPeriodicNativeSurfaceLiftChartOccurrence
import struct PolylineLiftAdapters.DefaultOriginalPeriodicNativeSurfaceLiftDomainIssuer
import struct PolylineLiftAdapters.OriginalPolylineRetainedAtlasLiftSnapshot
import struct PolylineLiftAdapters.OriginalPolylineRetainedAtlasLiftSnapshotProvider
import protocol PolylineLiftAdapters.OriginalRetainedLiftHostSnapshotting
import struct PolylineLiftAdapters.OriginalRetainedSurfaceCell
import protocol PolylineLiftAdapters.OriginalFiniteRetainedSurfaceChartPreparing
import struct PolylineLiftAdapters.DefaultOriginalFiniteRetainedSurfaceChartPreparer
import struct PolylineLiftAdapters.OriginalCoonsAtlasSnapshot
import struct PolylineLiftAdapters.OriginalCoonsAtlasSnapshotProvider
import struct PolylineLiftAdapters.OriginalBoundaryCorrectionSnapshot
import struct PolylineLiftAdapters.OriginalBoundaryCorrectionSnapshotProvider
import struct PolylineLiftAdapters.OriginalPreparedPolylinePcurves
import protocol PolylineLiftAdapters.OriginalPolylinePcurveFamilyPreparing
import struct PolylineLiftAdapters.DefaultOriginalPolylinePcurveFamilyPreparer
import struct PolylineLiftAdapters.OriginalPolynomialSurfaceLiftGraphReduction
import protocol PolylineLiftAdapters.OriginalPolynomialSurfaceLiftGraphReducing
import struct PolylineLiftAdapters.DefaultOriginalPolynomialSurfaceLiftGraphReducer
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

public struct DefaultOriginalRationalGraphFamilyPreparer<S:Sendable,C:Sendable>:OriginalIssuedGraphFamilyPreparing {
    public typealias Source=S
    public typealias Evidence=OriginalRationalChartReceipt<S,C,OriginalExactScalarDomain>
    public typealias Cover=OriginalIssuedDomainCover<S,C,OriginalExactScalarDomain>
    public init() {}
    public func prepare<A:ExactScalarAdmission & ~Copyable>(cover:borrowing Cover,field:borrowing ExactAlgebraicScalarDomain<OriginalExactScalarDomain>,
        maximumGraphs:Int,limits:OriginalDomainIdentityLimits,using admission:inout A)
        throws(NativeExactRelationFailure) -> OriginalIssuedGraphFamily<S,Evidence,Cover> {
        do {
            try admission.checkpoint()
            guard maximumGraphs >= 0 else { throw NativeExactRelationFailure.invalidDomain }
            guard cover.laws.count <= limits.maximumCharts,cover.charts.count <= maximumGraphs else { throw OriginalDomainIdentityFailure.chartLimit }
            let request=cover.coverage.request,source=request.frame.source
            guard source.sourceDepth <= limits.source.remainingSourceDepth else { throw OriginalDomainIdentityFailure.sourceDepthLimit }
            _=try field.importingBase(request.frame.scalarField.integer(0,using:&admission),using:&admission)
            var v=0,c=0
            for axis in request.frame.axes { try admission.consumeWork(1);v=max(v,axis.depth.value);c=max(c,axis.depth.coefficient) }
            for axis in request.axes { try admission.consumeWork(1);v=max(v,axis.depth.value);c=max(c,axis.depth.coefficient) }
            for law in cover.laws {
                try admission.consumeWork(1);try law.admitProof(using:&admission)
                if let depth=law.proofDepth {v=max(v,depth.value);c=max(c,depth.coefficient)}
                for p in law.homogeneous { try admission.consumeWork(1);v=max(v,p.depth.value);c=max(c,p.depth.coefficient) }
                for p in law.parameterTransport.numerators { try admission.consumeWork(1);v=max(v,p.depth.value);c=max(c,p.depth.coefficient) }
                for p in law.parameterTransport.denominators { try admission.consumeWork(1);v=max(v,p.depth.value);c=max(c,p.depth.coefficient) }
            }
            try admission.retainStorage(bytes:exactScalarPayloadBytes(count:cover.charts.count,of:OriginalIssuedGraphPreparation<S,Evidence>.self))
            var graphs:[OriginalIssuedGraphPreparation<S,Evidence>]=[];graphs.reserveCapacity(cover.charts.count)
            for chart in cover.charts {
                try admission.consumeWork(1)
                let graph=try DefaultOriginalRationalGraphIssuer().issue(cover.laws[chart.lawIndex],limits:limits.source,using:&admission)
                let binding=try DefaultOriginalParametricGraphDomainBinder().bind(graph:graph,request:request,limits:limits,using:&admission)
                let prepared=try DefaultOriginalIssuedGraphCompiler().compile(binding:binding,field:copy field,limits:limits,using:&admission)
                v=max(v,prepared.depth.value);c=max(c,prepared.depth.coefficient);graphs.append(prepared)
            }
            let depth=try ExactScalarDepth(value:v,coefficient:c);try admission.admitDepth(value:v,coefficient:c)
            try admission.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalIssuedGraphFamily<S,Evidence,Cover>.self))
            let result=OriginalIssuedGraphFamily(coverage:copy cover,source:source,field:copy field,graphs:graphs,parameterCount:request.arity,templateCount:cover.laws.count,depth:depth)
            try admission.checkpoint();return result
        } catch { throw .preserving(error) }
    }
}
