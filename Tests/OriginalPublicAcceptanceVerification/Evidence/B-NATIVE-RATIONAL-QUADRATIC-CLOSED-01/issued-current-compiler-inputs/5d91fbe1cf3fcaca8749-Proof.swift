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
import CADCore
@testable import CADGeometry
@testable import PolylineLiftAdapters
@testable import PublicLiftPlane
@testable import PublicCoonsBoundary
import CADTopology
import CADKernel
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#endif

/// One changed issued-boundary path; the retained lower solver is a historical premise.
@main struct RationalQuadraticIssuedBoundaryRegression {
    typealias F = OriginalExactScalarDomain
    typealias Field = PublicLiftPlane.ExactAlgebraicScalarDomain<F>

    static func sourceAuthority() throws {
        var a = try PolylineLiftProof.Admission(work: 80_000_000)
        let base = try F(maximumValueDepth: 32, maximumCoefficientDepth: 32, using: &a)
        let field = try Field.base(field: base, maximumExtensionLevel: 32, using: &a)
        let curve = BSplineCurve2D(degree: 2, knots: [0, 0, 0, 1, 1, 1],
            controlPoints: [.init(x: 0.5, y: 0.25), .init(x: 0.25, y: 0.25), .init(x: 0, y: 0)],
            weights: [1, 3, 1])
        let source = try DefaultOriginalSourceBindingIssuer(provider: PublicCoonsBoundary.OriginalBSplinePcurveSnapshotProvider(tolerance: .standard))
            .bind(curve, limits: .init(remainingSourceDepth: 8), using: &a)
        let receipt = try PublicCoonsBoundary.DefaultOriginalRationalQuadraticBoundaryIssuer<BSplineCurve2D, Field>()
            .issue(source: source, field: field, limits: .init(remainingSourceDepth: 8), using: &a)
        try PolylineLiftProof.require(receipt.law.source.original == curve)
        let ring = receipt.law.polynomials
        let s = try ring.variable(0, using: &a), s2 = try ring.multiplying(s, s, using: &a)
        func constant(_ value: Double) throws -> ExactPolynomial<Field> {
            try ring.constant(field.binary64(exactly: value, using: &a), using: &a)
        }
        func linear(_ c: Double, _ gain: Double, _ square: Double) throws -> ExactPolynomial<Field> {
            try ring.adding(ring.adding(constant(c), ring.multiplying(constant(gain), s, using: &a), using: &a),
                ring.multiplying(constant(square), s2, using: &a), using: &a)
        }
        let expected = try [linear(0.5, 0.5, -1), linear(0.25, 1, -1.25), constant(0), linear(1, 4, -4)]
        let h = receipt.law.homogeneous
        for axis in 0..<4 {
            let lhs = try ring.multiplying(h[axis], expected[3], using: &a)
            let rhs = try ring.multiplying(expected[axis], h[3], using: &a)
            try PolylineLiftProof.require(ring.equals(lhs, rhs, using: &a))
        }
        let zero = try constant(0)
        for residual in receipt.identityResiduals { try PolylineLiftProof.require(ring.equals(residual, zero, using: &a)) }
        print("PASS OriginalExactScalarDomain rational quadratic source coefficients and complete source authority")
    }

    static func detachedResult() throws -> OriginalIssuedGraphFaceClippedParameters<
        BSplineCurve3D, OriginalRationalChartReceipt<BSplineCurve3D, OriginalBSplineChartSelection, F>, CoonsHoleBoundaryProbe.CurveCover,
        OriginalCoonsAtlasSnapshot, OriginalRationalChartReceipt<OriginalCoonsAtlasSnapshot, Int, F>, CoonsHoleBoundaryProbe.SurfaceCover> {
        var preparation = try PolylineLiftProof.Admission(work: 80_000_000)
        let host = try PolylineAtlasLiftProof.shape(multi: true, using: &preparation).0
        let face = try CoonsHoleBoundaryProbe.face(host: host)
        let field = try F(maximumValueDepth: 32, maximumCoefficientDepth: 32, using: &preparation)
        let limits = try PolylineLiftProof.limits()
        let raw = try CoonsHoleBoundaryProbe.raw(host: host, field: field, limits: limits, using: &preparation)
        let binding = try OriginalFaceSurfaceBinding.coons(raw.second.source, limits: limits.source, using: &preparation)
        let source = try OriginalIssuedGraphBoundarySource.secondSurface(raw, binding: binding, limits: limits, using: &preparation)
        var query = try PolylineLiftProof.Admission(work: 80_000_000)
        let result = try CADKernel.DefaultOriginalFaceBoundaryClipper().clip(source, to: face.1, in: face.0,
            selection: .closed, domainLimits: limits,
            cellLimits: .init(maximumStoredCells: 20_000, maximumRootsPerStack: 100),
            topologyLimits: .init(maximumGeneratedCells: 20_000, maximumRootsPerStack: 100,
                maximumClosures: 20_000, maximumAttachmentPieces: 100_000, maximumComponents: 1_000), using: &query)
        try PolylineLiftProof.require(result.faceID == face.1 && result.loops.count == 2 &&
            result.parameters.boundary.source.raw.second.source.owner === raw.second.source.owner)
        try PolylineLiftProof.require(result.parameters.boundary.preparedLoops.count == 2)
#if !hasFeature(Embedded)
        print("ISSUED query work", query.ledger.work, "storage", query.ledger.storageBytes)
#endif
        return result
    }

    static func issued() throws {
        let retained = try detachedResult()
        var independent = try PolylineLiftProof.Admission(work: 80_000_000)
        try CoonsHoleBoundaryAcceptance.verify(retained, using: &independent)
        try PolylineLiftProof.require(retained.parameters.refinements.map { $0.parameters.pairOrdinal } == [0, 1, 2, 3])
        print("PASS issued Coons closed: all four raw/refined ordinals, all terminal material iff, spans, detached lifetime")
    }
    static func main() throws {
        let group: String
#if hasFeature(Embedded)
        group = getenv("CAD_PROOF_GROUP").map { String(cString: $0) } ?? "issued"
#else
        group = CommandLine.arguments.dropFirst().first ?? "issued"
#endif
        switch group {
        case "source": try sourceAuthority()
        case "issued": try issued()
        case "all": try sourceAuthority(); try issued()
        default: throw ExactScalarFailure.invalidEvidence
        }
    }

}
