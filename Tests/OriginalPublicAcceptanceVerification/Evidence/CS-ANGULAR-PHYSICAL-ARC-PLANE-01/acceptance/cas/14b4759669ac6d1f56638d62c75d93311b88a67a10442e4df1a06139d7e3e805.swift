import CADCore
@testable import CADGeometry
@testable import RetainedHostAdapters
import struct RetainedHostAdapters.OriginalSourceProofAdmission
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
import struct AngularSourcePhase.OriginalAnalyticCosineZeroRoot
import protocol AngularSourcePhase.OriginalAnalyticCosineZeroIssuing
import struct AngularSourcePhase.OriginalAnalyticCosineZeroReceipt
import struct AngularSourcePhase.DefaultOriginalAnalyticCosineZeroIssuer
import struct AngularSourcePhase.OriginalAnalyticCoordinateSnapshot
import struct AngularSourcePhase.OriginalAnalyticCoordinateCurveSnapshotProvider
import struct AngularSourcePhase.OriginalPlaneSnapshot
import struct AngularSourcePhase.OriginalPlaneSnapshotProvider
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

/// Complete original native point publication, before any legacy dispatch.
struct NativeCurveSurfacePointProducer {
    func resolve(curve: Curve3D, surface: Surface3D, options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance, invocation: CurveSurfaceQueryInvocation? = nil,
        retainingRelations: Bool = false)
        throws -> CurveSurfaceIntersectionResult? {
        guard case .bSpline(let source) = curve, case .bSpline(let target) = surface else { return nil }
        try options.validate(tolerance: tolerance)
        var usage = try NativeCurveSurfacePointAllowance(options: options, invocation: invocation)
        try usage.consumeExactWork(1)
        guard invocation.map({ $0.remainingSourceDepth > 0 }) ?? true else {
            throw failure(.resourceLimitExceeded, "Native point preparation exhausted original source depth.", tolerance)
        }
        try invocation?.consume(depth: 0)
        guard max(source.degree, target.uDegree, target.vDegree) <= options.maximumPolynomialDegree else {
            throw failure(.resourceLimitExceeded, "Native point source degree exceeds the admitted ceiling.", tolerance)
        }
        try source.validate(tolerance: tolerance, consumeWork: { try usage.consumeExactWork(1) })
        try target.validate(tolerance: tolerance, consumeWork: { try usage.consumeExactWork(1) })
        let t = try ScalarInterval(lower: source.knots[source.degree], upper: source.knots[source.controlPointCount])
        let u = try ScalarInterval(lower: target.uKnots[target.uDegree], upper: target.uKnots[target.uControlPointCount])
        let v = try ScalarInterval(lower: target.vKnots[target.vDegree], upper: target.vKnots[target.vControlPointCount])
        func selected(_ explicit: ScalarInterval?, native: ScalarInterval, periodic: Bool) throws -> ScalarInterval {
            if let explicit { return explicit }
            return periodic ? try .init(lower: 0, upper: native.upper - native.lower) : native
        }
        let selectedT = try selected(options.curveRange, native: t, periodic: source.isPeriodic)
        let selectedU = try selected(options.surfaceURange, native: u, periodic: target.isUPeriodic)
        let selectedV = try selected(options.surfaceVRange, native: v, periodic: target.isVPeriodic)
        try RationalAlgebraStorage.retain(9, of: OriginalRationalParameterDomain.self, usage: &usage)
        let native = try [OriginalRationalParameterDomain(source.isPeriodic ? nil : t, usage: &usage),
            OriginalRationalParameterDomain(target.isUPeriodic ? nil : u, usage: &usage),
            OriginalRationalParameterDomain(target.isVPeriodic ? nil : v, usage: &usage)]
        let requested = try [OriginalRationalParameterDomain(selectedT, usage: &usage),
            OriginalRationalParameterDomain(selectedU, usage: &usage), OriginalRationalParameterDomain(selectedV, usage: &usage)]
        var effective: [OriginalRationalParameterDomain]? = []
        effective?.reserveCapacity(3)
        for axis in 0..<3 {
            if let intersection = try native[axis].intersecting(requested[axis], usage: &usage) {
                effective?.append(intersection)
            } else { effective = nil }
        }
        let maximumSpans = min(invocation?.maximumSpanCount ?? options.maximumCandidateCount, 262_144)
        let curveCover = try OriginalNativeCurveChartCover(source: source,
            over: source.isPeriodic ? selectedT : t, tolerance: tolerance,
            maximumSpanCount: maximumSpans, usage: &usage)
        let nativeBox = SurfaceParameterBox(u: target.isUPeriodic ? selectedU : u, v: target.isVPeriodic ? selectedV : v)
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: target, tolerance: tolerance,
            consumeWork: { try usage.consumeExactWork(1) }, consumeStorage: { try usage.retainBytes($0) })
        let spans = try prepared.originalIntersectionNativeSpans(over: nativeBox, tolerance: tolerance,
            maximumSpanCount: maximumSpans, consumeWork: { try usage.consumeExactWork(1) },
            consumeStorage: { try usage.retainBytes($0) })
        let productCount = try rationalAlgebraCount(curveCover.spans.count, spans.count, multiply: true)
        guard productCount > 0, productCount <= maximumSpans else {
            throw failure(.resourceLimitExceeded, "Native point product count exceeds the cumulative span ceiling.", tolerance)
        }
        try RationalAlgebraStorage.retain(productCount, of: NativeCurveSurfacePointChart.self, usage: &usage)
        var charts: [NativeCurveSurfacePointChart] = []; charts.reserveCapacity(productCount)
        var references: [NativeCurveSurfacePointCell] = []
        var points: [CurveSurfaceIntersection] = []
        var retainedParameters: [OriginalSingularFieldValueIsolation] = []
        var retainedLocalizations: [NativeCurveSurfaceScalarLocalization?] = []
        var capacity = 0
        for curveOwner in curveCover.spans {
            try usage.consumeExactWork(1)
            let curveLaw = curveOwner.law
            for span in spans {
                try usage.consumeExactWork(1)
                let surfaceLaw = try OriginalRationalSurfacePolynomial(source: target, native: span,
                    domain: .init(u: span.uBounds, v: span.vBounds), view: .init(x: 0, y: 0, z: 1),
                    tolerance: tolerance, usage: &usage)
                let system = try OriginalRationalIntersectionSystem(curve: curveLaw, surface: surfaceLaw, usage: &usage)
                let decomposition: OriginalRationalIntersectionDecomposition?
                let domains: [OriginalRationalParameterDomain]
                if retainingRelations && productCount > 1 {
                    // The whole common refinement proves these retained original source bindings.
                    decomposition = nil
                    try RationalAlgebraStorage.retain(3, of: OriginalRationalParameterDomain.self, usage: &usage)
                    domains = try [.init(lower: curveLaw.lowerParameter, upper: curveLaw.upperParameter, usage: &usage),
                        .init(span.uBounds, usage: &usage), .init(span.vBounds, usage: &usage)]
                } else {
                    let proved = try OriginalRationalIntersectionDecomposition.prepare(system: system,
                        requestedDomains: requested, pruneExcludedPrefixes: true, normalizeDenominatorFactors: true,
                        isolatedOnly: !retainingRelations, preferIsolatedCells: retainingRelations,
                        maximumDepth: usage.maximumAlgebraicDepth, usage: &usage)
                    decomposition = proved; domains = proved.nativeDomains
                }
                let chartIndex = charts.count
                charts.append(.init(curveOwner: curveOwner, surfaceOwner: span, surface: surfaceLaw,
                    system: system, nativeDomains: domains, decomposition: decomposition))
                if let decomposition,
                    case .parameterCells(let strata, _, _) = decomposition.coverage,
                    let chartDomains = decomposition.effectiveDomains {
                    let partition = strata.partition
                    var hasPositiveDimension = false
                    for index in partition.solutionCells {
                        try usage.consumeExactWork(1)
                        if partition.cells[index].dimension > 0 { hasPositiveDimension = true }
                    }
                    if hasPositiveDimension {
                        guard retainingRelations else {
                            throw failure(.nonDiscreteIntersection,
                                "The original requested native product contains a positive-dimensional intersection.", tolerance)
                        }
                    }
                    try RationalAlgebraStorage.retain(partition.solutionCells.count, of: Int.self, usage: &usage)
                    var isolatedCells: [Int] = []; isolatedCells.reserveCapacity(partition.solutionCells.count)
                    if case .parameterCells(_, _, let connected) = decomposition.coverage {
                        for component in connected.components {
                            var dimension = 0
                            for index in component.cellIndexes {
                                try usage.consumeExactWork(1)
                                dimension = max(dimension, partition.cells[index].dimension)
                            }
                            if dimension == 0 { isolatedCells.append(contentsOf: component.cellIndexes) }
                        }
                    }
                    for index in isolatedCells {
                        try RationalAlgebraStorage.retain(3, of: OriginalSingularFieldValueIsolation.self, usage: &usage)
                        try RationalAlgebraStorage.retain(3, of: NativeCurveSurfaceScalarLocalization?.self, usage: &usage)
                        var parameters: [OriginalSingularFieldValueIsolation] = []; parameters.reserveCapacity(3)
                        var localizations: [NativeCurveSurfaceScalarLocalization?] = []; localizations.reserveCapacity(3)
                        let point = try NativeCurveSurfacePointPublisher().publish(cell: partition.cells[index], partition: partition,
                            cellIndex: index, effectiveDomains: chartDomains, curve: curveLaw, surfaceHomogeneous: surfaceLaw.homogeneous,
                            surfaceNormalNumerators: surfaceLaw.normalNumerators,
                            options: options, tolerance: tolerance,
                            nativeDomains: (curveOwner.nativeDomain, span.uBounds, span.vBounds),
                            retainingParameters: &parameters, retainingLocalizations: &localizations, usage: &usage)
                        // Source basis chooses the right positive span at every internal knot.
                        // Chart closure remains retained for coverage, but does not duplicate a tuple.
                        var owns = true
                        for axis in 0..<3 {
                            let upper: Double, final: Double
                            switch axis {
                            case 0: upper = curveOwner.nativeDomain.upper; final = t.upper
                            case 1: upper = span.uBounds.upper; final = u.upper
                            default: upper = span.vBounds.upper; final = v.upper
                            }
                            let periodic = axis == 0 ? source.isPeriodic : axis == 1 ? target.isUPeriodic : target.isVPeriodic
                            if !periodic && upper == final { continue }
                            let comparison = try parameters[axis].compared(to: .originalDouble(upper, usage: &usage),
                                maximumDepth: usage.maximumAlgebraicDepth, usage: &usage)
                            parameters[axis] = comparison.isolation
                            if comparison.sign == .zero { owns = false }
                        }
                        guard owns else { continue }
                        guard points.count < options.maximumCandidateCount else {
                            throw failure(.resourceLimitExceeded, "Native isolated tuple count exceeds the cumulative result ceiling.", tolerance)
                        }
                        if points.count == capacity {
                            let doubled = try rationalAlgebraCount(max(1, capacity), 2, multiply: true)
                            capacity = min(options.maximumCandidateCount, doubled)
                            let scalarCapacity = try rationalAlgebraCount(capacity, 3, multiply: true)
                            try RationalAlgebraStorage.retain(capacity, of: CurveSurfaceIntersection.self, usage: &usage)
                            try RationalAlgebraStorage.retain(capacity, of: NativeCurveSurfacePointCell.self, usage: &usage)
                            try RationalAlgebraStorage.retain(scalarCapacity, of: OriginalSingularFieldValueIsolation.self, usage: &usage)
                            try RationalAlgebraStorage.retain(scalarCapacity, of: NativeCurveSurfaceScalarLocalization?.self, usage: &usage)
                            points.reserveCapacity(capacity); references.reserveCapacity(capacity)
                            retainedParameters.reserveCapacity(scalarCapacity); retainedLocalizations.reserveCapacity(scalarCapacity)
                        }
                        points.append(point); references.append(.init(chartIndex: chartIndex, cellIndex: index))
                        retainedParameters.append(contentsOf: parameters); retainedLocalizations.append(contentsOf: localizations)
                    }
                }
            }
        }
        try RationalAlgebraStorage.retain(charts.count, of: OriginalNativeCurveSurfaceChart.self, usage: &usage)
        var sourceCharts: [OriginalNativeCurveSurfaceChart] = []; sourceCharts.reserveCapacity(charts.count)
        for chart in charts { try usage.consumeExactWork(1); sourceCharts.append(.init(chart: chart)) }
        let relation: OriginalNativeCurveSurfaceRelation?
        if retainingRelations {
            try RationalAlgebraStorage.retain(1, of: OriginalNativeCurveSurfaceRelation.self, usage: &usage)
            relation = try .init(charts: charts, sourceCharts: sourceCharts,
                curve: source, surface: target, tolerance: tolerance,
                nativeDomains: native, requestedDomains: requested, effectiveDomains: effective,
                maximumCandidateCount: options.maximumCandidateCount,
                maximumDepth: usage.maximumAlgebraicDepth, usage: &usage)
        } else { relation = nil }
        if let common = relation?.composition, let effective {
            for component in common.connected.components {
                var dimension = 0
                for index in component.cellIndexes {
                    try usage.consumeExactWork(1)
                    dimension = max(dimension, common.partition.cells[index].dimension)
                }
                guard dimension == 0 else { continue }
                for index in component.cellIndexes {
                    let chartIndex = common.chartOwners[index], chart = charts[chartIndex]
                    try RationalAlgebraStorage.retain(3, of: OriginalSingularFieldValueIsolation.self, usage: &usage)
                    try RationalAlgebraStorage.retain(3, of: NativeCurveSurfaceScalarLocalization?.self, usage: &usage)
                    var parameters: [OriginalSingularFieldValueIsolation] = []; parameters.reserveCapacity(3)
                    var localizations: [NativeCurveSurfaceScalarLocalization?] = []; localizations.reserveCapacity(3)
                    let point = try NativeCurveSurfacePointPublisher().publish(cell: common.partition.cells[index], partition: common.partition,
                        cellIndex: index, effectiveDomains: effective, curve: chart.curve, surfaceHomogeneous: chart.surface.homogeneous,
                        surfaceNormalNumerators: chart.surface.normalNumerators,
                        options: options, tolerance: tolerance,
                        nativeDomains: (chart.curveOwner.nativeDomain, chart.surfaceOwner.uBounds, chart.surfaceOwner.vBounds),
                        retainingParameters: &parameters, retainingLocalizations: &localizations, usage: &usage)
                    guard points.count < options.maximumCandidateCount else {
                        throw failure(.resourceLimitExceeded, "Native composed isolated tuple count exceeds the cumulative result ceiling.", tolerance)
                    }
                    if points.count == capacity {
                        let doubled = try rationalAlgebraCount(max(1, capacity), 2, multiply: true)
                        capacity = min(options.maximumCandidateCount, doubled)
                        let scalarCapacity = try rationalAlgebraCount(capacity, 3, multiply: true)
                        try RationalAlgebraStorage.retain(capacity, of: CurveSurfaceIntersection.self, usage: &usage)
                        try RationalAlgebraStorage.retain(capacity, of: NativeCurveSurfacePointCell.self, usage: &usage)
                        try RationalAlgebraStorage.retain(scalarCapacity, of: OriginalSingularFieldValueIsolation.self, usage: &usage)
                        try RationalAlgebraStorage.retain(scalarCapacity, of: NativeCurveSurfaceScalarLocalization?.self, usage: &usage)
                        points.reserveCapacity(capacity); references.reserveCapacity(capacity)
                        retainedParameters.reserveCapacity(scalarCapacity); retainedLocalizations.reserveCapacity(scalarCapacity)
                    }
                    points.append(point); references.append(.init(chartIndex: chartIndex, cellIndex: index))
                    retainedParameters.append(contentsOf: parameters); retainedLocalizations.append(contentsOf: localizations)
                }
            }
        }
        try order(points: &points, references: &references, parameters: &retainedParameters,
            localizations: &retainedLocalizations, charts: charts, usage: &usage)
        try RationalAlgebraStorage.retainBytes(MemoryLayout<BSplineCurve3D>.stride + MemoryLayout<BSplineSurface3D>.stride
            + MemoryLayout<ModelingTolerance>.stride + 9 * MemoryLayout<[Int]>.stride
            + MemoryLayout<OriginalRationalIntersectionCells?>.stride
            + 2 * MemoryLayout<UnsafeRawPointer>.stride, usage: &usage)
        let receipt = OriginalNativeCurveSurfacePoints(curve: source, surface: target, tolerance: tolerance,
            nativeDomains: native, requestedDomains: requested, effectiveDomains: effective,
            charts: charts, sourceCharts: sourceCharts, composedPartition: relation?.composition?.partition, pointCells: references,
            parameterIsolations: retainedParameters, parameterLocalizations: retainedLocalizations)
        try RationalAlgebraStorage.retain(1, of: CurveSurfaceIntersectionResult.self, usage: &usage)
        try CurrentTaskCancellationChecker().checkCancellation()
        return .init(points: points, overlaps: [], originalNativePoints: receipt,
            originalNativeRelations: relation)
    }

    /// Stable merge ordering compares original tuples, never their numerical image.
    private func order(points: inout [CurveSurfaceIntersection],
        references: inout [NativeCurveSurfacePointCell],
        parameters: inout [OriginalSingularFieldValueIsolation],
        localizations: inout [NativeCurveSurfaceScalarLocalization?],
        charts: [NativeCurveSurfacePointChart], usage: inout NativeCurveSurfacePointAllowance) throws {
        guard points.count > 1, charts.count > 1 else { return }
        let count = points.count
        try RationalAlgebraStorage.retain(count, of: Int.self, usage: &usage)
        try RationalAlgebraStorage.retain(count, of: Int.self, usage: &usage)
        var indices: [Int] = []; indices.reserveCapacity(count)
        for index in 0..<count { try usage.consumeExactWork(1); indices.append(index) }
        var scratch = [Int](repeating: 0, count: count)
        func precedes(_ first: Int, _ second: Int, usage: inout NativeCurveSurfacePointAllowance) throws -> Bool {
            for axis in 0..<3 {
                var a = parameters[first * 3 + axis], b = parameters[second * 3 + axis]
                let sign = try OriginalSingularFieldValueOrder.compare(&a, &b,
                    maximumDepth: usage.maximumAlgebraicDepth, maximumCoefficientDepth: 0, usage: &usage)
                parameters[first * 3 + axis] = a; parameters[second * 3 + axis] = b
                if sign != .zero { return sign == .negative }
            }
            // Exact source ownership forbids a duplicate tuple across different products.
            throw rationalAlgebraFailure("Distinct native chart owners issued the same exact parameter tuple.")
        }
        var width = 1
        while width < count {
            var start = 0
            while start < count {
                let middle = min(count, try rationalAlgebraCount(start, width))
                let end = min(count, try rationalAlgebraCount(middle, width))
                var left = start, right = middle, destination = start
                while left < middle || right < end {
                    try usage.consumeExactWork(1)
                    let useLeft: Bool
                    if right == end { useLeft = true }
                    else if left == middle { useLeft = false }
                    else { useLeft = try precedes(indices[left], indices[right], usage: &usage) }
                    if useLeft { scratch[destination] = indices[left]; left += 1 }
                    else { scratch[destination] = indices[right]; right += 1 }
                    destination += 1
                }
                start = end
            }
            swap(&indices, &scratch)
            width = try rationalAlgebraCount(width, 2, multiply: true)
        }
        try RationalAlgebraStorage.retain(count, of: CurveSurfaceIntersection.self, usage: &usage)
        try RationalAlgebraStorage.retain(count, of: NativeCurveSurfacePointCell.self, usage: &usage)
        let scalarCount = try rationalAlgebraCount(count, 3, multiply: true)
        try RationalAlgebraStorage.retain(scalarCount, of: OriginalSingularFieldValueIsolation.self, usage: &usage)
        try RationalAlgebraStorage.retain(scalarCount, of: NativeCurveSurfaceScalarLocalization?.self, usage: &usage)
        var orderedPoints: [CurveSurfaceIntersection] = []; orderedPoints.reserveCapacity(count)
        var orderedReferences: [NativeCurveSurfacePointCell] = []; orderedReferences.reserveCapacity(count)
        var orderedParameters: [OriginalSingularFieldValueIsolation] = []; orderedParameters.reserveCapacity(scalarCount)
        var orderedLocalizations: [NativeCurveSurfaceScalarLocalization?] = []; orderedLocalizations.reserveCapacity(scalarCount)
        for ordinal in indices {
            try usage.consumeExactWork(1)
            orderedPoints.append(points[ordinal]); orderedReferences.append(references[ordinal])
            for axis in 0..<3 {
                orderedParameters.append(parameters[ordinal * 3 + axis])
                orderedLocalizations.append(localizations[ordinal * 3 + axis])
            }
        }
        points = orderedPoints; references = orderedReferences
        parameters = orderedParameters; localizations = orderedLocalizations
    }

    private func failure(_ code: KernelErrorCode, _ message: String, _ tolerance: ModelingTolerance) -> KernelError {
        .init(phase: .geometry, code: code, tolerance: tolerance, message: message)
    }
}
