import struct GuideSeamPort.OriginalIssuedGraphRelations
import struct GuideSeamPort.DefaultOriginalIssuedGraphRelationResolver
import CADCore
@testable import CADGeometry
@testable import RetainedHostAdapters
import struct AngularSourcePhase.OriginalSourceProofAdmission
@testable import DerivativePayloadAccess
@testable import PublicLiftPlane
import struct RetainedHostAdapters.DefaultOriginalAnalyticCoordinateIssuer
import struct RetainedHostAdapters.DefaultOriginalBSplineChartIssuer
import struct RetainedHostAdapters.DefaultOriginalBSplineFundamentalChartPreparer
import struct RetainedHostAdapters.DefaultOriginalBSplinePeriodIssuer
import struct RetainedHostAdapters.DefaultOriginalConeImageIssuer
import struct RetainedHostAdapters.DefaultOriginalCoonsChartIssuer
import struct RetainedHostAdapters.DefaultOriginalCurveEndpointIssuer
import struct RetainedHostAdapters.DefaultOriginalFiniteBSplineChartPreparer
import struct RetainedHostAdapters.DefaultOriginalFiniteCoonsBoundaryPreparer
import struct RetainedHostAdapters.DefaultOriginalFiniteCoonsChartPreparer
import struct RetainedHostAdapters.DefaultOriginalFiniteGuideChartPreparer
import struct RetainedHostAdapters.DefaultOriginalFiniteNativeOffsetLawPreparer
import struct RetainedHostAdapters.DefaultOriginalFiniteNativeRollingBallGraphPreparer
import struct RetainedHostAdapters.DefaultOriginalFiniteNativeSurfaceLiftGraphPreparer
import struct RetainedHostAdapters.DefaultOriginalFiniteParameterImageChartPreparer
import struct RetainedHostAdapters.DefaultOriginalFiniteRetainedCurveChartPreparer
import struct RetainedHostAdapters.DefaultOriginalFiniteRetainedSurfaceChartPreparer
import struct RetainedHostAdapters.DefaultOriginalFiniteRetainedSurfaceLiftGraphPreparer
import struct RetainedHostAdapters.DefaultOriginalFiniteRevolutionLawPreparer
import struct RetainedHostAdapters.DefaultOriginalFiniteRollingBallGraphPreparer
import struct RetainedHostAdapters.DefaultOriginalFiniteRuledChartPreparer
import struct RetainedHostAdapters.DefaultOriginalFiniteSpatialChartPreparer
import struct RetainedHostAdapters.DefaultOriginalFiniteTraversalChartPreparer
import struct RetainedHostAdapters.DefaultOriginalIntrinsicSphereLawIssuer
import struct RetainedHostAdapters.DefaultOriginalLinearChartIssuer
import struct RetainedHostAdapters.DefaultOriginalOffsetGraphIssuer
import struct RetainedHostAdapters.DefaultOriginalOffsetLawIssuer
import struct RetainedHostAdapters.DefaultOriginalParameterImageActionIssuer
import struct RetainedHostAdapters.DefaultOriginalParameterImageChartIssuer
import struct RetainedHostAdapters.DefaultOriginalPeriodicNativeOffsetLawPreparer
import struct RetainedHostAdapters.DefaultOriginalPeriodicNativeSurfaceLiftGraphPreparer
import struct RetainedHostAdapters.DefaultOriginalPhysicalAnalyticCoordinateIssuer
import struct RetainedHostAdapters.DefaultOriginalPlaneBasisIssuer
import struct RetainedHostAdapters.DefaultOriginalPrimitiveImageIssuer
import struct RetainedHostAdapters.DefaultOriginalRationalGraphIssuer
import struct RetainedHostAdapters.DefaultOriginalRevolutionLawIssuer
import struct RetainedHostAdapters.DefaultOriginalRuledChartIssuer
import struct RetainedHostAdapters.DefaultOriginalSourceBindingIssuer
import struct RetainedHostAdapters.DefaultOriginalSourceCoefficientImporter
import struct RetainedHostAdapters.DefaultOriginalSpatialActionIssuer
import struct RetainedHostAdapters.DefaultOriginalSpatialChartIssuer
import struct RetainedHostAdapters.DefaultOriginalTraversalActionIssuer
import struct RetainedHostAdapters.DefaultOriginalTraversalChartIssuer
import struct RetainedHostAdapters.DefaultOriginalWholeLinearLawIssuer
import protocol RetainedHostAdapters.OriginalAnalyticCoordinateIssuing
import enum RetainedHostAdapters.OriginalAnalyticCoordinateKind
import struct RetainedHostAdapters.OriginalAnalyticCoordinateLawReceipt
import protocol RetainedHostAdapters.OriginalAnalyticCoordinateReading
import struct RetainedHostAdapters.OriginalBSplineChartSelection
import protocol RetainedHostAdapters.OriginalBSplineFundamentalChartPreparing
import struct RetainedHostAdapters.OriginalBSplineFundamentalCharts
import protocol RetainedHostAdapters.OriginalBSplineSourceReading
import protocol RetainedHostAdapters.OriginalCoefficientBoundChartIssuing
import protocol RetainedHostAdapters.OriginalCompleteCurveGraphPreparing
import struct RetainedHostAdapters.OriginalCompleteCurveGraphs
import protocol RetainedHostAdapters.OriginalConeImageReading
import struct RetainedHostAdapters.OriginalCoonsBoundarySelection
import struct RetainedHostAdapters.OriginalCoonsChartSelection
import protocol RetainedHostAdapters.OriginalCoonsSourceReading
import protocol RetainedHostAdapters.OriginalCurveEndpointIssuing
import struct RetainedHostAdapters.OriginalCurveEndpointReceipt
import protocol RetainedHostAdapters.OriginalFiniteBSplineChartPreparing
import struct RetainedHostAdapters.OriginalFiniteBSplineCharts
import protocol RetainedHostAdapters.OriginalFiniteCoonsBoundaryPreparing
import protocol RetainedHostAdapters.OriginalFiniteCoonsChartPreparing
import struct RetainedHostAdapters.OriginalFiniteGuideChartFamily
import protocol RetainedHostAdapters.OriginalFiniteGuideChartPreparing
import struct RetainedHostAdapters.OriginalFiniteNativeOffsetLawFamily
import protocol RetainedHostAdapters.OriginalFiniteNativeOffsetLawPreparing
import protocol RetainedHostAdapters.OriginalFiniteNativeRollingBallGraphPreparing
import struct RetainedHostAdapters.OriginalFiniteNativeRollingBallGraphs
import protocol RetainedHostAdapters.OriginalFiniteNativeSurfaceLiftGraphPreparing
import struct RetainedHostAdapters.OriginalFiniteNativeSurfaceLiftGraphs
import protocol RetainedHostAdapters.OriginalFiniteParameterImageChartPreparing
import protocol RetainedHostAdapters.OriginalFiniteRetainedCurveChartPreparing
import struct RetainedHostAdapters.OriginalFiniteRetainedCurveCharts
import protocol RetainedHostAdapters.OriginalFiniteRetainedSurfaceChartPreparing
import struct RetainedHostAdapters.OriginalFiniteRetainedSurfaceCharts
import protocol RetainedHostAdapters.OriginalFiniteRetainedSurfaceLiftGraphPreparing
import struct RetainedHostAdapters.OriginalFiniteRetainedSurfaceLiftGraphs
import struct RetainedHostAdapters.OriginalFiniteRevolutionLawFamily
import protocol RetainedHostAdapters.OriginalFiniteRevolutionLawPreparing
import protocol RetainedHostAdapters.OriginalFiniteRollingBallGraphPreparing
import struct RetainedHostAdapters.OriginalFiniteRollingBallGraphs
import protocol RetainedHostAdapters.OriginalFiniteRuledChartPreparing
import protocol RetainedHostAdapters.OriginalFiniteSpatialChartPreparing
import protocol RetainedHostAdapters.OriginalFiniteTraversalChartPreparing
import struct RetainedHostAdapters.OriginalGuideChartReceipt
import protocol RetainedHostAdapters.OriginalGuideSourceReading
import protocol RetainedHostAdapters.OriginalImageFrameReading
import protocol RetainedHostAdapters.OriginalImplicitImageIssuing
import struct RetainedHostAdapters.OriginalImplicitImageReceipt
import protocol RetainedHostAdapters.OriginalIntrinsicSphereLawIssuing
import protocol RetainedHostAdapters.OriginalIntrinsicSphereSourceReading
import protocol RetainedHostAdapters.OriginalLiftSourceReading
import struct RetainedHostAdapters.OriginalLinearChartSelection
import protocol RetainedHostAdapters.OriginalLinearSourceReading
import protocol RetainedHostAdapters.OriginalOffsetLawIssuing
import struct RetainedHostAdapters.OriginalOffsetLawReceipt
import protocol RetainedHostAdapters.OriginalOffsetSourceReading
import struct RetainedHostAdapters.OriginalParameterImageChartSelection
import protocol RetainedHostAdapters.OriginalParameterImageSourceReading
import struct RetainedHostAdapters.OriginalParametricGraphCondition
import protocol RetainedHostAdapters.OriginalParametricGraphIssuing
import struct RetainedHostAdapters.OriginalParametricGraphReceipt
import struct RetainedHostAdapters.OriginalParametricVariableLayout
import struct RetainedHostAdapters.OriginalPeriodicNativeOffsetLawFamily
import protocol RetainedHostAdapters.OriginalPeriodicNativeOffsetLawPreparing
import protocol RetainedHostAdapters.OriginalPeriodicNativeSurfaceLiftGraphPreparing
import protocol RetainedHostAdapters.OriginalPeriodicNativeSurfaceLiftGraphQuerying
import struct RetainedHostAdapters.OriginalPeriodicNativeSurfaceLiftGraphs
import protocol RetainedHostAdapters.ExactPhysicalAngleCoefficients
import struct RetainedHostAdapters.OriginalPhysicalAngleScalarDomain
import struct RetainedHostAdapters.OriginalPhysicalAngleValue
import protocol RetainedHostAdapters.OriginalPiGenerating
import struct RetainedHostAdapters.OriginalPiScalarDomain
import struct RetainedHostAdapters.OriginalPiValue
import protocol RetainedHostAdapters.OriginalPlaneBasisIssuing
import struct RetainedHostAdapters.OriginalPlaneBasisReceipt
import protocol RetainedHostAdapters.OriginalPlaneSourceReading
import enum RetainedHostAdapters.OriginalPrimitiveImageKind
import protocol RetainedHostAdapters.OriginalPrimitiveImageReading
import struct RetainedHostAdapters.OriginalPrimitiveImageSelection
import protocol RetainedHostAdapters.OriginalRationalChartIssuing
import struct RetainedHostAdapters.OriginalRationalChartReceipt
import struct RetainedHostAdapters.OriginalRationalParameterTransport
import protocol RetainedHostAdapters.OriginalRetainedCurveSourceReading
import struct RetainedHostAdapters.OriginalRetainedSurfaceCell
import protocol RetainedHostAdapters.OriginalRetainedSurfaceLiftSourceReading
import protocol RetainedHostAdapters.OriginalRetainedSurfaceSourceReading
import protocol RetainedHostAdapters.OriginalRevolutionLawIssuing
import struct RetainedHostAdapters.OriginalRevolutionLawReceipt
import protocol RetainedHostAdapters.OriginalRevolutionSourceReading
import struct RetainedHostAdapters.OriginalRollingBallChildGraphEvidence
import protocol RetainedHostAdapters.OriginalRollingBallChildSourceReading
import struct RetainedHostAdapters.OriginalRollingBallGraphEvidence
import protocol RetainedHostAdapters.OriginalRollingBallSourceReading
import struct RetainedHostAdapters.OriginalRuledChartSelection
import protocol RetainedHostAdapters.OriginalRuledSourceReading
import class RetainedHostAdapters.OriginalSourceAffineAction
import protocol RetainedHostAdapters.OriginalSourceAffineActionIssuing
import struct RetainedHostAdapters.OriginalSourceAffineActionReceipt
import enum RetainedHostAdapters.OriginalSourceAngularMap
import struct RetainedHostAdapters.OriginalSourceBinding
import protocol RetainedHostAdapters.OriginalSourceBindingIssuing
import struct RetainedHostAdapters.OriginalSourceChart
import protocol RetainedHostAdapters.OriginalSourceCoefficientImporting
import struct RetainedHostAdapters.OriginalSourceCollapsedFiberReceipt
import struct RetainedHostAdapters.OriginalSourceCoordinateAxis
import enum RetainedHostAdapters.OriginalSourceCoordinateFunction
import enum RetainedHostAdapters.OriginalSourceIssuanceFailure
import struct RetainedHostAdapters.OriginalSourceIssuanceLimits
import struct RetainedHostAdapters.OriginalSourceParameterInterval
import enum RetainedHostAdapters.OriginalSourceParameterMeaning
import protocol RetainedHostAdapters.OriginalSourcePeriodIssuing
import struct RetainedHostAdapters.OriginalSourcePeriodReceipt
import struct RetainedHostAdapters.OriginalSourcePoleReceipt
import struct RetainedHostAdapters.OriginalSourceSnapshot
import protocol RetainedHostAdapters.OriginalSourceSnapshotting
import struct RetainedHostAdapters.OriginalSpatialChartSelection
import protocol RetainedHostAdapters.OriginalSpatialSourceReading
import struct RetainedHostAdapters.OriginalSurfaceLiftGraphEvidence
import protocol RetainedHostAdapters.OriginalSurfaceLiftSourceReading
import struct RetainedHostAdapters.OriginalTransportedSourceCoefficientImporter
import struct RetainedHostAdapters.OriginalTraversalChartSelection
import protocol RetainedHostAdapters.OriginalTraversalSourceReading
import protocol RetainedHostAdapters.OriginalWholeLinearLawIssuing
import struct RetainedHostAdapters.OriginalWholeLinearLawReceipt
import protocol RetainedHostAdapters.OriginalPeriodicRetainedSurfaceLiftGraphPreparing
import protocol RetainedHostAdapters.OriginalLiftGraphSourceReading
import protocol RetainedHostAdapters.OriginalRetainedPcurveLiftSourceReading
import protocol RetainedHostAdapters.OriginalRetainedAtlasLiftSourceReading
import protocol RetainedHostAdapters.OriginalFiniteRetainedAtlasLiftGraphPreparing
import protocol RetainedHostAdapters.OriginalNativePcurveRetainedAtlasLiftSourceReading
import protocol RetainedHostAdapters.OriginalFiniteNativePcurveRetainedAtlasLiftGraphPreparing
import struct RetainedHostAdapters.OriginalBSplineSurfaceSnapshotProvider
import struct RetainedHostAdapters.OriginalNativeSurfaceFamilySnapshotProvider
import struct RetainedHostAdapters.OriginalBSplinePcurveSnapshotProvider
import struct RetainedHostAdapters.OriginalNativeSurfaceLiftSnapshot
import struct RetainedHostAdapters.OriginalNativeSurfaceLiftSnapshotProvider
import struct RetainedHostAdapters.OriginalAffinePcurveSnapshot
import struct RetainedHostAdapters.OriginalAffinePcurveSnapshotProvider
import struct RetainedHostAdapters.OriginalAffineSurfaceLiftSnapshot
import struct RetainedHostAdapters.OriginalAffineSurfaceLiftSnapshotProvider
import enum RetainedHostAdapters.ExactParameterBound
import protocol RetainedHostAdapters.ExactParameterDomainConstructing
import protocol RetainedHostAdapters.ExactParameterDomainQuerying
import struct RetainedHostAdapters.ExactParameterInterval
import struct RetainedHostAdapters.ExactParameterSet
import protocol RetainedHostAdapters.ExactParameterDomainFieldQuerying
import struct RetainedHostAdapters.ExactParameterDomain
import struct RetainedHostAdapters.ExactParameterProduct
import enum RetainedHostAdapters.ExactParameterDomainFailure
import enum RetainedHostAdapters.OriginalDomainIdentityFailure
import struct RetainedHostAdapters.OriginalDomainIdentityLimits
import protocol RetainedHostAdapters.OriginalNativeSurfaceLiftDomainIssuing
import struct RetainedHostAdapters.OriginalDomainBoundParametricGraph
import struct RetainedHostAdapters.OriginalAffineChildDomainOccurrence
import protocol RetainedHostAdapters.OriginalPeriodicGuardedChartFamilyQuerying
import struct RetainedHostAdapters.DefaultOriginalIssuedDomainBinder
import protocol RetainedHostAdapters.OriginalNativeOffsetDomainIssuing
import protocol RetainedHostAdapters.OriginalRetainedCurveDomainIssuing
import struct RetainedHostAdapters.DefaultOriginalAnalyticDomainIssuer
import struct RetainedHostAdapters.OriginalRevolutionChartOccurrence
import protocol RetainedHostAdapters.OriginalNativeRollingBallDomainIssuing
import struct RetainedHostAdapters.OriginalAffineChildDomainCover
import protocol RetainedHostAdapters.OriginalRetainedSurfaceDomainIssuing
import protocol RetainedHostAdapters.OriginalParametricGraphDomainBinding
import struct RetainedHostAdapters.OriginalBSplineChartOccurrence
import struct RetainedHostAdapters.OriginalPeriodicNativeOffsetChartOccurrence
import struct RetainedHostAdapters.OriginalDomainCover
import struct RetainedHostAdapters.DefaultOriginalParameterImageDomainIssuer
import struct RetainedHostAdapters.OriginalPeriodicNativeSurfaceLiftChartOccurrence
import protocol RetainedHostAdapters.OriginalDomainCoverQuerying
import struct RetainedHostAdapters.OriginalPeriodicNativeSurfaceLiftDomainCover
import struct RetainedHostAdapters.DefaultOriginalTraversalDomainIssuer
import struct RetainedHostAdapters.OriginalNativeRollingBallDomainCover
import struct RetainedHostAdapters.OriginalPrimitiveDomainCover
import struct RetainedHostAdapters.OriginalPeriodicNativeOffsetDomainCover
import struct RetainedHostAdapters.DefaultOriginalLinearDomainIssuer
import protocol RetainedHostAdapters.OriginalPeriodicNativeSurfaceLiftDomainIssuing
import protocol RetainedHostAdapters.OriginalRollingBallGraphDomainIssuing
import protocol RetainedHostAdapters.OriginalGuardedChartFamilyQuerying
import struct RetainedHostAdapters.OriginalPeriodicNativeSurfaceLiftDomainSpace
import struct RetainedHostAdapters.OriginalPeriodicNativeOffsetDomainSpace
import struct RetainedHostAdapters.OriginalRetainedSurfaceDomainCover
import protocol RetainedHostAdapters.OriginalBSplineDomainIssuing
import struct RetainedHostAdapters.OriginalGuideDomainCover
import protocol RetainedHostAdapters.OriginalIssuedDomainBinding
import protocol RetainedHostAdapters.OriginalPeriodicNativeSurfaceLiftDomainQuerying
import struct RetainedHostAdapters.OriginalBSplineDomainSpace
import struct RetainedHostAdapters.OriginalRetainedSurfaceLiftDomainCover
import protocol RetainedHostAdapters.OriginalChartFamilyQuerying
import struct RetainedHostAdapters.OriginalIssuedDomainCover
import struct RetainedHostAdapters.OriginalBSplineDomainCover
import struct RetainedHostAdapters.OriginalAnalyticDomainCover
import struct RetainedHostAdapters.DefaultOriginalBSplineDomainIssuer
import struct RetainedHostAdapters.OriginalRetainedSurfaceChartOccurrence
import struct RetainedHostAdapters.DefaultOriginalSpatialChildDomainIssuer
import struct RetainedHostAdapters.DefaultOriginalDomainCoverIssuer
import struct RetainedHostAdapters.OriginalGuideChartOccurrence
import struct RetainedHostAdapters.DefaultOriginalPlaneDomainIssuer
import struct RetainedHostAdapters.OriginalRetainedCurveDomainCover
import struct RetainedHostAdapters.OriginalRetainedCurveChartOccurrence
import struct RetainedHostAdapters.OriginalRollingBallGraphDomainCover
import protocol RetainedHostAdapters.OriginalDomainCoverIssuing
import struct RetainedHostAdapters.DefaultOriginalPeriodicNativeOffsetDomainIssuer
import struct RetainedHostAdapters.DefaultOriginalGuideDomainIssuer
import struct RetainedHostAdapters.DefaultOriginalDomainBoundBSplineChartIssuer
import protocol RetainedHostAdapters.OriginalRetainedSurfaceLiftDomainIssuing
import struct RetainedHostAdapters.DefaultOriginalParametricGraphDomainBinder
import struct RetainedHostAdapters.DefaultOriginalPeriodicNativeSurfaceLiftDomainIssuer
import protocol RetainedHostAdapters.OriginalAffineChildDomainIssuing
import struct RetainedHostAdapters.OriginalIntrinsicSphereDomainCover
import struct RetainedHostAdapters.OriginalDomainBoundRationalChart
import struct RetainedHostAdapters.DefaultOriginalRetainedCurveDomainIssuer
import protocol RetainedHostAdapters.OriginalPlaneDomainIssuing
import struct RetainedHostAdapters.DefaultOriginalRevolutionDomainIssuer
import struct RetainedHostAdapters.OriginalNativeOffsetDomainCover
import struct RetainedHostAdapters.OriginalDomainChart
import struct RetainedHostAdapters.DefaultOriginalIntrinsicSphereDomainIssuer
import struct RetainedHostAdapters.OriginalNativeSurfaceLiftDomainCover
import protocol RetainedHostAdapters.OriginalAnalyticDomainIssuing
import struct RetainedHostAdapters.DefaultOriginalNativeOffsetDomainIssuer
import protocol RetainedHostAdapters.OriginalGuideDomainIssuing
import struct RetainedHostAdapters.DefaultOriginalNativeRollingBallDomainIssuer
import struct RetainedHostAdapters.OriginalRevolutionDomainCover
import protocol RetainedHostAdapters.OriginalFiniteChartFamilyQuerying
import protocol RetainedHostAdapters.OriginalLinearDomainIssuing
import struct RetainedHostAdapters.DefaultOriginalNativeSurfaceLiftDomainIssuer
import struct RetainedHostAdapters.DefaultOriginalRetainedSurfaceDomainIssuer
import struct RetainedHostAdapters.DefaultOriginalRollingBallGraphDomainIssuer
import protocol RetainedHostAdapters.OriginalPeriodicNativeOffsetDomainIssuing
import struct RetainedHostAdapters.DefaultOriginalRetainedSurfaceLiftDomainIssuer
import protocol RetainedHostAdapters.OriginalRevolutionDomainIssuing
import struct RetainedHostAdapters.OriginalNativeOffsetChartOccurrence
import protocol RetainedHostAdapters.OriginalDomainBoundRationalChartIssuing
import struct RetainedHostAdapters.OriginalIssuedDomainChart
import protocol RetainedHostAdapters.OriginalIntrinsicSphereDomainIssuing
import protocol RetainedHostAdapters.OriginalParameterIdentityRelationQuerying
import protocol RetainedHostAdapters.OriginalAffineChildParameterIdentityIssuing
import struct RetainedHostAdapters.DefaultOriginalAffinePairedParameterIdentityIssuer
import protocol RetainedHostAdapters.OriginalIntrinsicParameterIdentityIssuing
import protocol RetainedHostAdapters.OriginalRevolutionParameterIdentityIssuing
import enum RetainedHostAdapters.OriginalParameterIdentityConstraints
import struct RetainedHostAdapters.DefaultOriginalAffineChildParameterIdentityIssuer
import protocol RetainedHostAdapters.OriginalParameterIdentityIssuing
import struct RetainedHostAdapters.OriginalSourceBoundaryDeclaration
import struct RetainedHostAdapters.OriginalParameterIdentityRelation
import protocol RetainedHostAdapters.OriginalAnalyticParameterIdentityIssuing
import protocol RetainedHostAdapters.OriginalAffinePairedParameterIdentityIssuing
import enum RetainedHostAdapters.OriginalParameterIdentityKind
import enum RetainedHostAdapters.OriginalParameterIdentityDecision
import protocol RetainedHostAdapters.OriginalPeriodicParameterIdentityIssuing
import protocol RetainedHostAdapters.OriginalParameterIdentityQuerying
import struct RetainedHostAdapters.DefaultOriginalParameterIdentityIssuer
import protocol RetainedHostAdapters.OriginalRationalParameterIdentityIssuing
import struct RetainedHostAdapters.OriginalParameterIdentity
import struct RetainedHostAdapters.OriginalParameterFrame
import struct RetainedHostAdapters.OriginalParameterAffineCoordinates
import struct RetainedHostAdapters.OriginalParameterCycle
import typealias RetainedHostAdapters.OriginalCoordinateSemantics
import protocol RetainedHostAdapters.OriginalParameterFieldQueryTransporting
import struct RetainedHostAdapters.OriginalParameterPeriodicLift
import struct RetainedHostAdapters.OriginalParameterSelection
import protocol RetainedHostAdapters.OriginalPlaneCoordinateQuerying
import struct RetainedHostAdapters.DefaultOriginalParameterTransporter
import protocol RetainedHostAdapters.OriginalParameterTransporting
import struct RetainedHostAdapters.OriginalParameterTransport
import protocol RetainedHostAdapters.OriginalParameterAffineCoordinateQuerying
import protocol RetainedHostAdapters.OriginalRetainedLiftHostSnapshotting
import struct RetainedHostAdapters.OriginalRetainedAtlasSurfaceLiftSnapshot
import struct RetainedHostAdapters.OriginalRetainedAtlasSurfaceLiftSnapshotProvider
import struct RetainedHostAdapters.OriginalBoundaryCorrectionSnapshot
import struct RetainedHostAdapters.OriginalBoundaryCorrectionSnapshotProvider
import struct RetainedHostAdapters.OriginalNativePcurveRetainedAtlasLiftSnapshot
import struct RetainedHostAdapters.OriginalNativePcurveRetainedAtlasLiftSnapshotProvider
import struct RetainedHostAdapters.OriginalCoonsAtlasSnapshot
import struct RetainedHostAdapters.OriginalCoonsAtlasSnapshotProvider
import struct RetainedHostAdapters.OriginalPlaneDerivativeSurfaceSnapshot
import struct RetainedHostAdapters.OriginalPlaneDerivativeSurfaceSnapshotProvider
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
import CADCore


@testable import CallerAdapters
import CADCore
#if ORIGINAL_SOURCE_GEOMETRY_ADAPTER_VERIFICATION
import struct CADGeometry.RuledSurface3D
import L0
import SourceIssuer
#endif


@testable import DraftZeroRuledPort
@testable import GuideSeamPort
import struct GuideSeamPort.OriginalIssuedGraphPreparation
import struct GuideSeamPort.OriginalIssuedGraphFamily
import struct GuideSeamPort.DefaultOriginalIssuedGraphCompiler
import struct GuideSeamPort.DefaultOriginalRationalGraphFamilyPreparer
import protocol GuideSeamPort.OriginalIssuedGraphRelationOwning
import struct GuideSeamPort.OriginalIssuedGraphRelationPair
import enum DraftZeroRuledPort.GeometryExactScalarFailure
import struct CallerAdapters.OriginalNativeCurveFamilySnapshotProvider
import struct DraftZeroRuledPort.OriginalLinearCurveSnapshot
import struct DraftZeroRuledPort.OriginalLinearCurveSnapshotProvider
import struct DraftZeroRuledPort.NativeExactPublicAdmission
import enum GuideSeamPort.NativeExactRelationFailure
import enum DraftZeroRuledPort.NativeExactPublicLimits
import enum RetainedHostAdapters.OriginalDomainAccess
import struct CADGeometry.OriginalTraversalEndpointBinding

@testable import AngularSourcePhase
import enum DraftZeroRuledPort.NativeExactGeometricRelationFailure
import struct AngularSourcePhase.OriginalAnalyticCosineZeroRoot
import protocol AngularSourcePhase.OriginalAnalyticCosineZeroIssuing
import struct AngularSourcePhase.OriginalAnalyticCosineZeroReceipt
import struct AngularSourcePhase.DefaultOriginalAnalyticCosineZeroIssuer
import struct AngularSourcePhase.OriginalAnalyticCoordinateSnapshot
import struct AngularSourcePhase.OriginalAnalyticCoordinateCurveSnapshotProvider
import struct AngularSourcePhase.OriginalPlaneSnapshot
import struct AngularSourcePhase.OriginalPlaneSnapshotProvider

@testable import CertifiedApexSourcePhase

@testable import ImplicitSourcePhase

@testable import ImplicitHostPlaneSourcePhase
import CADCore

/// Certified numerical representatives of retained original rational graph tuples.
struct OriginalRationalGraphPointPublisher<S: Sendable, E: Sendable, C: Sendable,
    T: Sendable, F: Sendable, D: Sendable> {
    typealias Base = OriginalExactScalarDomain
    private typealias Algebraic = ExactAlgebraicScalarDomain<Base>
    typealias Geometry = OriginalIssuedGeometricRelations<S,E,C,T,F,D>

    func publish<A: ExactScalarAdmission & ~Copyable>(_ geometry: OriginalIssuedGeometricRelations<S,E,C,T,F,D>,
        field: OriginalExactScalarDomain, options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance, limits: OriginalDomainIdentityLimits,
        maximumDepth: Int, using a: inout A
    ) throws -> (points: [CurveSurfaceIntersection], receipt: OriginalIssuedNumericalCurveSurfacePoints) {
        try publish(geometry, field: field, options: options, tolerance: tolerance, limits: limits,
            maximumDepth: maximumDepth, curveEvaluator: OriginalIdentityRationalGraphCurvePointEvaluator<S,E>(), using: &a)
    }

    func publish<Q: OriginalRationalGraphCurvePointEvaluating, A: ExactScalarAdmission & ~Copyable>(
        _ geometry: Geometry, field: Base, options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance, limits: OriginalDomainIdentityLimits, maximumDepth: Int,
        curveEvaluator: Q, using a: inout A
    ) throws -> (points: [CurveSurfaceIntersection], receipt: OriginalIssuedNumericalCurveSurfacePoints)
        where Q.Source == S, Q.Evidence == E {
        try a.checkpoint(); try geometry.original.admitProof(limits: limits, using: &a)
        guard geometry.kind == .curveSurface else { throw ExactGeometricRelationFailure.invalidSourceBinding }
        for graph in geometry.original.first.graphs { try curveEvaluator.admit(graph.original.graph, limits: limits, using: &a) }
        for graph in geometry.original.second.graphs { try OriginalRationalGraphPointAccess.requireIdentity(graph.original.graph, arity: 2, using: &a) }
        let count = geometry.exactPoints.count
        guard count <= options.maximumCandidateCount else { throw ExactScalarFailure.resourceLimit(.work) }
        let total = count.multipliedReportingOverflow(by: 6)
        guard !total.overflow else { throw ExactScalarFailure.countOverflow }
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: total.partialValue, of: Algebraic.Value.self))
        var exact: [Algebraic.Value] = []; exact.reserveCapacity(total.partialValue)
        for point in geometry.exactPoints {
            try a.consumeWork(1)
            guard point.firstParameters.count == 1, point.secondParameters.count == 2 else {
                throw ExactGeometricRelationFailure.invalidSourceBinding
            }
            let pair = geometry.original.pairs[point.pairOrdinal]
            try curveEvaluator.validate(point, graph: geometry.original.first.graphs[pair.firstGraphIndex].original.graph,
                limits: limits, using: &a)
            exact.append(point.firstParameters[0]); exact.append(contentsOf: point.secondParameters)
            exact.append(point.position.x); exact.append(point.position.y); exact.append(point.position.z)
        }
        let transferred = try DefaultExactOriginalScalarTransporter().transfer(exact, into: field, using: &a)
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: Int.self))
        var ordinals: [Int] = []; ordinals.reserveCapacity(count)
        for index in 0..<count { try a.consumeWork(1); ordinals.append(index) }
        func order(_ left: Int, _ right: Int, _ a: inout A) throws -> ExactOrder {
            for axis in 0..<3 {
                let answer = try transferred.field.compare(transferred.values[6*left+axis],
                    transferred.values[6*right+axis], using: &a)
                if answer != .equal { return answer }
            }
            return .equal
        }
        // One admitted index buffer preserves every incident and avoids sort scratch.
        func sift(_ start: Int, _ end: Int, _ indices: inout [Int], _ a: inout A) throws {
            var parent = start
            while parent < end/2 {
                try a.consumeWork(1)
                var child = parent*2+1
                if child+1 < end, try order(indices[child], indices[child+1], &a) == .less { child += 1 }
                if try order(indices[parent], indices[child], &a) != .less { return }
                indices.swapAt(parent, child); parent = child
            }
        }
        if count > 1 {
            for start in stride(from: count/2-1, through: 0, by: -1) { try sift(start, count, &ordinals, &a) }
            for end in stride(from: count-1, through: 1, by: -1) {
                ordinals.swapAt(0, end); try sift(0, end, &ordinals, &a)
            }
        }
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: Range<Int>.self))
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: CurveSurfaceIntersection.self))
        var ranges: [Range<Int>] = []; ranges.reserveCapacity(count)
        var points: [CurveSurfaceIntersection] = []; points.reserveCapacity(count)
        var start = 0
        while start < count {
            var end = start+1
            while end < count, try order(ordinals[start], ordinals[end], &a) == .equal { end += 1 }
            let range = start..<end
            let kind = try classify(geometry, ordinals: ordinals, range: range, tolerance: tolerance, curveEvaluator: curveEvaluator, using: &a)
            points.append(try representative(geometry, transfer: transferred, ordinals: ordinals, range: range,
                kind: kind, options: options, tolerance: tolerance, limits: limits, maximumDepth: maximumDepth, curveEvaluator: curveEvaluator, using: &a))
            ranges.append(range); start = end
        }
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: OriginalIssuedNumericalCurveSurfacePoints.self))
        let receipt = OriginalIssuedNumericalCurveSurfacePoints(geometry: geometry, coordinates: transferred,
            incidenceOrdinals: ordinals, incidenceRanges: ranges)
        try a.checkpoint(); return (points, receipt)
    }

    private func classify<Q: OriginalRationalGraphCurvePointEvaluating, A: ExactScalarAdmission & ~Copyable>(_ geometry: Geometry,
        ordinals: [Int], range: Range<Int>, tolerance: ModelingTolerance, curveEvaluator: Q, using a: inout A
    ) throws -> CurveSurfaceIntersectionKind where Q.Source == S, Q.Evidence == E {
        var answer: CurveSurfaceIntersectionKind?
        for ordinal in range {
            let point = geometry.exactPoints[ordinals[ordinal]], f = point.local.witness.field
            let pair = geometry.original.pairs[point.pairOrdinal]
            let first = geometry.original.first.graphs[pair.firstGraphIndex].original.graph
            let second = geometry.original.second.graphs[pair.secondGraphIndex].original.graph
            let curve = try curveEvaluator.tangent(first, at: point.firstParameters, field: f, using: &a)
            let u = try OriginalRationalGraphPointAccess.derivative(second, at: point.secondParameters, axis: 0, field: f, using: &a)
            let v = try OriginalRationalGraphPointAccess.derivative(second, at: point.secondParameters, axis: 1, field: f, using: &a)
            var tangentSquared = try f.integer(0, using: &a), normalSquared = tangentSquared, dot = tangentSquared
            for axis in 0..<3 {
                let i = (axis+1)%3, j = (axis+2)%3
                let normal = try f.subtracting(f.multiplying(u[i], v[j], using: &a), f.multiplying(u[j], v[i], using: &a), using: &a)
                tangentSquared = try f.adding(tangentSquared, f.multiplying(curve[axis], curve[axis], using: &a), using: &a)
                normalSquared = try f.adding(normalSquared, f.multiplying(normal, normal, using: &a), using: &a)
                dot = try f.adding(dot, f.multiplying(curve[axis], normal, using: &a), using: &a)
            }
            let kind: CurveSurfaceIntersectionKind
            if try f.sign(of: tangentSquared, using: &a) == .zero || f.sign(of: normalSquared, using: &a) == .zero { kind = .mixed }
            else {
                let angle = try f.binary64(exactly: tolerance.angle, using: &a)
                let threshold = try f.multiplying(f.multiplying(tangentSquared, normalSquared, using: &a),
                    f.multiplying(angle, angle, using: &a), using: &a)
                kind = try f.compare(f.multiplying(dot, dot, using: &a), threshold, using: &a) == .greater ? .transverse : .tangent
            }
            // FIXME(INCOMPLETE_IMPLEMENTATION): Disagreeing incident germs need
            // a scoped multi-classification receipt before ordinary success.
            guard answer == nil || answer == kind else { throw OriginalSourceIssuanceFailure.unsupportedRepresentation }
            answer = kind
        }
        guard let answer else { throw ExactGeometricRelationFailure.invalidCoverage }
        return answer
    }

    private func representative<Q: OriginalRationalGraphCurvePointEvaluating, A: ExactScalarAdmission & ~Copyable>(_ geometry: Geometry,
        transfer: ExactOriginalScalarTransferReceipt, ordinals: [Int], range: Range<Int>, kind: CurveSurfaceIntersectionKind,
        options: CurveSurfaceIntersectionOptions, tolerance: ModelingTolerance, limits: OriginalDomainIdentityLimits,
        maximumDepth: Int, curveEvaluator: Q, using a: inout A) throws -> CurveSurfaceIntersection
        where Q.Source == S, Q.Evidence == E {
        let f = transfer.field, offset = ordinals[range.lowerBound]*6
        let maximum = try ExactScalarDepth(value: maximumDepth, coefficient: maximumDepth)
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 6, of: OriginalSingularFieldValueIsolation.self))
        var isolations: [OriginalSingularFieldValueIsolation] = []; isolations.reserveCapacity(6)
        var inherited = ExactScalarDepth.zero
        for axis in 0..<6 {
            let value = transfer.values[offset+axis]
            let seed = try ExactScalarNumericAccess.withAdmission(&a, original: value.depth, inherited: value.depth, maximum: maximum) { usage in
                try OriginalSingularFieldValueIsolation(original: value.original, inheritedDepth: value.depth.value,
                    maximumDepth: maximumDepth, usage: &usage)
            }
            inherited = try .init(value: max(inherited.value, seed.depth.value), coefficient: max(inherited.coefficient, seed.depth.coefficient))
            isolations.append(seed.value)
        }
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 6, of: Double.self))
        var numbers: [Double] = []; numbers.reserveCapacity(6)
        let epsilon = try f.binary64(exactly: tolerance.distance, using: &a)
        let squared = try f.multiplying(epsilon, epsilon, using: &a)
        var width = ExactRationalCoefficient.one
        for iteration in 0..<options.maximumIterations {
            numbers.removeAll(keepingCapacity: true)
            var narrow = true
            for axis in 0..<6 {
                let isolation = isolations[axis]
                let depth = try ExactScalarDepth(value: isolation.sourceDepth, coefficient: transfer.values[offset+axis].depth.coefficient)
                let refined = try ExactScalarNumericAccess.withAdmission(&a, original: depth, inherited: depth, maximum: maximum) { usage in
                    let next = try isolation.refined(maximumWidth: width, maximumDepth: maximumDepth, usage: &usage)
                    return (next, try next.enclosure(usage: &usage))
                }
                inherited = try .init(value: max(inherited.value, refined.depth.value), coefficient: max(inherited.coefficient, refined.depth.coefficient))
                isolations[axis] = refined.value.0
                let bounds = refined.value.1
                if bounds.upper-bounds.lower > tolerance.distance { narrow = false }
                var number = bounds.lower*0.5+bounds.upper*0.5
                let request = axis == 0 ? options.curveRange : axis == 1 ? options.surfaceURange : axis == 2 ? options.surfaceVRange : nil
                if let request { number = max(request.lower, min(request.upper, number)) }
                guard number.isFinite, number >= bounds.lower, number <= bounds.upper else { throw ExactGeometricRelationFailure.invalidCoverage }
                numbers.append(number)
            }
            if narrow {
                try a.retainStorage(bytes: exactScalarPayloadBytes(count: 6, of: OriginalExactScalar.self))
                var numeric: [OriginalExactScalar] = []; numeric.reserveCapacity(6)
                for number in numbers { numeric.append(try f.binary64(exactly: number, using: &a)) }
                var parametersValid = true
                for axis in 0..<3 {
                    let delta = try f.subtracting(transfer.values[offset+axis], numeric[axis], using: &a)
                    if try f.compare(f.multiplying(delta, delta, using: &a), squared, using: &a) == .greater { parametersValid = false }
                }
                try a.retainStorage(bytes: exactScalarPayloadBytes(count: 6, of: OriginalExactScalar.self))
                let published = [numeric[3],numeric[4],numeric[5]]
                let original = [transfer.values[offset+3],transfer.values[offset+4],transfer.values[offset+5]]
                for index in range {
                    let point = geometry.exactPoints[ordinals[index]], pair = geometry.original.pairs[point.pairOrdinal]
                    let first = geometry.original.first.graphs[pair.firstGraphIndex].original.graph
                    let second = geometry.original.second.graphs[pair.secondGraphIndex].original.graph
                    if let curve = try curveEvaluator.position(first, numbers: numbers, field: f, limits: limits, using: &a),
                        let surface = try OriginalRationalGraphPointAccess.position(second, numbers: numbers, offset: 1, field: f, limits: limits, using: &a),
                        parametersValid, try within(original, published, squared: squared, field: f, using: &a),
                        try within(curve, surface, squared: squared, field: f, using: &a),
                        try within(curve, published, squared: squared, field: f, using: &a),
                        try within(surface, published, squared: squared, field: f, using: &a) {
                        return try .init(point: .init(x: numbers[3], y: numbers[4], z: numbers[5]), curveParameter: numbers[0],
                            surfaceU: numbers[1], surfaceV: numbers[2], kind: kind, residual: tolerance.distance, iterations: iteration)
                    }
                }
            }
            width = try ExactScalarNumericAccess.withAdmission(&a, inherited: inherited, maximum: maximum) { usage in
                try width.divided(by: .natural(2, usage: &usage), usage: &usage)
            }.value
        }
        throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
            message: "Original rational graph publication exhausted the caller's refinement iterations.")
    }

    private func within<A: ExactScalarAdmission & ~Copyable>(_ first: [OriginalExactScalar], _ second: [OriginalExactScalar],
        squared: OriginalExactScalar, field: Base, using a: inout A) throws -> Bool {
        var total = try field.integer(0, using: &a)
        for axis in 0..<3 {
            let delta = try field.subtracting(first[axis], second[axis], using: &a)
            total = try field.adding(total, field.multiplying(delta, delta, using: &a), using: &a)
        }
        return try field.compare(total, squared, using: &a) != .greater
    }
}
