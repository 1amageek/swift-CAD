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
#if hasFeature(Embedded)
func print(_ label: StaticString, _ value: String) {
 Swift.print(label,terminator:" ")
 value.withCString { pointer in _ = fputs(pointer, stdout) }
 putchar(10)
}
func print(_ first: StaticString, _ a: Bool, _ second: StaticString, _ b: Bool, _ third: StaticString, _ c: Bool) {
 Swift.print(first,terminator:" ");Swift.print(a ? "true" : "false",terminator:" ")
 Swift.print(second,terminator:" ");Swift.print(b ? "true" : "false",terminator:" ")
 Swift.print(third,terminator:" ");Swift.print(c ? "true" : "false")
}
#endif
@testable import ImplicitAcceptanceUpper
typealias DefaultCurveSurfaceIntersector = ImplicitAcceptanceUpper.DefaultCurveSurfaceIntersector
typealias CurveSurfaceIntersectionResult = ImplicitAcceptanceUpper.CurveSurfaceIntersectionResult
typealias DefaultOriginalCompleteCurveGraphFamilyPreparer<S: Sendable,E: Sendable,C: Sendable> = ImplicitAcceptanceUpper.DefaultOriginalCompleteCurveGraphFamilyPreparer<S,E,C>
typealias OriginalImplicitCurvePublicProducer = ImplicitAcceptanceUpper.OriginalImplicitCurvePublicProducer
#if canImport(Darwin)
import Darwin
#elseif canImport(WASILibc)
import WASILibc
#endif
import Synchronization
import CADCore
@testable import CADGeometry

/// Checks a finite original implicit source cover through the actual ordinary rich CS entry.
@main struct ImplicitReverseDyadicParabolaAcceptance {
  struct Failure: Error { let line: Int }
  private let tolerance = ModelingTolerance.standard
  static func require(_ value: Bool, line: Int = #line) throws {
    if !value { throw Failure(line: line) }
  }
  static func ledger() throws -> ExactScalarLedger {
    .init(limits: try .init(work: 8_388_608, storageBytes: 268_435_456,
      valueDepth: 32, coefficientDepth: 32))
  }
  private func dyadicPlaneParabolaCurve(
    direction: CertifiedImplicitIntersectionDirection = .forward, split: Bool = false
  ) throws -> CertifiedImplicitIntersectionCurve {
    // Exact original controls: S1(u,v)=(u/32,v/64,0),
    // S2(s,r)=(s^2/32,s/64,(2r-1)/64). No fitted chart or sampled certificate.
    let first = BSplineSurface3D(uDegree:1,vDegree:1,
      uKnots:[-0.5,-0.5,1.5,1.5],vKnots:[0,0,1,1],
      controlPoints:[0.0,1.0/64].map { y in
        [Point3D(x:-1.0/64,y:y,z:0),Point3D(x:3.0/64,y:y,z:0)]
      })
    let second = BSplineSurface3D(uDegree:2,vDegree:1,
      uKnots:[0,0,0,1,1,1],vKnots:[0,0,1,1],
      controlPoints:[-1.0/64,1.0/64].map { z in
        [Point3D(x:0,y:0,z:z),Point3D(x:0,y:1.0/128,z:z),Point3D(x:1.0/32,y:1.0/64,z:z)]
      })
    func anchor(_ t: Double) throws -> SurfaceIntersectionParameterPair {
      try SurfaceIntersectionParameterPair(first:SurfaceParameter(u:t*t,v:t),
        second:SurfaceParameter(u:t,v:0.5))
    }
    let ranges: [(Double,Double)] = split ? [(0.25,0.5),(0.5,0.75)] : [(0.25,0.75)]
    let ordered = direction == .forward ? ranges : Array(ranges.reversed())
    let cells = try ordered.map { lower,upper in
      try CertifiedImplicitIntersectionGraphCell(parameterBox:SurfaceIntersectionParameterBox(
        firstU:ScalarInterval(lower:-0.25,upper:0.875),firstV:ScalarInterval(lower:lower,upper:upper),
        secondU:ScalarInterval(lower:0.2,upper:0.8),secondV:ScalarInterval(lower:0,upper:1)),
        freeParameter:.firstV,direction:direction,
        lowerAnchor:anchor(lower),midpointAnchor:anchor((lower+upper)/2),upperAnchor:anchor(upper),
        firstSurface:first,secondSurface:second,tolerance:tolerance)
    }
    return try CertifiedImplicitIntersectionCurve(firstSurface:first,secondSurface:second,
      cells:cells,isClosed:false,tolerance:tolerance)
  }
  static func forwardInput(empty: Bool, split: Bool = true) throws -> (Curve3D, Surface3D, CurveSurfaceIntersectionOptions) {
    let original = try Self().dyadicPlaneParabolaCurve(direction: .forward, split: split)
    try require(original.cells.count == (split ? 2 : 1) && !original.isClosed)
    let target = BSplineSurface3D(uDegree: 1, vDegree: 1,
      uKnots: [0,0,1,1], vKnots: [0,0,1,1],
      controlPoints: [-1.0/64,1.0/64].map { z in
        [Point3D(x:0,y:1.0/128,z:z), Point3D(x:1.0/32,y:1.0/128,z:z)] })
    var options = CurveSurfaceIntersectionOptions()
    options.curveRange = try .init(lower:0,upper:empty ? 0.25 : 1)
    options.surfaceURange = try .init(lower:0,upper:1)
    options.surfaceVRange = try .init(lower:0,upper:1)
    return (.implicit(original),.bSpline(target),options)
  }
  static func verifyForward(_ result: CurveSurfaceIntersectionResult, empty: Bool, storedCells: Int = 2) throws {
    guard let source = result.originalImplicitCurveRelation,
      let geometry = result.originalIssuedGeometricRelation,
      let mapping = result.originalIssuedNumericalPoints else { throw Failure(line:#line) }
    var a = try ledger()
    let coverage = source.finiteCoverage
    try coverage.admitProof(limits:.init(remainingSourceDepth:1),using:&a)
    try require(coverage.reductions.count == storedCells && source.original.original.cells.count == storedCells)
    var checkedGuards = 0
    for (ordinal,reduction) in coverage.reductions.enumerated() {
      try reduction.admitProof(limits:.init(remainingSourceDepth:1),using:&a)
      try require(reduction.cellOrdinal == ordinal)
      let f = reduction.graph.field
      let half = try f.dividing(f.integer(1,using:&a),f.integer(2,using:&a),using:&a)
      let local = try reduction.graph.polynomials.evaluated(reduction.localParameter,at:[half],using:&a).value
      let expectedLocal = storedCells == 1 ? half : try f.integer(ordinal == 0 ? 1 : 0,using:&a)
      try require(f.compare(local,expectedLocal,using:&a) == .equal)
      let lower = storedCells == 1 || ordinal == 0 ? try f.integer(0,using:&a) : half
      let upper = storedCells == 1 || ordinal == 1 ? try f.integer(1,using:&a) : half
      try require(f.compare(reduction.globalSupport.lower,lower,using:&a) == .equal)
      try require(f.compare(reduction.globalSupport.upper,upper,using:&a) == .equal)
      try require(reduction.original.layout.variableCount == 5
        && reduction.original.layout.parameters.count == 1
        && reduction.original.layout.auxiliaries.count == 4)
      try require(reduction.graph.layout.variableCount == 1
        && reduction.graph.layout.parameters.count == 1
        && reduction.graph.layout.auxiliaries.isEmpty)
      try require(reduction.original.conditions.count == 27
        && reduction.substitutedConditions.count == 27
        && reduction.conditionRanges.count == 27
        && reduction.originalCoordinates.count == 5)
      let kept = reduction.retainedConditionOrdinals
      let removed = reduction.eliminatedConditionOrdinals
      try require(kept == kept.sorted() && removed == removed.sorted())
      try require(Set(kept).isDisjoint(with:Set(removed))
        && (kept + removed).sorted() == Array(0..<27)
        && reduction.graph.conditions.count == kept.count)
      let guardField = reduction.graph.field
      let zero = try guardField.integer(0,using:&a)
      // The independent fixture has every original guard valid over its entire closed T interval.
      for ordinal in 0..<27 {
        let range = reduction.conditionRanges[ordinal]
        let lower = try guardField.compare(range.lower,zero,using:&a)
        let upper = try guardField.compare(range.upper,zero,using:&a)
        try require(guardField.compare(range.lower,range.upper,using:&a) != .greater)
        switch reduction.substitutedConditions[ordinal].relation {
        case .equal: try require(lower == .equal && upper == .equal)
        case .notEqual: try require(lower == .greater || upper == .less)
        case .positive: try require(lower == .greater)
        case .nonnegative: try require(lower != .less)
        }
      }
      try require(removed.count == 27 && kept.isEmpty)
      checkedGuards += reduction.substitutedConditions.count
    }
    try require(checkedGuards == storedCells*27)
    try require(source.isEmpty == empty && geometry.isEmpty == empty)
    try require(!source.hasPositiveDimensionalSolutions && !source.hasPositiveDimensionalImage)
    try require(!geometry.hasPositiveDimensionalSolutions && !geometry.hasPositiveDimensionalImage)
    try require(result.overlaps.isEmpty && !result.hasPositiveDimensionalSolutions)
    for pair in geometry.pairs {
      try pair.original.relation.admitProof(using:&a)
      let projection = pair.original.relation.projection
      try require(projection.original.partition.source.variableCount == 3)
      if empty {
        try require(projection.selection.cells.isEmpty && projection.original.cells.isEmpty)
      } else {
        try require(projection.selection.cells.count == 1 && projection.original.cells.count == 1)
        guard let lifts = projection.liftedCells(forProjectedOrdinal:0) else { throw Failure(line:#line) }
        try require(lifts.count == 1 && lifts.original.cells.count == 1)
        for cell in lifts { try require(cell.dimension == 0 && cell.source.variableCount == 3) }
        for stratum in pair.geometry.strata {
          try require(stratum.parameterDimension == 0 && stratum.imageDimension == 0 && stratum.fiberDimension == 0)
        }
      }
    }
    if empty {
      // Left T <= 1/4 or right T >= 3/4 excludes Y=1/128 over the whole selected interval.
      try require(result.points.isEmpty && geometry.exactPoints.isEmpty && mapping.count == 0)
      try require(mapping.incidenceOrdinals.isEmpty && mapping.incidenceRanges.isEmpty)
      return
    }
    try require(geometry.pairs.count == storedCells && geometry.exactPoints.count == storedCells && result.points.count == 1)
    try require(mapping.count == 1 && mapping.incidenceOrdinals.sorted() == Array(0..<storedCells) && mapping.incidenceRanges == [0..<storedCells])
    var seen: Set<Int> = []
    for point in geometry.exactPoints {
      try require(point.pairOrdinal >= 0 && point.pairOrdinal < storedCells)
      let pair = geometry.pairs[point.pairOrdinal]
      try require(pair.original.firstGraphIndex == point.pairOrdinal)
      seen.insert(pair.original.firstGraphIndex)
      let field = point.local.witness.field
      try require(point.firstParameters.count == 1 && point.secondParameters.count == 2)
      try require(point.local.witness.coordinates.count == 3)
      guard let restored = point.originalFirstCoordinates else { throw Failure(line:#line) }
      try require(restored.count == 5)
      // Independent sole complete reduced tuple [T,U,V], retaining every original source coordinate.
      let denominators = [2,4,2]
      for (index,denominator) in denominators.enumerated() {
        let expected = try field.dividing(field.integer(1,using:&a),field.integer(denominator,using:&a),using:&a)
        try require(field.compare(point.local.witness.coordinates[index],expected,using:&a) == .equal)
      }
      // The source-owned unique forward lift preserves original [T,firstU,firstV,secondU,secondV].
      for (index,denominator) in [2,4,2,2,2].enumerated() {
        let expected = try field.dividing(field.integer(1,using:&a),field.integer(denominator,using:&a),using:&a)
        try require(field.compare(restored[index],expected,using:&a) == .equal)
      }
      let xyz = [point.position.x,point.position.y,point.position.z]
      for index in 0..<3 {
        let expected = index == 2 ? try field.integer(0,using:&a) : try field.dividing(field.integer(1,using:&a),field.integer(128,using:&a),using:&a)
        try require(field.compare(xyz[index],expected,using:&a) == .equal)
      }
    }
    try require(seen == Set(0..<storedCells))
    let numeric = mapping.coordinates.field
    for (index,denominator) in [2,4,2,128,128,0].enumerated() {
      let expected = denominator == 0 ? try numeric.integer(0,using:&a) : try numeric.dividing(numeric.integer(1,using:&a),numeric.integer(denominator,using:&a),using:&a)
      try require(numeric.compare(mapping.coordinates.values[index],expected,using:&a) == .equal)
    }
  }
  static func input(empty: Bool) throws -> (Curve3D, Surface3D, CurveSurfaceIntersectionOptions) {
    let original = try Self().dyadicPlaneParabolaCurve(direction:.reversed,split:false)
    try require(original.cells.count == 1 && original.cells[0].direction == .reversed)
    var options = CurveSurfaceIntersectionOptions()
    options.curveRange = try .init(lower:0,upper:1)
    options.surfaceURange = try .init(lower:0,upper:1)
    options.surfaceVRange = try .init(lower:0,upper:empty ? 0.125 : 1)
    return (.implicit(original),original.firstSurface,options)
  }
  static func verify(_ result: CurveSurfaceIntersectionResult, empty: Bool, singleton: Double? = nil) throws {
    guard let source = result.originalImplicitCurveRelation,
      let geometry = result.originalIssuedGeometricRelation,
      let mapping = result.originalIssuedNumericalPoints else { throw Failure(line:#line) }
    let storedCells = 1
    var a = try ledger()
    let coverage = source.finiteCoverage
    try coverage.admitProof(limits:.init(remainingSourceDepth:1),using:&a)
    try require(coverage.reductions.count == storedCells && source.original.original.cells.count == storedCells)
    var checkedGuards = 0
    for (ordinal,reduction) in coverage.reductions.enumerated() {
      try reduction.admitProof(limits:.init(remainingSourceDepth:1),using:&a)
      try require(reduction.cellOrdinal == ordinal)
      let f = reduction.graph.field
      let half = try f.dividing(f.integer(1,using:&a),f.integer(2,using:&a),using:&a)
      let local = try reduction.graph.polynomials.evaluated(reduction.localParameter,at:[half],using:&a).value
      let expectedLocal = storedCells == 1 ? half : try f.integer(ordinal == 0 ? 1 : 0,using:&a)
      try require(f.compare(local,expectedLocal,using:&a) == .equal)
      let lower = storedCells == 1 || ordinal == 0 ? try f.integer(0,using:&a) : half
      let upper = storedCells == 1 || ordinal == 1 ? try f.integer(1,using:&a) : half
      try require(f.compare(reduction.globalSupport.lower,lower,using:&a) == .equal)
      try require(f.compare(reduction.globalSupport.upper,upper,using:&a) == .equal)
      try require(reduction.original.layout.variableCount == 5
        && reduction.original.layout.parameters.count == 1
        && reduction.original.layout.auxiliaries.count == 4)
      try require(reduction.graph.layout.variableCount == 1
        && reduction.graph.layout.parameters.count == 1
        && reduction.graph.layout.auxiliaries.isEmpty)
      try require(reduction.original.conditions.count == 27
        && reduction.substitutedConditions.count == 27
        && reduction.conditionRanges.count == 27
        && reduction.originalCoordinates.count == 5)
      let kept = reduction.retainedConditionOrdinals
      let removed = reduction.eliminatedConditionOrdinals
      try require(kept == kept.sorted() && removed == removed.sorted())
      try require(Set(kept).isDisjoint(with:Set(removed))
        && (kept + removed).sorted() == Array(0..<27)
        && reduction.graph.conditions.count == kept.count)
      let guardField = reduction.graph.field
      let zero = try guardField.integer(0,using:&a)
      // The independent fixture has every original guard valid over its entire closed T interval.
      for ordinal in 0..<27 {
        let range = reduction.conditionRanges[ordinal]
        let lower = try guardField.compare(range.lower,zero,using:&a)
        let upper = try guardField.compare(range.upper,zero,using:&a)
        try require(guardField.compare(range.lower,range.upper,using:&a) != .greater)
        switch reduction.substitutedConditions[ordinal].relation {
        case .equal: try require(lower == .equal && upper == .equal)
        case .notEqual: try require(lower == .greater || upper == .less)
        case .positive: try require(lower == .greater)
        case .nonnegative: try require(lower != .less)
        }
      }
      try require(removed.count == 27 && kept.isEmpty)
      checkedGuards += reduction.substitutedConditions.count
    }
    try require(checkedGuards == storedCells*27)

    let reduction = coverage.reductions[0], e = reduction.original.evidence
    let f = reduction.graph.field, ring = e.parameterPolynomials
    func rational(_ n: Int, _ d: Int) throws -> OriginalExactScalarDomain.Value {
      try f.dividing(f.integer(n,using:&a),f.integer(d,using:&a),using:&a)
    }
    let t = try ring.variable(0,using:&a)
    let half = try rational(1,2), quarter = try rational(1,4), threeQuarters = try rational(3,4)
    let tau = try ring.subtracting(ring.constant(threeQuarters,using:&a),ring.scaled(t,by:half,using:&a),using:&a)
    let square = try ring.multiplying(tau,tau,using:&a)
    let constantHalf = try ring.constant(half,using:&a)
    try require(f.compare(e.freeOffset,threeQuarters,using:&a) == .equal)
    try require(f.compare(e.freeGain,rational(-1,2),using:&a) == .equal)
    let expected = [t,square,tau,tau,constantHalf]
    for index in 0..<5 { try require(ring.equals(reduction.originalCoordinates[index],expected[index],using:&a)) }
    try require(ring.equals(reduction.localParameter,t,using:&a))
    for index in 0..<4 { try require(ring.equals(e.forwardHostCoordinates[index],expected[index+1],using:&a)) }
    let zero = try ring.constant(f.integer(0,using:&a),using:&a)
    let xyz = [try ring.scaled(square,by:rational(1,32),using:&a),
      try ring.scaled(tau,by:rational(1,64),using:&a),zero]
    let tangent = [try ring.scaled(tau,by:rational(-1,32),using:&a),
      try ring.constant(rational(-1,128),using:&a),zero]
    let h=e.forwardHomogeneous, dh=e.forwardHomogeneousDerivative
    try require(h.count == 4 && dh.count == 4)
    let w2=try ring.multiplying(h[3],h[3],using:&a)
    for index in 0..<3 {
      // Polynomial identities prove the entire authored closed interval, not sampled points.
      try require(ring.equals(h[index],ring.multiplying(xyz[index],h[3],using:&a),using:&a))
      let numerator=try ring.subtracting(ring.multiplying(dh[index],h[3],using:&a),
        ring.multiplying(h[index],dh[3],using:&a),using:&a)
      try require(ring.equals(numerator,ring.multiplying(tangent[index],w2,using:&a),using:&a))
    }
    for (parameter,free) in [(0,threeQuarters),(1,quarter)] {
      let value=try ring.evaluated(tau,at:[f.integer(parameter,using:&a)],using:&a).value
      try require(f.compare(value,free,using:&a) == .equal)
    }
    try require(source.isEmpty == empty && geometry.isEmpty == empty && result.overlaps.isEmpty)
    let positive = !empty && singleton == nil
    try require(source.hasPositiveDimensionalSolutions == positive && source.hasPositiveDimensionalImage == positive)
    try require(geometry.hasPositiveDimensionalSolutions == positive && geometry.hasPositiveDimensionalImage == positive)
    try require(result.hasPositiveDimensionalSolutions == positive)
    var sawCurve=false
    for pair in geometry.pairs {
      try pair.original.relation.admitProof(using:&a)
      let projection=pair.original.relation.projection
      try require(pair.original.firstGraphIndex == 0 && projection.original.partition.source.variableCount == 3)
      if empty { try require(projection.selection.cells.isEmpty && projection.original.cells.isEmpty) }
      for stratum in pair.geometry.strata {
        try require(stratum.parameterDimension == stratum.imageDimension && stratum.fiberDimension == 0)
        if stratum.parameterDimension == 1 { sawCurve=true }
      }
    }
    if empty || positive {
      try require(result.points.isEmpty && geometry.exactPoints.isEmpty && mapping.count == 0)
      try require(mapping.incidenceOrdinals.isEmpty && mapping.incidenceRanges.isEmpty)
      if positive { try require(sawCurve && geometry.pairs.count == 1 && result.representation == .exactRelation) }
      return
    }
    guard let parameter=singleton else { throw Failure(line:#line) }
    try require(geometry.pairs.count == 1 && geometry.exactPoints.count == 1 && result.points.count == 1)
    try require(mapping.count == 1 && mapping.incidenceOrdinals == [0] && mapping.incidenceRanges == [0..<1])
    let point=geometry.exactPoints[0], field=point.local.witness.field
    guard let restored=point.originalFirstCoordinates else { throw Failure(line:#line) }
    let free=0.75-parameter/2, u=free*free
    let values=[parameter,u,free,free,0.5]
    try require(restored.count == 5 && point.local.witness.coordinates.count == 3)
    for index in 0..<5 {
      let expected=try field.importingBase(f.binary64(exactly:values[index],using:&a),using:&a)
      try require(field.compare(restored[index],expected,using:&a) == .equal)
    }
    for (index,value) in [parameter,u,free].enumerated() {
      let expected=try field.importingBase(f.binary64(exactly:value,using:&a),using:&a)
      try require(field.compare(point.local.witness.coordinates[index],expected,using:&a) == .equal)
    }
    for (actual,value) in zip([point.position.x,point.position.y,point.position.z],[u/32,free/64,0]) {
      let expected=try field.importingBase(f.binary64(exactly:value,using:&a),using:&a)
      try require(field.compare(actual,expected,using:&a) == .equal)
    }
    let projection=geometry.pairs[0].original.relation.projection
    try require(projection.original.cells.count == 1 && projection.selection.cells.count == 1)
    guard let lifts=projection.liftedCells(forProjectedOrdinal:0) else { throw Failure(line:#line) }
    try require(lifts.count == 1)
    for cell in lifts { try require(cell.dimension == 0 && cell.source.variableCount == 3) }
    let numeric=result.points[0]
    try require(numeric.curveParameter == parameter && numeric.surfaceU == u && numeric.surfaceV == free
      && numeric.point.x == u/32 && numeric.point.y == free/64 && numeric.point.z == 0)
  }
  final class Counter: Sendable {
    struct State: Sendable { var work = 0; var bytes = 0 }
    private let state = Mutex(State())
    let maximumWork: Int, maximumBytes: Int
    let cancelAt: Int?, cancelStorageAt: Int?
    init(work: Int = 8_388_609, bytes: Int = 738_197_504,
      cancelAt: Int? = nil, cancelStorageAt: Int? = nil) {
      maximumWork=work; maximumBytes=bytes; self.cancelAt=cancelAt; self.cancelStorageAt=cancelStorageAt
    }
    func consume(_ depth: Int) throws {
      let count = try state.withLock { value in
        guard value.work < maximumWork else { throw ExactScalarFailure.resourceLimit(.work) }
        value.work += 1; return value.work
      }
      if count == cancelAt { throw CancellationError() }
    }
    func retain(_ bytes: Int) throws {
      let count = try state.withLock { value in
        let next=value.bytes.addingReportingOverflow(bytes)
        guard bytes >= 0, !next.overflow, next.partialValue <= maximumBytes else {
          throw ExactScalarFailure.resourceLimit(.storage)
        }
        value.bytes=next.partialValue; return value.bytes
      }
      if count == cancelStorageAt { withUnsafeCurrentTask { $0?.cancel() } }
    }
    var totals: State { state.withLock { $0 } }
  }
  static func query(_ curve: Curve3D, _ surface: Surface3D, _ options: CurveSurfaceIntersectionOptions,
    counter: Counter = Counter(), sourceDepth: Int = 8, algebraicDepth: Int = 32,
    spans: Int = 262_144) throws -> CurveSurfaceIntersectionResult {
    try DefaultCurveSurfaceIntersector().intersectionResult(curve:curve,surface:surface,
      options:options,tolerance:.standard,maximumSpanCount:spans,maximumSubdivisionDepth:8,
      remainingSourceDepth:sourceDepth,consumeWork:{try counter.consume($0)},
      consumeStorage:{try counter.retain($0)},maximumAlgebraicDepth:algebraicDepth)
  }
  static func numeric(_ points: [CurveSurfaceIntersection], empty: Bool) throws {
    try require(points.count == (empty ? 0:1))
    if !empty {
      let point=points[0]
      try require(point.curveParameter == 0.5 && point.surfaceU == 0.25
        && point.surfaceV == 0.5 && point.point.x == 1.0/128
        && point.point.y == 1.0/128 && point.point.z == 0)
    }
  }
  static func resourceFailure(_ body: () throws -> Void) throws {
    do { try body(); throw Failure(line:#line) }
    catch let error as KernelError { try require(error.code == .resourceLimitExceeded) }
  }
  static func seamMismatchCurve() throws -> CertifiedImplicitIntersectionCurve {
    let original = try Self().dyadicPlaneParabolaCurve(split:true)
    let previous = original.cells[1], box = previous.parameterBox
    let lower = 0.5.nextUp, upper = box.firstV.upper
    func anchor(_ t: Double) throws -> SurfaceIntersectionParameterPair {
      try .init(first:SurfaceParameter(u:t*t,v:t),second:SurfaceParameter(u:t,v:0.5))
    }
    let shifted = try CertifiedImplicitIntersectionGraphCell(parameterBox:.init(
      firstU:box.firstU,firstV:try .init(lower:lower,upper:upper),
      secondU:box.secondU,secondV:box.secondV),freeParameter:.firstV,direction:.forward,
      lowerAnchor:anchor(lower),midpointAnchor:anchor((lower+upper)/2),upperAnchor:anchor(upper),
      firstSurface:original.firstSurface,secondSurface:original.secondSurface,tolerance:.standard)
    return try .init(firstSurface:original.firstSurface,secondSurface:original.secondSurface,
      cells:[original.cells[0],shifted],isClosed:false,tolerance:.standard)
  }
  static func sourceControls() throws {
    let (curve,surface,options)=try input(empty:false)
    for other in [try Self().dyadicPlaneParabolaCurve(direction:.reversed,split:true)] {
      try require(!OriginalImplicitCurveSnapshotProvider.supports(.implicit(other)))
      try require(OriginalImplicitCurvePublicProducer().resolve(curve:.implicit(other),surface:surface,
        options:options,tolerance:.standard) == nil)
    }
    try require(OriginalImplicitCurveSnapshotProvider.supports(curve))
    var a=try ledger()
    let field=try OriginalExactScalarDomain(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
    let zero=try field.integer(0,using:&a), one=try field.integer(1,using:&a)
    let minus=try field.integer(-1,using:&a)
    let unknown=OriginalSourceParameterInterval(lower:minus,upper:one)
    for relation in [OriginalParametricGraphCondition<OriginalExactScalarDomain>.Relation.equal,
      .notEqual,.positive,.nonnegative] {
      try require(!OriginalImplicitCurveGraphReduction.rangeProves(relation,range:unknown,
        field:field,zero:zero,using:&a))
    }
    let limits=try OriginalDomainIdentityLimits(source:.init(remainingSourceDepth:1),
      maximumTransportDepth:32,maximumCharts:2,maximumFamilies:2,maximumIdentityProofs:0)
    let issuer=DefaultOriginalSourceBindingIssuer(provider:OriginalImplicitCurveSnapshotProvider(tolerance:.standard))
    // Actual tolerance-certified adjacency cannot issue an exact joined closed cover.
    let mismatch: CertifiedImplicitIntersectionCurve?
    do { mismatch = try seamMismatchCurve() }
    catch let error as KernelError {
      try require(error.phase == .geometry)
      print("source-seam constructor-negative; exact issuer not invoked");fflush(nil)
      mismatch = nil
    }
    if let mismatch {
      try require(mismatch.cells[0].parameterBox.firstV.upper != mismatch.cells[1].parameterBox.firstV.lower)
      let mismatched = try issuer.bind(.implicit(mismatch),limits:limits.source,using:&a)
      do {
        _ = try DefaultOriginalFiniteImplicitCurveGraphPreparer().prepare(source:mismatched,field:field,
          maximumCharts:2,limits:limits.source,using:&a)
        throw Failure(line:#line)
      } catch OriginalSourceIssuanceFailure.unresolvedAuthority { }
      print("PASS exact seam mismatch unresolvedAuthority before closed-family publication");fflush(nil)
    }
    let first=try issuer.bind(curve,limits:limits.source,using:&a)
    let foreign=try issuer.bind(curve,limits:limits.source,using:&a)
    let family=try DefaultOriginalFiniteImplicitCurveGraphPreparer().prepare(source:first,field:field,
      maximumCharts:2,limits:limits.source,using:&a)
    let interval=try ExactParameterInterval.checked(field:field,lower:.finite(zero),upper:.finite(one),
      depth:.init(value:0,coefficient:0),using:&a)
    let frame=try DefaultOriginalParameterTransporter<OriginalImplicitCurveSnapshot,OriginalExactScalarDomain>()
      .frame(source:foreign,field:field,support:[[interval]],semantics:[.authoredScalar],limits:limits,using:&a)
    let request=try frame.fullSelection(limits:limits,using:&a)
    let algebraic=try ExactAlgebraicScalarDomain.base(field:field,maximumExtensionLevel:Int.max,using:&a)
    do {
      _ = try DefaultOriginalCompleteCurveGraphFamilyPreparer<OriginalImplicitCurveSnapshot,
        OriginalImplicitCurveGraphEvidence,OriginalFiniteImplicitCurveGraphCoverage>().prepare(family:family,
        request:request,field:algebraic,maximumGraphs:2,limits:limits,using:&a)
      throw Failure(line:#line)
    } catch NativeExactRelationFailure.domain(.foreignOwner) { }
  }
  static func run(_ selected: String) async throws {
    let (curve,surface,opt)=try input(empty:false)
    if selected == "ordinary" {
      for empty in [false,true] {
        let (c,s,o)=try input(empty:empty), port=DefaultCurveSurfaceIntersector(), counter=Counter()
        if empty { try numeric(port.intersections(curve:c,surface:s,options:o,tolerance:.standard),empty:true) }
        else {
          do { _ = try port.intersections(curve:c,surface:s,options:o,tolerance:.standard);throw Failure(line:#line) }
          catch let error as KernelError { try require(error.code == .nonDiscreteIntersection) }
        }
        try verify(port.intersectionResult(curve:c,surface:s,options:o,tolerance:.standard),empty:empty)
        if empty {
          try numeric(port.intersections(curve:c,surface:s,options:o,tolerance:.standard,
            maximumSpanCount:262_144,maximumSubdivisionDepth:8,remainingSourceDepth:8,
            consumeWork:{try counter.consume($0)},consumeStorage:{try counter.retain($0)},maximumAlgebraicDepth:32),empty:true)
        } else {
          do { _ = try port.intersections(curve:c,surface:s,options:o,tolerance:.standard,
            maximumSpanCount:262_144,maximumSubdivisionDepth:8,remainingSourceDepth:8,
            consumeWork:{try counter.consume($0)},consumeStorage:{try counter.retain($0)},maximumAlgebraicDepth:32);throw Failure(line:#line) }
          catch let error as KernelError { try require(error.code == .nonDiscreteIntersection) }
        }
        try verify(query(c,s,o),empty:empty)
        log("ordinary-work",counter.totals.work);log("ordinary-bytes",counter.totals.bytes)
      }
    } else if selected == "compatibility" {
      for split in [false,true] {
        let (c,s,o)=try forwardInput(empty:false,split:split)
        try verifyForward(query(c,s,o),empty:false,storedCells:split ? 2 : 1)
      }
    } else if selected == "selections" {
      for parameter in [0.0,0.5,1.0] {
        var singleton=opt;singleton.curveRange=try .init(lower:parameter,upper:parameter)
        let free=0.75-parameter/2
        singleton.surfaceURange=try .init(lower:free*free,upper:free*free)
        singleton.surfaceVRange=try .init(lower:free,upper:free)
        try verify(query(curve,surface,singleton),empty:false,singleton:parameter)
      }
      for (lower,upper) in [(0.0,0.5),(0.5,1.0),(0.25,0.75)] {
        var selection=opt;selection.curveRange=try .init(lower:lower,upper:upper)
        try verify(query(curve,surface,selection),empty:false)
      }
      for axis in 0..<3 {
        var outside=opt
        if axis == 0 { outside.curveRange=try .init(lower:2,upper:3) }
        if axis == 1 { outside.surfaceURange=try .init(lower:2,upper:3) }
        if axis == 2 { outside.surfaceVRange=try .init(lower:2,upper:3) }
        try verify(query(curve,surface,outside),empty:true)
      }
    } else if selected == "source" { try sourceControls()
    } else if selected == "limits" {
      try verify(query(curve,surface,opt,sourceDepth:1,spans:1),empty:false)
      try resourceFailure { _ = try query(curve,surface,opt,sourceDepth:0) }
      try resourceFailure { _ = try query(curve,surface,opt,algebraicDepth:0) }
      do { _ = try query(curve,surface,opt,spans:0);throw Failure(line:#line) }
      catch GeometryConversionError.invalidInput { }
      var degree=opt;degree.maximumPolynomialDegree=2
      try verify(query(curve,surface,degree),empty:false)
      degree.maximumPolynomialDegree=1
      try resourceFailure { _ = try query(curve,surface,degree) }
      // Candidate limits count retained raw cells and components, including endpoint strata.
      var count=opt, countLower=0, countUpper=1
      while true {
        count.maximumCandidateCount=countUpper
        do { try verify(query(curve,surface,count),empty:false);break }
        catch let error as KernelError {
          try require(error.code == .resourceLimitExceeded && countUpper < 4096)
          countLower=countUpper;countUpper *= 2
        }
      }
      while countUpper-countLower > 1 {
        let middle=(countLower+countUpper)/2;count.maximumCandidateCount=middle
        do { try verify(query(curve,surface,count),empty:false);countUpper=middle }
        catch let error as KernelError { try require(error.code == .resourceLimitExceeded);countLower=middle }
      }
      count.maximumCandidateCount=countUpper
      try verify(query(curve,surface,count),empty:false)
      if countUpper > 1 {
        count.maximumCandidateCount=countUpper-1
        try resourceFailure { _ = try query(curve,surface,count) }
      }
      log("minimum-candidate-count",countUpper)
      var lower=0,upper=32
      while upper-lower > 1 {
        let middle=(lower+upper)/2
        do { try verify(query(curve,surface,opt,algebraicDepth:middle),empty:false);upper=middle }
        catch let error as KernelError { try require(error.code == .resourceLimitExceeded);lower=middle }
      }
      try verify(query(curve,surface,opt,algebraicDepth:upper),empty:false)
      try resourceFailure { _ = try query(curve,surface,opt,algebraicDepth:upper-1) }
      log("minimum-algebraic-depth",upper)
    } else if selected == "budgets" {
      for empty in [false,true] {
        let (c,s,o)=try input(empty:empty), baseline=Counter()
        try verify(query(c,s,o,counter:baseline),empty:empty)
        let n=baseline.totals
        try verify(query(c,s,o,counter:Counter(work:n.work,bytes:n.bytes)),empty:empty)
        try resourceFailure { _ = try query(c,s,o,counter:Counter(work:n.work-1,bytes:n.bytes)) }
        try resourceFailure { _ = try query(c,s,o,counter:Counter(work:n.work,bytes:n.bytes-1)) }
        log("exact-work",n.work);log("exact-bytes",n.bytes)
      }
    } else if selected == "continuous" {
      try verify(query(curve,surface,opt),empty:false)
      var partial=opt;partial.surfaceVRange=try .init(lower:0.375,upper:0.625)
      try verify(query(curve,surface,partial),empty:false)
    } else if selected == "cancel-entry" {
      withUnsafeCurrentTask { $0?.cancel() }
      let counter=Counter()
      do { _ = try query(curve,surface,opt,counter:counter);throw Failure(line:#line) }
      catch is CancellationError { }
      try require(counter.totals.work == 0 && counter.totals.bytes == 0)
    } else if selected == "cancel-mid" {
      for tick in [1,1000] {
        let counter=Counter(cancelAt:tick)
        do { _ = try query(curve,surface,opt,counter:counter);throw Failure(line:#line) }
        catch is CancellationError { }
        try require(counter.totals.work == tick)
      }
    } else if selected == "cancel-final" || selected == "cancel-empty" {
      let empty=selected == "cancel-empty",(c,s,o)=try input(empty:empty), baseline=Counter()
      try verify(query(c,s,o,counter:baseline),empty:empty)
      let count=Counter(cancelStorageAt:baseline.totals.bytes)
      do { _ = try query(c,s,o,counter:count);throw Failure(line:#line) }
      catch is CancellationError { }
      try require(count.totals.bytes == baseline.totals.bytes)
    } else if selected == "lifetime" {
      let result:CurveSurfaceIntersectionResult
      do {
        let (c,s,o)=try input(empty:false)
        result=try query(c,s,o)
        guard case .implicit(let original)=c,case .bSpline(let native)=original.firstSurface else { throw Failure(line:#line) }
        var changed=native;changed.controlPoints[0][0].x=7
        try require(native.controlPoints[0][0].x == -1.0/64 && changed.controlPoints[0][0].x == 7)
      }
      try verify(result,empty:false)
      try await withThrowingTaskGroup(of:Void.self) { readers in
        for _ in 0..<2 { readers.addTask { try verify(result,empty:false) } }
        try await readers.waitForAll()
      }
    } else { throw Failure(line:#line) }
    print("PASS reverse implicit finite acceptance",selected);fflush(nil)
  }
  static func log(_ label: String, _ value: Int) {
#if hasFeature(Embedded)
    print(label,terminator:": ")
    var divisor=1
    while divisor <= value/10 { divisor *= 10 }
    repeat { putchar(Int32(48+value/divisor%10));divisor /= 10 } while divisor > 0
    putchar(10)
#else
    print(label,value)
#endif
    fflush(nil)
  }
  static func group() -> String {
#if hasFeature(Embedded)
    if let value=getenv("CAD_PROOF_GROUP") { return String(cString:value) }
    return "ordinary"
#else
    return CommandLine.arguments.dropFirst().first ?? "ordinary"
#endif
  }
  static func main() async {
    do { try await run(group()) }
    catch {
#if !hasFeature(Embedded)
      print("actual-stop:",String(reflecting:error))
#else
      print("actual-stop: implicit acceptance failure")
#endif
      fflush(nil);exit(1)
    }
  }
}
