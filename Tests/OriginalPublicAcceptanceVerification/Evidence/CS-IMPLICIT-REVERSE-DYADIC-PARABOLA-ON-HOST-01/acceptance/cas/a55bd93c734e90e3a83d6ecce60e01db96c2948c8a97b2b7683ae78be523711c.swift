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
/// Supplies every admitted original cell with checked global-T host correspondence.
public struct DefaultOriginalFiniteImplicitCurveGraphPreparer: OriginalCompleteCurveGraphPreparing {
    public typealias Source = OriginalImplicitCurveSnapshot
    public typealias Evidence = OriginalImplicitCurveGraphEvidence
    public typealias Coverage = OriginalFiniteImplicitCurveGraphCoverage
    typealias Reduction = OriginalImplicitCurveGraphReduction
    typealias Field = OriginalExactScalarDomain
    typealias Polynomial = ExactPolynomial<Field>
    public init() {}

    public func prepare<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<Source>,
        field: OriginalExactScalarDomain, maximumCharts: Int, limits: OriginalSourceIssuanceLimits, using admission: inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalCompleteCurveGraphs<Source,Evidence,Coverage> {
        let retained = copy source
        do {
            return try OriginalSourceProofAdmission<A>.withBorrow(&admission) { a in
                try a.checkpoint(); try retained.require(limits)
                guard maximumCharts >= 0 else { throw OriginalSourceIssuanceFailure.invalidChart }
                guard maximumCharts >= retained.original.original.cells.count else { throw OriginalSourceIssuanceFailure.chartLimit }
                guard limits.remainingSourceDepth > 0 else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
                let original = retained.original
                // FIXME(INCOMPLETE_IMPLEMENTATION): The ordinary implicit CS source path
                // issues one or two forward triangular Native cells, or one reversed cell.
                // Other traversals require complete guarded correspondence before they count as supplied.
                guard OriginalImplicitCurveSnapshotProvider.supports(.implicit(original.original)) else {
                    throw OriginalSourceIssuanceFailure.unsupportedRepresentation
                }
                try a.consumeWork(64)
                let children = try OriginalSourceIssuanceLimits(remainingSourceDepth: limits.remainingSourceDepth - 1)
                let native = DefaultOriginalFiniteBSplineChartPreparer<BSplineSurface3D>()
                let first = try native.prepare(source: original.first, field: field, maximumCharts: maximumCharts,
                    limits: children, using: &a)
                let second = try native.prepare(source: original.second, field: field, maximumCharts: maximumCharts,
                    limits: children, using: &a)
                guard first.laws.count == 1, second.laws.count == 1,
                    original.first.owns(first.laws[0].chart), original.second.owns(second.laws[0].chart) else {
                    throw OriginalSourceIssuanceFailure.foreignBinding
                }
                let f = field, ring = try ExactPolynomialDomain(field: f, variableCount: 5, using: &a)
                let parameterRing = try ExactPolynomialDomain(field: f, variableCount: 1, using: &a)
                let zero = try f.integer(0,using:&a), one = try f.integer(1,using:&a)
                try a.retainStorage(bytes: exactScalarPayloadBytes(count: 5,of: Polynomial.self))
                var coordinates: [Polynomial] = []; coordinates.reserveCapacity(5)
                for axis in 0..<5 { coordinates.append(try ring.variable(axis,using:&a)) }

                func embed(_ p: Polynomial, firstHost: Bool) throws -> Polynomial {
                    guard p.variableCount == 2 else { throw OriginalSourceIssuanceFailure.invalidChart }
                    try a.admitDepth(value:p.depth.value,coefficient:p.depth.coefficient)
                    try a.retainStorage(bytes:exactScalarPayloadBytes(count:p.termCount,of:ExactPolynomialTerm<Field.Value>.self))
                    var terms: [ExactPolynomialTerm<Field.Value>] = []; terms.reserveCapacity(p.termCount)
                    for term in p.terms {
                        try a.consumeWork(1)
                        try a.retainStorage(bytes:exactScalarPayloadBytes(count:5,of:Int.self))
                        let powers = firstHost ? [0,term.powers[0],term.powers[1],0,0]
                            : [0,0,0,term.powers[0],term.powers[1]]
                        terms.append(.init(powers:powers,coefficient:try f.importing(term.coefficient,using:&a)))
                    }
                    return try ring.polynomial(orderedTerms:terms,using:&a)
                }
                func constant(_ p: Polynomial) throws -> Field.Value? {
                    if p.terms.isEmpty { return zero }
                    guard p.termCount == 1 else { return nil }
                    for power in p.terms[0].powers { try a.consumeWork(1); if power != 0 { return nil } }
                    return try f.importing(p.terms[0].coefficient,using:&a)
                }
                func position(_ family: OriginalFiniteBSplineCharts<BSplineSurface3D>, firstHost: Bool) throws -> [Polynomial] {
                    let law = family.laws[0]
                    try law.admitProof(using:&a)
                    guard law.support.count == 2,law.homogeneous.count == 4,
                        law.parameterTransport.numerators.count == 2,law.parameterTransport.denominators.count == 2 else {
                        throw OriginalSourceIssuanceFailure.invalidChart
                    }
                    guard let weight = try constant(law.denominator),try f.sign(of:weight,using:&a) == .positive else {
                        throw OriginalSourceIssuanceFailure.unresolvedAuthority
                    }
                    for axis in 0..<2 {
                        let transport = law.parameterTransport
                        guard let divisor = try constant(transport.denominators[axis]),
                            try f.sign(of:divisor,using:&a) != .zero,
                            try law.polynomials.equals(transport.numerators[axis],
                                law.polynomials.scaled(law.polynomials.variable(axis,using:&a),by:divisor,using:&a),using:&a) else {
                            throw OriginalSourceIssuanceFailure.unresolvedAuthority
                        }
                    }
                    try a.retainStorage(bytes:exactScalarPayloadBytes(count:4,of:Polynomial.self))
                    var result: [Polynomial] = []; result.reserveCapacity(4)
                    for p in law.homogeneous { result.append(try embed(p,firstHost:firstHost)) }
                    return result
                }
                let firstPosition = try position(first,firstHost:true)
                let secondPosition = try position(second,firstHost:false)
                let count = original.original.cells.count
                let countValue = try f.integer(count,using:&a)
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalSourceParameterInterval<Field.Value>.self))
                let support = OriginalSourceParameterInterval(lower:zero,upper:one)
                func reduction(cellOrdinal: Int) throws -> Reduction {
                    try a.consumeWork(1)
                    let cell = original.original.cells[cellOrdinal]
                    let ordinal = try f.integer(cellOrdinal,using:&a)
                    let lower = try f.dividing(ordinal,countValue,using:&a)
                    let upper = try f.dividing(f.integer(cellOrdinal+1,using:&a),countValue,using:&a)
                    let globalSupport = OriginalSourceParameterInterval(lower:lower,upper:upper)
                    let localParameter = try parameterRing.subtracting(
                        parameterRing.scaled(parameterRing.variable(0,using:&a),by:countValue,using:&a),
                        parameterRing.constant(ordinal,using:&a),using:&a)
                    let spanParameter = try parameterRing.adding(parameterRing.constant(lower,using:&a),
                        parameterRing.scaled(parameterRing.variable(0,using:&a),
                            by:f.dividing(one,countValue,using:&a),using:&a),using:&a)
                    try a.retainStorage(bytes:exactScalarPayloadBytes(count:4,of:Polynomial.self))
                    var equations: [Polynomial] = []; equations.reserveCapacity(4)
                    for axis in 0..<3 {
                        equations.append(try ring.subtracting(
                            ring.multiplying(firstPosition[axis],secondPosition[3],using:&a),
                            ring.multiplying(secondPosition[axis],firstPosition[3],using:&a),using:&a))
                    }
                    let free = cell.parameterBox.firstV
                    let freeLower = try f.binary64(exactly:free.lower,using:&a)
                    let freeWidth = try f.binary64(exactly:free.width,using:&a)
                    let freeUpper = try f.binary64(exactly:free.upper,using:&a)
                    let reversed = cell.direction == .reversed
                    let offset: Field.Value, gain: Field.Value
                    if reversed {
                        // The admitted single reversed cell applies 1-T once in its original free law.
                        offset = freeUpper
                        gain = try f.negated(freeWidth,using:&a)
                    } else {
                        offset = try f.subtracting(freeLower,f.multiplying(freeWidth,ordinal,using:&a),using:&a)
                        gain = try f.multiplying(freeWidth,countValue,using:&a)
                    }
                    let start = reversed ? freeUpper:freeLower, end = reversed ? freeLower:freeUpper
                    guard try f.sign(of:freeWidth,using:&a) == .positive,
                        try f.compare(f.adding(freeLower,freeWidth,using:&a),freeUpper,using:&a) == .equal,
                        try f.compare(f.adding(offset,f.multiplying(gain,lower,using:&a),using:&a),start,using:&a) == .equal,
                        try f.compare(f.adding(offset,f.multiplying(gain,upper,using:&a),using:&a),end,using:&a) == .equal else {
                        throw OriginalSourceIssuanceFailure.unresolvedAuthority
                    }
                    equations.append(try ring.subtracting(coordinates[2],ring.adding(ring.constant(offset,using:&a),
                        ring.scaled(coordinates[0],by:gain,using:&a),using:&a),using:&a))

                    // Each substitution is forced by one original equality, not an inverse fit.
                    try a.retainStorage(bytes:exactScalarPayloadBytes(count:5,of:Polynomial.self))
                    var replacements = coordinates
                    try a.retainStorage(bytes:exactScalarPayloadBytes(count:5,of:Bool.self))
                    var resolved = [true,false,false,false,false]
                    try a.retainStorage(bytes:exactScalarPayloadBytes(count:8,of:Int.self))
                    try a.retainStorage(bytes:exactScalarPayloadBytes(count:4,of:Field.Value.self))
                    var axes: [Int] = [], selected: [Int] = [], pivots: [Field.Value] = []
                    axes.reserveCapacity(4); selected.reserveCapacity(4); pivots.reserveCapacity(4)
                    for _ in 0..<4 {
                        for axis in 1..<5 where !resolved[axis] {
                            for equation in equations.indices {
                                try a.consumeWork(1)
                                let current = try ring.substituted(equations[equation],with:replacements,using:&a)
                                var pivot: Field.Value?, valid = true
                                for term in current.terms {
                                    try a.consumeWork(5)
                                    if term.powers[axis] == 0 {
                                        for other in 1..<5 where term.powers[other] != 0 { valid = false }
                                    } else {
                                        if term.powers[axis] != 1 || term.powers[0] != 0 || pivot != nil { valid = false }
                                        for other in 1..<5 where other != axis && term.powers[other] != 0 { valid = false }
                                        pivot = term.coefficient
                                    }
                                    if !valid { break }
                                }
                                guard valid,let pivot,try f.sign(of:pivot,using:&a) != .zero else { continue }
                                try a.retainStorage(bytes:exactScalarPayloadBytes(count:current.termCount,of:ExactPolynomialTerm<Field.Value>.self))
                                var terms: [ExactPolynomialTerm<Field.Value>] = []; terms.reserveCapacity(current.termCount)
                                for term in current.terms where term.powers[axis] == 0 {
                                    try a.consumeWork(1)
                                    terms.append(.init(powers:term.powers,
                                        coefficient:try f.dividing(f.negated(term.coefficient,using:&a),pivot,using:&a)))
                                }
                                replacements[axis] = try ring.polynomial(orderedTerms:terms,using:&a)
                                resolved[axis] = true; axes.append(axis); selected.append(equation); pivots.append(pivot)
                                break
                            }
                        }
                    }
                    guard axes.count == 4 else { throw OriginalSourceIssuanceFailure.unresolvedAuthority }
                    for equation in equations {
                        guard try ring.isZero(ring.substituted(equation,with:replacements,using:&a),using:&a) else {
                            throw OriginalSourceIssuanceFailure.unresolvedAuthority
                        }
                    }
                    func project(_ p: Polynomial) throws -> Polynomial {
                        try a.admitDepth(value:p.depth.value,coefficient:p.depth.coefficient)
                        try a.retainStorage(bytes:exactScalarPayloadBytes(count:p.termCount,of:ExactPolynomialTerm<Field.Value>.self))
                        var terms: [ExactPolynomialTerm<Field.Value>] = []; terms.reserveCapacity(p.termCount)
                        for term in p.terms {
                            try a.consumeWork(5)
                            guard term.powers[1] == 0,term.powers[2] == 0,term.powers[3] == 0,term.powers[4] == 0 else {
                                throw OriginalSourceIssuanceFailure.unresolvedAuthority
                            }
                            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Int.self))
                            terms.append(.init(powers:[term.powers[0]],coefficient:try f.importing(term.coefficient,using:&a)))
                        }
                        return try parameterRing.polynomial(orderedTerms:terms,using:&a)
                    }
                    // Pull the actual closed global span back to local [0,1] before bounding.
                    func range(_ p: Polynomial) throws -> OriginalSourceParameterInterval<Field.Value> {
                        let bounded: Polynomial
                        if count == 1 { bounded = p }
                        else {
                            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Polynomial.self))
                            bounded = try parameterRing.substituted(p,with:[spanParameter],using:&a)
                        }
                        let degree = try parameterRing.degree(of:bounded,in:0,using:&a) ?? 0
                        let count = degree.addingReportingOverflow(1)
                        guard !count.overflow else { throw OriginalSourceIssuanceFailure.countOverflow }
                        try a.retainStorage(bytes:exactScalarPayloadBytes(count:count.partialValue,of:Field.Value.self))
                        var powers = [Field.Value](repeating:zero,count:count.partialValue)
                        for term in bounded.terms { try a.consumeWork(1); powers[term.powers[0]] = term.coefficient }
                        var lower: Field.Value?, upper: Field.Value?
                        for index in 0...degree {
                            var value = zero, ratio = one
                            for power in 0...index {
                                try a.consumeWork(1)
                                value = try f.adding(value,f.multiplying(powers[power],ratio,using:&a),using:&a)
                                if power < index {
                                    ratio = try f.dividing(f.multiplying(ratio,f.integer(index-power,using:&a),using:&a),
                                        f.integer(degree-power,using:&a),using:&a)
                                }
                            }
                            if let previous = lower { if try f.compare(value,previous,using:&a) == .less { lower = value } }
                            else { lower = value }
                            if let previous = upper { if try f.compare(value,previous,using:&a) == .greater { upper = value } }
                            else { upper = value }
                        }
                        guard let lower,let upper else { throw OriginalSourceIssuanceFailure.unresolvedAuthority }
                        return .init(lower:lower,upper:upper)
                    }
                    try a.retainStorage(bytes:exactScalarPayloadBytes(count:4,of:Polynomial.self))
                    try a.retainStorage(bytes:exactScalarPayloadBytes(count:4,of:OriginalSourceParameterInterval<Field.Value>.self))
                    var forward: [Polynomial] = [], ranges: [OriginalSourceParameterInterval<Field.Value>] = []
                    forward.reserveCapacity(4); ranges.reserveCapacity(4)
                    for axis in 1..<5 {
                        let p = try project(replacements[axis]); forward.append(p); ranges.append(try range(p))
                    }
                    // Four equalities, sixteen closed bounds, seven original denominator guards.
                    try a.retainStorage(bytes:exactScalarPayloadBytes(count:27,of:OriginalParametricGraphCondition<Field>.self))
                    var conditions: [OriginalParametricGraphCondition<Field>] = []; conditions.reserveCapacity(27)
                    for equation in equations { conditions.append(.init(equation,.equal)) }
                    for axis in 0..<4 {
                        try a.consumeWork(1)
                        guard let coordinate = SurfaceIntersectionParameterCoordinate(rawValue:axis) else {
                            throw OriginalSourceIssuanceFailure.invalidChart
                        }
                        let bound = cell.parameterBox.interval(for:coordinate)
                        let lower = try f.binary64(exactly:bound.lower,using:&a)
                        let upper = try f.binary64(exactly:bound.upper,using:&a)
                        let host = axis < 2 ? first:second, hostAxis = axis % 2
                        let span = host.laws[0].support[hostAxis]
                        guard try f.compare(lower,upper,using:&a) == .less,
                            try f.compare(ranges[axis].lower,lower,using:&a) != .less,
                            try f.compare(ranges[axis].upper,upper,using:&a) != .greater,
                            try f.compare(ranges[axis].lower,span.lower,using:&a) != .less,
                            try f.compare(ranges[axis].upper,span.upper,using:&a) != .greater else {
                            throw OriginalSourceIssuanceFailure.unresolvedAuthority
                        }
                        conditions.append(.init(try ring.subtracting(coordinates[axis+1],ring.constant(lower,using:&a),using:&a),.nonnegative))
                        conditions.append(.init(try ring.subtracting(ring.constant(upper,using:&a),coordinates[axis+1],using:&a),.nonnegative))
                        conditions.append(.init(try ring.subtracting(coordinates[axis+1],ring.constant(span.lower,using:&a),using:&a),.nonnegative))
                        conditions.append(.init(try ring.subtracting(ring.constant(span.upper,using:&a),coordinates[axis+1],using:&a),.nonnegative))
                        conditions.append(.init(try embed(host.laws[0].parameterTransport.denominators[hostAxis],firstHost:axis<2),.notEqual))
                    }
                    conditions.append(.init(firstPosition[3],.notEqual)); conditions.append(.init(secondPosition[3],.notEqual))
                    conditions.append(.init(try ring.constant(one,using:&a),.notEqual))

                    // Original dependent-position Jacobian, in firstU/secondU/secondV order.
                    try a.retainStorage(bytes:exactScalarPayloadBytes(count:9,of:Polynomial.self))
                    var matrix: [Polynomial] = []; matrix.reserveCapacity(9)
                    for row in 0..<3 {
                        for column in 0..<3 {
                            let axis = column == 0 ? 1:column+2
                            matrix.append(try ring.differentiated(equations[row],in:axis,using:&a))
                        }
                    }
                    var determinant = try ring.zero(using:&a)
                    for i in 0..<3 {
                        for j in 0..<3 where j != i {
                            for k in 0..<3 where k != i && k != j {
                                try a.consumeWork(1)
                                let term = try ring.multiplying(matrix[i],ring.multiplying(matrix[3+j],matrix[6+k],using:&a),using:&a)
                                let inversions = (i > j ? 1:0) + (i > k ? 1:0) + (j > k ? 1:0)
                                determinant = inversions % 2 == 0 ? try ring.adding(determinant,term,using:&a)
                                    : try ring.subtracting(determinant,term,using:&a)
                            }
                        }
                    }
                    let jacobian = try project(ring.substituted(determinant,with:replacements,using:&a))
                    guard let jacobianValue = try constant(jacobian),try f.sign(of:jacobianValue,using:&a) != .zero else {
                        throw OriginalSourceIssuanceFailure.unresolvedAuthority
                    }
                    try a.retainStorage(bytes:exactScalarPayloadBytes(count:8,of:Polynomial.self))
                    var positionLaw: [Polynomial] = [], derivative: [Polynomial] = []
                    positionLaw.reserveCapacity(4); derivative.reserveCapacity(4)
                    for p in firstPosition {
                        let composed = try project(ring.substituted(p,with:replacements,using:&a))
                        positionLaw.append(composed)
                        derivative.append(try parameterRing.differentiated(composed,in:0,using:&a))
                    }
                    try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:Polynomial.self))
                    let transport = OriginalRationalParameterTransport<Field>(numerators:[try parameterRing.variable(0,using:&a)],
                        denominators:[try parameterRing.constant(one,using:&a)])
                    try a.retainStorage(bytes:exactScalarPayloadBytes(count:5,of:Int.self))
                    let layout = try OriginalParametricVariableLayout.checked(variableCount:5,parameters:[0],auxiliaries:[1,2,3,4],using:&a)
                    try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalSourceParameterInterval<Field.Value>.self))
                    try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Evidence.self))
                    let evidence = Evidence(source:retained,field:f,cellOrdinal:cellOrdinal,
                        globalSupport:globalSupport,localParameter:localParameter,first:first,second:second,
                        graphPolynomials:ring,conditions:conditions,parameterPolynomials:parameterRing,freeOffset:offset,freeGain:gain,
                        forwardHostCoordinates:forward,forwardHomogeneous:positionLaw,forwardHomogeneousDerivative:derivative,
                        hostCoordinateRanges:ranges,eliminationAxes:axes,eliminationEquations:selected,eliminationPivots:pivots,
                        dependentJacobian:jacobian,proofDepth:try a.depth)
                    typealias Graph = OriginalParametricGraphReceipt<Source,Field,Evidence>
                    try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Bool.self))
                    try a.retainStorage(bytes:exactScalarPayloadBytes(count:3,of:Graph.self))
                    let originalGraph = Graph(source:retained,evidence:evidence,field:f,polynomials:ring,homogeneous:firstPosition,
                        support:[globalSupport],includesUpperBoundary:[true],layout:layout,conditions:conditions,
                        parameterTransport:transport,proofDepth:try a.depth)
                    // The original equalities force these unique auxiliaries for every T.
                    // Retain every substituted guard and the full original graph as the inverse proof.
                    try a.retainStorage(bytes:exactScalarPayloadBytes(count:conditions.count,of:OriginalParametricGraphCondition<Field>.self))
                    var substitutedConditions: [OriginalParametricGraphCondition<Field>] = []
                    substitutedConditions.reserveCapacity(conditions.count)
                    try a.retainStorage(bytes:exactScalarPayloadBytes(count:conditions.count,of:OriginalSourceParameterInterval<Field.Value>.self))
                    var conditionRanges: [OriginalSourceParameterInterval<Field.Value>] = []
                    conditionRanges.reserveCapacity(conditions.count)
                    for condition in originalGraph.conditions {
                        try a.consumeWork(1)
                        let reduced = try project(ring.substituted(condition.polynomial,with:replacements,using:&a))
                        substitutedConditions.append(.init(reduced,condition.relation))
                        conditionRanges.append(try range(reduced))
                    }
                    try a.retainStorage(bytes:exactScalarPayloadBytes(count:conditions.count,of:OriginalParametricGraphCondition<Field>.self))
                    var reducedConditions: [OriginalParametricGraphCondition<Field>] = []
                    reducedConditions.reserveCapacity(conditions.count)
                    try a.retainStorage(bytes:exactScalarPayloadBytes(count:conditions.count,of:Int.self))
                    try a.retainStorage(bytes:exactScalarPayloadBytes(count:conditions.count,of:Int.self))
                    var retainedOrdinals: [Int] = [], eliminatedOrdinals: [Int] = []
                    retainedOrdinals.reserveCapacity(conditions.count); eliminatedOrdinals.reserveCapacity(conditions.count)
                    for index in substitutedConditions.indices {
                        try a.consumeWork(1)
                        let condition = substitutedConditions[index]
                        if try Reduction.rangeProves(condition.relation,range:conditionRanges[index],field:f,zero:zero,using:&a) {
                            eliminatedOrdinals.append(index)
                        } else {
                            retainedOrdinals.append(index); reducedConditions.append(condition)
                        }
                    }
                    try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Int.self))
                    let reducedLayout = try OriginalParametricVariableLayout.checked(variableCount:1,parameters:[0],auxiliaries:[],using:&a)
                    // positionLaw was obtained above by exact substitution in every original XYZW component.
                    let graph = Graph(source:retained,evidence:evidence,field:f,polynomials:parameterRing,homogeneous:positionLaw,
                        support:originalGraph.support,includesUpperBoundary:originalGraph.includesUpperBoundary,
                        layout:reducedLayout,conditions:reducedConditions,parameterTransport:originalGraph.parameterTransport,
                        proofDepth:try a.depth)
                    try a.retainStorage(bytes:exactScalarPayloadBytes(count:5,of:Polynomial.self))
                    var originalCoordinates: [Polynomial] = []; originalCoordinates.reserveCapacity(5)
                    originalCoordinates.append(transport.numerators[0])
                    for p in forward { try a.consumeWork(1); originalCoordinates.append(p) }
                    try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Reduction.self))
                    let result = Reduction(original:originalGraph,graph:graph,substitutedConditions:substitutedConditions,
                        conditionRanges:conditionRanges,retainedConditionOrdinals:retainedOrdinals,
                        eliminatedConditionOrdinals:eliminatedOrdinals,originalCoordinates:originalCoordinates,proofDepth:try a.depth)
                    return result
                }
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:count,of:Reduction.self))
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:count,of:Reduction.Graph.self))
                var reductions: [Reduction] = [], graphs: [Reduction.Graph] = []
                reductions.reserveCapacity(count); graphs.reserveCapacity(count)
                for cellOrdinal in 0..<count {
                    let value = try reduction(cellOrdinal:cellOrdinal)
                    reductions.append(value); graphs.append(value.graph)
                }
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Coverage.self))
                try Coverage.validateCover(source:retained,field:f,reductions:reductions,support:support,using:&a)
                let coverage = Coverage(source:retained,field:f,reductions:reductions,support:support,proofDepth:try a.depth)
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalCompleteCurveGraphs<Source,Evidence,Coverage>.self))
                let result = OriginalCompleteCurveGraphs(source:retained,coverage:coverage,field:f,graphs:graphs,
                    support:support,proofDepth:try a.depth)
                try a.checkpoint(); return result
            }
        } catch { throw .init(preserving:error) }
    }
}
