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
import CADCore
#if !hasFeature(Embedded)
import Foundation
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#else
#error("CADGeometry numeric algorithms require the target C math module.")
#endif

struct CurveSurfaceOverlapResolver {
    private struct Candidate {
        let range: ScalarInterval
        let deviation: Double
        var isoparametric: OverlapIsoparametricCorrespondence? = nil
        var graph: OverlapRegularGraphCorrespondence? = nil
    }

    func resolve(curve: Curve3D, surface: Surface3D, options: CurveSurfaceIntersectionOptions,
                 tolerance: ModelingTolerance, intersector: DefaultCurveSurfaceIntersector) throws -> CurveSurfaceIntersectionResult {
        if let exact = try NativeExactPublicCurveSurfaceProducer().resolve(curve: curve, surface: surface,
            options: options, tolerance: tolerance, retainingRelations: true) { return exact }
        if let native = try NativeCurveSurfacePointProducer().resolve(curve: curve, surface: surface,
            options: options, tolerance: tolerance, retainingRelations: true) { return native }
        if let original = try OriginalPolynomialCurveSurfacePointProducer().resolve(curve: curve, surface: surface,
            options: options, tolerance: tolerance) { return original }
        if let affine = try OriginalAffineCurveSurfacePointProducer().resolve(curve: curve, surface: surface,
            options: options, tolerance: tolerance) { return affine }
        if let coons = try OriginalCoonsCurveSurfacePointProducer().resolve(curve: curve, surface: surface,
            options: options, tolerance: tolerance) { return coons }
        try options.validate(tolerance: tolerance)
        try curve.validate(tolerance: tolerance)
        try surface.validate(tolerance: tolerance)
        try CurrentTaskCancellationChecker().checkCancellation()
        let range = try DefaultCurveSurfaceSearchRangeResolver().curveRange(curve: curve, surface: surface,
                                                                          requestedRange: options.curveRange, tolerance: tolerance)
        guard range.width.isFinite, range.width > 0, try curve.parameterDomain.containsSpan(from: range.lower, to: range.upper, tolerance: tolerance) else {
            throw failure(.invalidInput, "Continuous intersection queries require a positive interval in the curve domain.", tolerance)
        }
        let proof = try proofSupport(surface, tolerance: tolerance)
        let support = proof.surface
        var rawOptions = options
        rawOptions.curveRange = range
        if !proof.preservesOriginalParameters {
            rawOptions.surfaceURange = nil
            rawOptions.surfaceVRange = nil
        }
        var points: [CurveSurfaceIntersection] = []
        var candidates: [Candidate] = []
        var graphBudget = OverlapProofBudget(options: options, tolerance: tolerance)

        if case .bSpline(let spline) = curve, case .bSpline(let target) = surface,
           let certificate = try OverlapIsoparametricMembershipCertifier().certificate(
               curve: spline, surface: target, range: range, options: options, tolerance: tolerance, budget: &graphBudget) {
            candidates.append(Candidate(range: range, deviation: certificate.deviation,
                isoparametric: certificate.correspondence))
        } else if case .bSpline(let spline) = curve, case .bSpline(let target) = surface,
                  !spline.isPeriodic, !target.isUPeriodic, !target.isVPeriodic,
                  ExactAffineBSplineSurfacePatch(target) == nil {
            let result = try OverlapRegularGraphCertifier().resolve(curve: spline, surface: target,
                range: range, options: options, tolerance: tolerance, budget: &graphBudget)
            for graph in result.graphs {
                candidates.append(Candidate(range: graph.range, deviation: graph.maximumDeviation, graph: graph))
            }
            for excluded in result.excluded {
                var discreteOptions = rawOptions
                discreteOptions.curveRange = excluded
                points.append(contentsOf: try intersector.intersections(curve: curve, surface: support,
                    options: discreteOptions, tolerance: tolerance))
            }
        } else if case .bSpline(let spline) = curve {
            let spans = try BSplineCurveBezierDecomposer().curvePatches(curve: spline, intersecting: range, tolerance: tolerance)
            guard spans.count <= options.maximumSubdivisionCells else {
                throw failure(.resourceLimitExceeded, "Overlap source spans exceed the cell budget.", tolerance)
            }
            for span in spans {
                try CurrentTaskCancellationChecker().checkCancellation()
                let lower = max(span.lower, range.lower), upper = min(span.upper, range.upper)
                guard upper > lower else { continue }
                let interval = try ScalarInterval(lower: lower, upper: upper)
                let degree = span.controlPoints.count - 1
                let piece = BSplineCurve3D(degree: degree,
                    knots: Array(repeating: span.lower, count: degree + 1) + Array(repeating: span.upper, count: degree + 1),
                    controlPoints: span.controlPoints, weights: span.weights)
                var pieceOptions = rawOptions
                pieceOptions.curveRange = interval
                do {
                    points.append(contentsOf: try intersector.intersections(curve: .bSpline(piece), surface: support,
                                                                          options: pieceOptions, tolerance: tolerance))
                } catch let error as KernelError where error.code == .nonDiscreteIntersection {
                    // FIXME(INCOMPLETE_IMPLEMENTATION): Non-isoparametric free-surface
                    // coincidence without retained hosting provenance has no proof here.
                    // intersectionResult may succeed only after its complete correspondence
                    // and whole-span membership certificate are implemented.
                    if case .unsupported = CanonicalAnalyticSurface(support) {
                        throw failure(.unsupportedCapability, "Rational overlap on this free surface has no membership certificate.", tolerance)
                    }
                    let bound = try OverlapSpanMembershipCertifier(maximumDegree: options.maximumPolynomialDegree, tolerance: tolerance)
                        .deviation(of: span, on: CanonicalAnalyticSurface(support))
                    guard bound <= tolerance.distance else {
                        throw failure(.intersectionFailure, "A non-discrete rational span has no certified overlap distance bound at this tolerance.", tolerance)
                    }
                    candidates.append(Candidate(range: interval, deviation: bound))
                }
                try checkCount(points.count + candidates.count, options: options, tolerance: tolerance)
            }
        } else {
            do {
                if case .periodic(let period) = curve.parameterDomain {
                    var fundamentalOptions = rawOptions
                    fundamentalOptions.curveRange = try ScalarInterval(lower: 0, upper: period)
                    let fundamental = try intersector.intersections(curve: curve, surface: support,
                                                                   options: fundamentalOptions, tolerance: tolerance)
                    for event in fundamental {
                        let lowerCycle = ceil((range.lower - event.curveParameter) / period)
                        let upperCycle = floor((range.upper - event.curveParameter) / period)
                        guard lowerCycle.isFinite, upperCycle.isFinite,
                              abs(lowerCycle) <= 9_007_199_254_740_991, abs(upperCycle) <= 9_007_199_254_740_991,
                              upperCycle - lowerCycle < Double(options.maximumCandidateCount) else {
                            throw failure(.resourceLimitExceeded, "Periodic overlap boundary events exceed the finite cycle budget.", tolerance)
                        }
                        var cycle = lowerCycle
                        while cycle <= upperCycle {
                            try CurrentTaskCancellationChecker().checkCancellation()
                            points.append(try CurveSurfaceIntersection(point: event.point,
                                curveParameter: event.curveParameter + cycle * period,
                                surfaceU: event.surfaceU, surfaceV: event.surfaceV, kind: event.kind,
                                residual: event.residual, iterations: event.iterations))
                            try checkCount(points.count, options: options, tolerance: tolerance)
                            cycle += 1
                        }
                    }
                } else {
                    points = try intersector.intersections(curve: curve, surface: support, options: rawOptions, tolerance: tolerance)
                }
            } catch let error as KernelError where error.code == .nonDiscreteIntersection {
                let bound = try membershipBound(curve: curve, surface: surface, support: support,
                                                range: range, options: options, tolerance: tolerance)
                candidates.append(Candidate(range: range, deviation: bound))
            }
        }

        var admitted: [Candidate] = []
        for candidate in candidates {
            let clipping = try clip(candidate, curve: curve, surface: surface, options: options,
                                    tolerance: tolerance, intersector: intersector, budget: &graphBudget)
            admitted.append(contentsOf: clipping.candidates)
            points.append(contentsOf: clipping.points)
            try checkCount(points.count + admitted.count, options: options, tolerance: tolerance)
        }
        let merged = try merge(admitted)
        var uniquePoints: [CurveSurfaceIntersection] = []
        for event in points.sorted(by: { $0.curveParameter < $1.curveParameter }) {
            try CurrentTaskCancellationChecker().checkCancellation()
            let candidate = candidates.first { $0.range.contains(event.curveParameter) }
            let correspondence = candidate?.isoparametric
            guard !merged.contains(where: { $0.range.contains(event.curveParameter) }),
                  try contains(curve: curve, surface: surface, parameter: event.curveParameter, options: options,
                               tolerance: tolerance, isoparametric: correspondence, graph: candidate?.graph, budget: &graphBudget) else { continue }
            if let last = uniquePoints.last, last.curveParameter == event.curveParameter { continue }
            let endpoint: CurveSurfaceOverlapEndpoint
            if let graph = candidate?.graph {
                endpoint = try CurveSurfaceOverlap.evaluate(curve: curve, surface: surface, parameter: event.curveParameter,
                    uRange: options.surfaceURange, vRange: options.surfaceVRange, tolerance: tolerance,
                    graph: graph, budget: &graphBudget)
            } else {
                endpoint = try CurveSurfaceOverlap.evaluate(curve: curve, surface: surface, parameter: event.curveParameter,
                    uRange: options.surfaceURange, vRange: options.surfaceVRange, tolerance: tolerance,
                    isoparametric: correspondence)
            }
            uniquePoints.append(try CurveSurfaceIntersection(point: endpoint.point, curveParameter: endpoint.curveParameter,
                surfaceU: endpoint.surfaceParameter.u, surfaceV: endpoint.surfaceParameter.v, kind: event.kind,
                residual: endpoint.residual, iterations: event.iterations))
        }
        let overlaps = try merged.map {
            if let graph = $0.graph {
                return try CurveSurfaceOverlap(curve: curve, surface: surface, range: $0.range, deviation: $0.deviation,
                    options: options, tolerance: tolerance, graph: graph, budget: &graphBudget)
            }
            return try CurveSurfaceOverlap(curve: curve, surface: surface, range: $0.range, deviation: $0.deviation,
                                    options: options, tolerance: tolerance, isoparametric: $0.isoparametric)
        }
        try checkCount(uniquePoints.count + overlaps.count, options: options, tolerance: tolerance)
        return CurveSurfaceIntersectionResult(points: uniquePoints, overlaps: overlaps)
    }

    /// Resolves retained original incidence without the legacy overlap ledger.
    func resolve(curve: Curve3D, surface: Surface3D, options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance, intersector: DefaultCurveSurfaceIntersector,
        invocation: CurveSurfaceQueryInvocation) throws -> CurveSurfaceIntersectionResult {
        if let exact = try NativeExactPublicCurveSurfaceProducer().resolve(curve: curve, surface: surface,
            options: options, tolerance: tolerance, invocation: invocation, retainingRelations: true) { return exact }
        if let native = try NativeCurveSurfacePointProducer().resolve(curve: curve, surface: surface,
            options: options, tolerance: tolerance, invocation: invocation, retainingRelations: true) { return native }
        if let original = try OriginalPolynomialCurveSurfacePointProducer().resolve(curve: curve, surface: surface,
            options: options, tolerance: tolerance, invocation: invocation) { return original }
        if let affine = try OriginalAffineCurveSurfacePointProducer().resolve(curve: curve, surface: surface,
            options: options, tolerance: tolerance, invocation: invocation) { return affine }
        if let coons = try OriginalCoonsCurveSurfacePointProducer().resolve(curve: curve, surface: surface,
            options: options, tolerance: tolerance, invocation: invocation) { return coons }
        try options.validate(tolerance: tolerance)
        try invocation.consumeFixedWork()
        guard case .bSpline(let spline) = curve, case .plane(let plane) = surface,
            plane.uDirection != nil else {
            let points = try intersector.intersections(curve: curve, surface: surface, options: options,
                tolerance: tolerance, maximumSpanCount: invocation.maximumSpanCount,
                maximumSubdivisionDepth: invocation.maximumSubdivisionDepth,
                remainingSourceDepth: invocation.remainingSourceDepth,
                consumeWork: invocation.consume, consumeStorage: invocation.consumeStorage,
                maximumAlgebraicDepth: invocation.maximumAlgebraicDepth)
            try invocation.reserve(count: 1, stride: MemoryLayout<CurveSurfaceIntersectionResult>.stride)
            return .init(points: points, overlaps: [])
        }
        let interval: ScalarInterval
        if let requested = options.curveRange { interval = requested }
        else {
            guard case .closed(let lower, let upper) = spline.domain else {
                throw failure(.invalidInput, "Original plane overlaps require an authored base-native range.", tolerance)
            }
            interval = try .init(lower: lower, upper: upper)
        }
        guard interval.lower.isFinite, interval.upper.isFinite, interval.lower < interval.upper,
            spline.degree <= options.maximumPolynomialDegree else {
            throw failure(.invalidInput, "Original plane overlaps require a finite positive range and admitted source degree.", tolerance)
        }
        let contacts = try OriginalNativePlaneContactProducer().contacts(source: spline,
            over: interval, plane: plane, tolerance: tolerance, invocation: invocation)
        // FIXME(INCOMPLETE_IMPLEMENTATION): This caller-admitted richer route
        // composes retained base-native/authored-U plane components. Periodic
        // translated carriers and general support coincidence still need their
        // original complete sector producers; this branch adds no authority to
        // numerical ranges or legacy overlap counters.
        let preparedPlane = try PreparedSurfaceDifferentialEncloser(surface: surface, tolerance: tolerance,
            remainingSourceDepth: invocation.remainingSourceDepth,
            maximumSubdivisionDepth: invocation.maximumSubdivisionDepth,
            consumeWork: invocation.consumeFixedWork, consumeStorage: invocation.consumeStorage,
            maximumAlgebraicDepth: invocation.maximumAlgebraicDepth)
        typealias Clip = OriginalNativePlaneContactProducer.Overlap.ClipResult
        try invocation.reserve(count: contacts.overlaps.count, stride: MemoryLayout<Clip>.stride)
        var clips: [Clip] = []; clips.reserveCapacity(contacts.overlaps.count)
        var pointCount = contacts.isolated.count
        var sectorCount = 0
        for overlap in contacts.overlaps {
            try invocation.consumeFixedWork()
            let clip = try overlap.clipped(uRange: options.surfaceURange,
                vRange: options.surfaceVRange, invocation: invocation)
            let points = pointCount.addingReportingOverflow(clip.isolated.count)
            let sectors = sectorCount.addingReportingOverflow(clip.sectors.count)
            guard !points.overflow, !sectors.overflow else {
                throw failure(.resourceLimitExceeded, "Original plane overlap result count overflows.", tolerance)
            }
            pointCount = points.partialValue; sectorCount = sectors.partialValue
            let total = pointCount.addingReportingOverflow(sectorCount)
            guard !total.overflow else {
                throw failure(.resourceLimitExceeded, "Original plane overlap result count overflows.", tolerance)
            }
            try checkCount(total.partialValue, options: options, tolerance: tolerance)
            clips.append(clip)
        }
        try checkCount(pointCount, options: options, tolerance: tolerance)
        typealias Sector = OriginalNativePlaneContactProducer.Overlap.Sector
        typealias Contact = OriginalNativePlaneContactProducer.Isolated
        try invocation.reserve(count: sectorCount, stride: MemoryLayout<Sector>.stride)
        var sectors: [Sector] = []; sectors.reserveCapacity(sectorCount)
        for clip in clips {
            for sector in clip.sectors { try invocation.consumeFixedWork(); sectors.append(sector) }
        }
        try invocation.reserve(count: pointCount, stride: MemoryLayout<Contact>.stride)
        var events: [Contact] = []; events.reserveCapacity(pointCount)
        func admit(_ contact: Contact) throws {
            for sector in sectors {
                if try sector.hasEndpoint(contact, invocation: invocation) { return }
            }
            if try contact.nativeKnotStation(invocation: invocation) != nil {
                for index in events.indices {
                    if let combined = try events[index].mergingNativeKnotEvent(contact, invocation: invocation) {
                        events[index] = combined
                        return
                    }
                }
            }
            events.append(contact)
        }
        for contact in contacts.isolated { try admit(contact) }
        for clip in clips { for contact in clip.isolated { try admit(contact) } }
        try invocation.reserve(count: events.count, stride: MemoryLayout<CurveSurfaceIntersection>.stride)
        try invocation.reserve(count: sectorCount, stride: MemoryLayout<CurveSurfaceOverlap>.stride)
        var points: [CurveSurfaceIntersection] = []; points.reserveCapacity(events.count)
        var overlaps: [CurveSurfaceOverlap] = []; overlaps.reserveCapacity(sectorCount)
        for contact in events {
            if let event = try intersector.publishOriginalNativePlaneContact(contact,
                preparedPlane: preparedPlane, options: options, tolerance: tolerance, invocation: invocation) {
                points.append(event)
            }
        }
        let width = max(Double.leastNonzeroMagnitude,
            interval.upper * 0.5 - interval.lower * 0.5)
        guard width.isFinite, width > 0 else {
            throw failure(.resourceLimitExceeded, "Original plane overlap has no finite localization width.", tolerance)
        }
        try invocation.reserve(count: sectorCount, stride: MemoryLayout<Sector>.stride)
        var component: [Sector] = []; component.reserveCapacity(sectorCount)
        func publishComponent() throws {
            guard !component.isEmpty else { return }
            let prepared = try OriginalNativePlaneContactProducer.Overlap.PreparedSector.joining(component,
                maximumParameterWidth: width, invocation: invocation)
            try invocation.reserve(count: 1, stride: MemoryLayout<OriginalNativePlaneOverlapCorrespondence>.stride)
            overlaps.append(try .init(original: .init(sector: prepared, preparedPlane: preparedPlane,
                options: options, tolerance: tolerance, invocation: invocation, maximumParameterWidth: width)))
            component.removeAll(keepingCapacity: true)
        }
        for sector in sectors {
            if let preceding = component.last, try !preceding.joins(sector, invocation: invocation) {
                try publishComponent()
            }
            component.append(sector)
        }
        try publishComponent()
        try invocation.reserve(count: 1, stride: MemoryLayout<CurveSurfaceIntersectionResult>.stride)
        return .init(points: points, overlaps: overlaps)
    }

    private func membershipBound(curve: Curve3D, surface: Surface3D, support: Surface3D,
                                 range: ScalarInterval, options: CurveSurfaceIntersectionOptions, tolerance: ModelingTolerance) throws -> Double {
        if try OverlapSourceMembershipResolver().isExactSource(surface, of: curve, tolerance: tolerance) {
            return tolerance.distance
        }
        if case .plane(let plane) = CanonicalAnalyticSurface(support) {
            return try OverlapPlanarMembershipCertifier().deviation(of: curve, over: range, on: plane, tolerance: tolerance)
        }
        if let rational = try AnalyticCurveBSplineBuilder().boundedCurve(curve: curve, interval: range,
            maximumSpanCount: options.maximumCandidateCount, tolerance: tolerance) {
            let spans = try BSplineCurveBezierDecomposer().curvePatches(curve: rational, tolerance: tolerance)
            let proof = OverlapSpanMembershipCertifier(maximumDegree: options.maximumPolynomialDegree, tolerance: tolerance)
            var bound = 0.0
            for span in spans {
                try CurrentTaskCancellationChecker().checkCancellation()
                bound = max(bound, try proof.deviation(of: span, on: CanonicalAnalyticSurface(support)))
            }
            guard bound <= tolerance.distance else {
                throw failure(.intersectionFailure, "The continuous analytic candidate cannot meet the whole-span distance bound.", tolerance)
            }
            return bound
        }
        // FIXME(INCOMPLETE_IMPLEMENTATION): Unretained non-affine free-surface coincidence
        // has no whole-span proof in intersectionResult. Completion requires certified
        // membership and complete overlap-domain isolation before this branch can succeed.
        throw failure(.unsupportedCapability, "This continuous curve-surface domain has no whole-span membership certificate.", tolerance)
    }

    private func proofSupport(_ surface: Surface3D, tolerance: ModelingTolerance) throws
        -> (surface: Surface3D, preservesOriginalParameters: Bool) {
        if case .bSpline(let spline) = surface, let affine = ExactAffineBSplineSurfacePatch(spline) {
            let normal = try affine.uDirection.cross(affine.vDirection).normalized(tolerance: tolerance.distance)
            return (.plane(Plane3D(origin: affine.origin, normal: normal)), false)
        }
        return (surface, true)
    }

    private func clip(_ candidate: Candidate, curve: Curve3D, surface: Surface3D, options: CurveSurfaceIntersectionOptions,
                      tolerance: ModelingTolerance, intersector: DefaultCurveSurfaceIntersector,
                      budget: inout OverlapProofBudget) throws -> (candidates: [Candidate], points: [CurveSurfaceIntersection]) {
        let boundaries = try OverlapChartBoundaryResolver().boundaries(curve: curve, surface: surface, options: options,
            tolerance: tolerance, isoparametric: candidate.isoparametric, regularGraph: candidate.graph, budget: &budget)
        var cuts = [candidate.range.lower, candidate.range.upper]
        for boundary in boundaries {
            try CurrentTaskCancellationChecker().checkCancellation()
            switch boundary {
            case .certifiedSourceParameter(let parameter):
                if candidate.range.contains(parameter) { cuts.append(parameter) }
            case let .plane(plane, parameterPlaneSource):
                var boundaryOptions = options
                boundaryOptions.curveRange = candidate.range
                boundaryOptions.surfaceURange = nil
                boundaryOptions.surfaceVRange = nil
                let source = parameterPlaneSource ?? curve
                let result = try resolve(curve: source, surface: plane, options: boundaryOptions,
                                         tolerance: tolerance, intersector: intersector)
                cuts.append(contentsOf: result.points.map({ $0.curveParameter }))
                for overlap in result.overlaps { cuts.append(overlap.curveRange.lower); cuts.append(overlap.curveRange.upper) }
            }
            try checkCount(cuts.count, options: options, tolerance: tolerance)
        }
        cuts.sort()
        var unique: [Double] = []
        for cut in cuts where unique.last != cut { unique.append(cut) }
        var regions: [Candidate] = []
        for index in 0..<(unique.count - 1) {
            try CurrentTaskCancellationChecker().checkCancellation()
            let lower = unique[index], upper = unique[index + 1]
            guard upper > lower else { continue }
            let middle = lower + (upper - lower) * 0.5
            guard middle > lower, middle < upper else {
                throw failure(.classificationFailure, "An overlap clipping cell has no representable interior parameter.", tolerance)
            }
            // Each cut came from a complete boundary result. An open connected
            // cell has no boundary crossing, so one membership test classifies it.
            if try contains(curve: curve, surface: surface, parameter: middle, options: options, tolerance: tolerance,
                            isoparametric: candidate.isoparametric, graph: candidate.graph, budget: &budget) {
                regions.append(Candidate(range: try ScalarInterval(lower: lower, upper: upper), deviation: candidate.deviation,
                                         isoparametric: candidate.isoparametric, graph: candidate.graph))
            }
        }
        var points: [CurveSurfaceIntersection] = []
        for cut in unique where !regions.contains(where: { $0.range.contains(cut) }) {
            if try contains(curve: curve, surface: surface, parameter: cut, options: options, tolerance: tolerance,
                            isoparametric: candidate.isoparametric, graph: candidate.graph, budget: &budget) {
                let endpoint: CurveSurfaceOverlapEndpoint
                if let graph = candidate.graph {
                    endpoint = try CurveSurfaceOverlap.evaluate(curve: curve, surface: surface, parameter: cut,
                        uRange: options.surfaceURange, vRange: options.surfaceVRange, tolerance: tolerance, graph: graph, budget: &budget)
                } else {
                    endpoint = try CurveSurfaceOverlap.evaluate(curve: curve, surface: surface, parameter: cut,
                        uRange: options.surfaceURange, vRange: options.surfaceVRange, tolerance: tolerance,
                        isoparametric: candidate.isoparametric)
                }
                points.append(try CurveSurfaceIntersection(point: endpoint.point, curveParameter: cut,
                    surfaceU: endpoint.surfaceParameter.u, surfaceV: endpoint.surfaceParameter.v,
                    kind: .tangent, residual: endpoint.residual, iterations: 0))
            }
        }
        return (regions, points)
    }

    private func contains(curve: Curve3D, surface: Surface3D, parameter: Double,
                          options: CurveSurfaceIntersectionOptions, tolerance: ModelingTolerance,
                          isoparametric: OverlapIsoparametricCorrespondence? = nil,
                          graph: OverlapRegularGraphCorrespondence? = nil, budget: inout OverlapProofBudget) throws -> Bool {
        let point = try curve.point(at: parameter, tolerance: tolerance)
        let coordinates: SurfaceParameter
        if let graph {
            coordinates = try graph.parameter(at: parameter, budget: &budget)
        } else if let isoparametric {
            coordinates = isoparametric.parameter(at: parameter)
        } else if case let .surfaceLift(lift) = curve, lift.surface == surface {
            coordinates = try lift.parameterCurve.parameter(atNormalizedFraction: parameter, tolerance: tolerance)
        } else {
            switch try surface.parameterProjectionResult(of: point, tolerance: tolerance) {
            case .projected(let projection): coordinates = SurfaceParameter(u: projection.u, v: projection.v)
            case .outsideTolerance:
                if case .bSpline(let spline) = surface, ExactAffineBSplineSurfacePatch(spline) != nil { return false }
                throw failure(.intersectionFailure, "A certified overlap candidate failed target membership verification.", tolerance)
            }
        }
        let resolver = SurfaceParameterRangeResolver()
        return resolver.resolvedParameter(coordinates.u, domain: surface.uDomain, requestedRange: options.surfaceURange, tolerance: tolerance) != nil
            && resolver.resolvedParameter(coordinates.v, domain: surface.vDomain, requestedRange: options.surfaceVRange, tolerance: tolerance) != nil
    }

    private func merge(_ candidates: [Candidate]) throws -> [Candidate] {
        var result: [Candidate] = []
        for candidate in candidates.sorted(by: { $0.range.lower < $1.range.lower }) {
            if let previous = result.last, candidate.range.lower <= previous.range.upper,
               previous.isoparametric == candidate.isoparametric,
               sameGraph(previous.graph, candidate.graph) {
                result[result.count - 1] = Candidate(range: try ScalarInterval(lower: previous.range.lower,
                    upper: max(previous.range.upper, candidate.range.upper)), deviation: max(previous.deviation, candidate.deviation),
                    isoparametric: previous.isoparametric, graph: previous.graph)
            } else { result.append(candidate) }
        }
        return result
    }

    private func sameGraph(_ first: OverlapRegularGraphCorrespondence?, _ second: OverlapRegularGraphCorrespondence?) -> Bool {
        switch (first, second) {
        case (.none, .none): return true
        case let (.some(first), .some(second)): return first.sharesAuthority(with: second)
        default: return false
        }
    }

    private func checkCount(_ count: Int, options: CurveSurfaceIntersectionOptions, tolerance: ModelingTolerance) throws {
        guard count <= options.maximumCandidateCount else { throw failure(.resourceLimitExceeded, "Continuous intersection results exceed the candidate budget.", tolerance) }
    }

    private func failure(_ code: KernelErrorCode, _ message: String, _ tolerance: ModelingTolerance) -> KernelError {
        KernelError(phase: .geometry, code: code, tolerance: tolerance, message: message)
    }
}
