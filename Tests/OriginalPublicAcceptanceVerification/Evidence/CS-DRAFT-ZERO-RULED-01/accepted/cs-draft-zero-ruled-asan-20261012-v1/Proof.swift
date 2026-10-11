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
@testable import DraftZeroRuledPort

#if canImport(Darwin)
import Darwin
#elseif canImport(WASILibc)
import WASILibc
#endif
import CADCore
import Synchronization
@testable import CADGeometry
@testable import DraftZeroRuledPort

/// Actual finite line queries retain the original zero-draft wall and exact correspondence.
@main struct DraftZeroRuledAcceptance {
    struct Admission: ~Copyable, ExactScalarAdmission {
        var ledger: ExactScalarLedger
        init(work: Int = 8_388_608) throws {
            ledger = .init(limits: try .init(work: work, storageBytes: 400_000_000,
                valueDepth: 32, coefficientDepth: 32))
        }
        mutating func checkpoint() throws(ExactScalarFailure) { try ledger.checkpoint() }
        mutating func consumeWork(_ count: Int) throws(ExactScalarFailure) { try ledger.consumeWork(count) }
        mutating func retainStorage(bytes: Int) throws(ExactScalarFailure) { try ledger.retainStorage(bytes: bytes) }
        mutating func visitCell(axis: ExactScalarRootAxis, depth: Int) throws(ExactScalarFailure) {
            try ledger.visitCell(axis: axis, depth: depth)
        }
        mutating func admitDepth(value: Int, coefficient: Int) throws(ExactScalarFailure) {
            try ledger.admitDepth(value: value, coefficient: coefficient)
        }
    }

    struct Failure: Error { let line: Int }
    nonisolated static func require(_ value: Bool, line: Int = #line) throws {
        if !value { throw Failure(line: line) }
    }
    typealias Field = OriginalExactScalarDomain
    typealias Result = DraftZeroRuledPort.CurveSurfaceIntersectionResult
    final class Counter: Sendable {
        struct State: Sendable { var work = 0; var bytes = 0 }
        private let state = Mutex(State())
        let maximumWork: Int
        let maximumBytes: Int
        let cancelAt: Int?
        let cancelTask: Bool
        let cancelStorageAt: Int?
        init(work: Int = Int.max, bytes: Int = Int.max, cancelAt: Int? = nil, cancelTask: Bool = false, cancelStorageAt: Int? = nil) {
            maximumWork = work; maximumBytes = bytes; self.cancelAt = cancelAt; self.cancelTask = cancelTask
            self.cancelStorageAt = cancelStorageAt
        }
        func consume(_ depth: Int) throws {
            let reached = try state.withLock { state in
                guard state.work < maximumWork else { throw ExactScalarFailure.resourceLimit(.work) }
                state.work += 1; return state.work
            }
            if reached == cancelAt {
                if cancelTask { withUnsafeCurrentTask { $0?.cancel() } }
                else { throw CancellationError() }
            }
        }
        func retain(_ bytes: Int) throws {
            let reached = try state.withLock { state in
                let next = state.bytes.addingReportingOverflow(bytes)
                guard bytes >= 0, !next.overflow, next.partialValue <= maximumBytes else {
                    throw ExactScalarFailure.resourceLimit(.storage)
                }
                state.bytes = next.partialValue
                return state.bytes
            }
            if reached == cancelStorageAt { withUnsafeCurrentTask { $0?.cancel() } }
        }
        var totals: State { state.withLock { $0 } }
    }

    static func marker(_ value: StaticString) { print(value); fflush(nil) }
#if hasFeature(Embedded)
    static func logCount(_ label: StaticString, _ value: Int) {
        print(label, terminator: ": ")
        var divisor = 1
        while divisor <= value / 10 { divisor *= 10 }
        repeat {
            putchar(Int32(48 + value / divisor % 10))
            divisor /= 10
        } while divisor > 0
        putchar(10)
    }
#endif
    static func group() -> String {
#if hasFeature(Embedded)
        if let value = getenv("CAD_PROOF_GROUP") { return String(cString: value) }
        return "ordinary"
#else
        return CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "ordinary"
#endif
    }
    static func input(regression: Int = 0, angle: Double = +0.0, oblique: Bool = false, signedAxis: Double = 4, folded: Bool = false, lineX: Double = 0.5) throws -> (Curve3D, Surface3D) {
        var a = try Admission()
        if regression != 0 {
            let host: Surface3D
            let pcurve: SurfaceParameterCurve
            if regression == 3 {
                host = .procedural(.originalPlaneDerivative(try DerivativeHostShape.shape(weighted:true,projected:true,using:&a)))
                pcurve = .bSpline(.init(degree:1,knots:[0,0,0.5,1,1],controlPoints:[.init(x:0,y:0),.init(x:0.5,y:0.5),.init(x:1,y:1)]))
            } else {
                let shape = try PolylineAtlasLiftProof.shape(multi:regression == 1,using:&a)
                host = regression == 1 ? .procedural(.originalCoons(shape.0)):.procedural(.originalBoundaryCorrected(shape.1))
                pcurve = .polyline(PolylineLiftProof.points())
            }
            return (.surfaceLift(.init(surface:host,parameterCurve:pcurve)),.plane(.init(origin:.init(x:0.5,y:0,z:0),normal:.unitX)))
        }
        let wall = try ExactScalarNumericAccess.withAdmission(&a) { usage in
            let raw = folded ? BSplineCurve3D(degree:1,knots:[0,0,0.5,1,1],controlPoints:[.origin,.init(x:1,y:0,z:0),.origin],weights:[1,1,1])
                : BSplineCurve3D(degree:1,knots:[0,0,1,1],controlPoints:[.origin,.init(x:1,y:0,z:0)],weights:[1,2])
            let generator = try OriginalCurveRootSpan3D(source:.bSpline(raw),start:.authored(0),end:.authored(1),nativeSpanIndex:folded ? nil:1,
                maximumParameterWidth:ModelingTolerance.standard.relative,maximumSubdivisionDepth:0,tolerance:.standard,
                storageByteStride:MemoryLayout<UInt32>.stride,usage:&usage,maximumSpanCount:folded ? 4:2,remainingSourceDepth:0,maximumAlgebraicDepth:0).reversed()
            let axis = Vector3D(x:oblique ? 1:0,y:0,z:signedAxis)
            let draft = try OriginalDraftedCurve3D(generator:generator,normal:.init(x:0,y:0,z:2),axis:axis,pull:axis,
                height:1,angle:angle,remainingSourceDepth:1,tolerance:.standard,usage:&usage)
            return try OriginalDraftedRuledSurface3D(start:draft,endHeight:3,remainingSourceDepth:2,tolerance:.standard,usage:&usage)
        }.value
        return (.line(.init(origin:.init(x:lineX,y:0,z:2),direction:.unitY)),.procedural(.originalDrafted(wall)))
    }
    static func options() throws -> CurveSurfaceIntersectionOptions {
        var options = CurveSurfaceIntersectionOptions()
        options.curveRange = try .init(lower:-1,upper:1)
        options.surfaceURange = try .init(lower:0,upper:1)
        options.surfaceVRange = try .init(lower:0,upper:1)
        return options
    }
    static func query(_ curve:Curve3D,_ surface:Surface3D,_ counter:Counter,
        options:CurveSurfaceIntersectionOptions,sourceDepth:Int = 8,algebraicDepth:Int = 32) throws -> Result {
        try DraftZeroRuledPort.DefaultCurveSurfaceIntersector().intersectionResult(curve:curve,surface:surface,
            options:options,tolerance:.standard,maximumSpanCount:262_144,maximumSubdivisionDepth:8,
            remainingSourceDepth:sourceDepth,consumeWork:{try counter.consume($0)},consumeStorage:{try counter.retain($0)},maximumAlgebraicDepth:algebraicDepth)
    }
    static func numeric(_ points:[CurveSurfaceIntersection]) throws {
        try require(points.count == 1 && points[0].kind == .transverse)
        let p = points[0]
        try require(p.curveParameter == 0 && abs(p.surfaceU-2.0/3) <= 1e-6 && abs(p.surfaceV-0.5) <= 1e-6
            && abs(p.point.x-0.5) <= 1e-6 && p.point.y == 0 && abs(p.point.z-2) <= 1e-6)
    }
    static func rich(_ result:Result) throws {
        try numeric(result.points)
        guard let geometry = result.originalIssuedGeometricRelation,let mapping = result.originalIssuedNumericalPoints else { throw ExactScalarFailure.invalidEvidence }
        try require(result.representation == .numericalRepresentatives && !geometry.isEmpty && !geometry.hasPositiveDimensionalSolutions
            && geometry.pairs.count == 1 && geometry.exactPoints.count == 1 && mapping.count == 1
            && mapping.incidenceRanges == [0..<1] && mapping.incidenceOrdinals == [0])
        var a = try Admission();let f = mapping.coordinates.field
        let zero = try f.integer(0,using:&a),half = try f.dividing(f.integer(1,using:&a),f.integer(2,using:&a),using:&a)
        let two = try f.integer(2,using:&a),u = try f.dividing(two,f.integer(3,using:&a),using:&a)
        for (axis,value) in [zero,u,half,half,zero,two].enumerated() { try require(f.compare(mapping.coordinates.values[axis],value,using:&a) == .equal) }
        let point = geometry.exactPoints[0],q = point.local.witness.field
        try require(point.firstParameters.count == 1 && point.secondParameters.count == 2 && point.originalFirstCoordinates == nil)
        let qt = try q.integer(0,using:&a),qu = try q.dividing(q.integer(2,using:&a),q.integer(3,using:&a),using:&a)
        let qv = try q.dividing(q.integer(1,using:&a),q.integer(2,using:&a),using:&a)
        try require(q.compare(point.firstParameters[0],qt,using:&a) == .equal
            && q.compare(point.secondParameters[0],qu,using:&a) == .equal && q.compare(point.secondParameters[1],qv,using:&a) == .equal)
        for pair in geometry.pairs {
            try require(!pair.geometry.hasPositiveDimensionalSolutions && !pair.geometry.strata.isEmpty)
            for stratum in pair.geometry.strata { try require(stratum.parameterDimension == 0 && stratum.imageDimension == 0 && stratum.fiberDimension == 0) }
        }
    }
    static func generatorMapping(_ surface:Surface3D,_ result:Result) throws {
        guard case .procedural(.originalDrafted(let wall)) = surface,
            let mapping = result.originalIssuedNumericalPoints else { throw ExactScalarFailure.invalidEvidence }
        var a = try Admission();let f = mapping.coordinates.field
        let source = try DefaultOriginalSourceBindingIssuer(provider:OriginalDraftedRuledSurfaceSnapshotProvider(field:f,tolerance:.standard))
            .bind(wall,limits:try .init(remainingSourceDepth:2),using:&a)
        try require(source.original.original == wall && source.sourceDepth == 2 && source.original.originalCellCount == 1)
        let generator = try source.original.originalGeneratorParameter(atU:mapping.coordinates.values[1],using:&a)
        let third = try f.dividing(f.integer(1,using:&a),f.integer(3,using:&a),using:&a)
        try require(f.compare(generator,third,using:&a) == .equal)
    }
    static func regression(_ result: Result, coons: Bool) throws {
        guard let geometry = result.originalIssuedGeometricRelation, let mapping = result.originalIssuedNumericalPoints else {
            throw ExactScalarFailure.invalidEvidence
        }
        let count = coons ? 12 : 3, z = coons ? 0.0 : 0.0625
        try require(result.points.count == 2 && geometry.exactPoints.count == count
            && !geometry.hasPositiveDimensionalSolutions && mapping.count == 2
            && mapping.incidenceRanges[0].count == (coons ? 8 : 2)
            && mapping.incidenceRanges[1].count == (coons ? 4 : 1)
            && Set(mapping.incidenceOrdinals) == Set(0..<count))
        try require(abs(result.points[0].curveParameter - (2.0.squareRoot() - 1)) <= 1e-6
            && result.points[1].curveParameter == 1)
        for p in result.points {
            try require(abs(p.point.x - 0.5) <= 1e-6 && abs(p.point.y - 0.5) <= 1e-6
                && abs(p.point.z - z) <= 1e-6 && abs(p.surfaceU - z) <= 1e-6
                && abs(p.surfaceV + 0.5) <= 1e-6)
        }
    }
    static func derivativeRegression(_ result: Result, normalZ: Bool = false) throws {
        try require(result.points.count == 1 && result.points[0].kind == .transverse)
        let p = result.points[0]
        try require(p.curveParameter == 0.5 && abs(p.point.x-0.5) <= 1e-6 && abs(p.point.y-0.5) <= 1e-6
            && abs(p.point.z-5.0/32) <= 1e-6 && abs(p.surfaceU-5.0/32) <= 1e-6 && abs(p.surfaceV+0.5) <= 1e-6)
        guard let geometry = result.originalIssuedGeometricRelation, let mapping = result.originalIssuedNumericalPoints else {
            throw ExactScalarFailure.invalidEvidence
        }
        try require(result.representation == .numericalRepresentatives && !geometry.isEmpty
            && !geometry.hasPositiveDimensionalSolutions && geometry.pairs.count == 8
            && geometry.exactPoints.count == 8 && mapping.count == 1
            && mapping.incidenceRanges.count == 1 && mapping.incidenceRanges[0].count == 8
            && Set(mapping.incidenceOrdinals) == Set(0..<8))
        var a = try Admission()
        let f = mapping.coordinates.field
        let half = try f.dividing(f.integer(1, using: &a), f.integer(2, using: &a), using: &a)
        let z = try f.dividing(f.integer(5, using: &a), f.integer(32, using: &a), using: &a)
        for ordinal in mapping.incidenceOrdinals {
            for (axis, expected) in [half, normalZ ? half : z, try f.negated(half, using: &a), half, half, z].enumerated() {
                try require(f.compare(mapping.coordinates.values[6 * ordinal + axis], expected, using: &a) == .equal)
            }
            let point = geometry.exactPoints[ordinal]
            guard let original = point.originalFirstCoordinates else { throw ExactScalarFailure.invalidEvidence }
            let q = point.local.witness.field
            let qhalf = try q.dividing(q.integer(1, using: &a), q.integer(2, using: &a), using: &a)
            try require(original.count == 3)
            for value in original { try require(q.compare(value, qhalf, using: &a) == .equal) }
            let pair = geometry.pairs[point.pairOrdinal]
            try require(!pair.geometry.hasPositiveDimensionalSolutions && !pair.geometry.strata.isEmpty)
            for stratum in pair.geometry.strata {
                try require(stratum.parameterDimension == 0 && stratum.imageDimension == 0 && stratum.fiberDimension == 0)
            }
        }
    }
    static func empty(_ result:Result) throws {
        guard let geometry = result.originalIssuedGeometricRelation,let mapping = result.originalIssuedNumericalPoints else { throw ExactScalarFailure.invalidEvidence }
        try require(result.points.isEmpty && geometry.isEmpty && geometry.exactPoints.isEmpty && mapping.count == 0 && !geometry.hasPositiveDimensionalSolutions)
    }
    static func grouped(_ result:Result,corner:Bool) throws {
        guard let geometry = result.originalIssuedGeometricRelation,let mapping = result.originalIssuedNumericalPoints else { throw ExactScalarFailure.invalidEvidence }
        try require(geometry.pairs.count == 2 && geometry.exactPoints.count == 2 && !geometry.hasPositiveDimensionalSolutions
            && result.points.count == (corner ? 1:2) && mapping.count == (corner ? 1:2)
            && Set(mapping.incidenceOrdinals) == Set(0..<2))
        try require(mapping.incidenceRanges.map { $0.count } == (corner ? [2]:[1,1]))
        var a = try Admission();let f = mapping.coordinates.field
        for (group,range) in mapping.incidenceRanges.enumerated() {
            let expectedU = try f.dividing(f.integer(corner ? 2:group == 0 ? 1:3,using:&a),f.integer(4,using:&a),using:&a)
            for index in range {
                let ordinal = mapping.incidenceOrdinals[index]
                try require(f.compare(mapping.coordinates.values[ordinal*6+1],expectedU,using:&a) == .equal)
            }
            let p = result.points[group]
            try require(p.kind == .transverse && p.curveParameter == 0 && abs(p.surfaceU-(corner ? 0.5:group == 0 ? 0.25:0.75)) <= 1e-6
                && abs(p.surfaceV-0.5) <= 1e-6 && abs(p.point.x-(corner ? 1:0.5)) <= 1e-6 && p.point.y == 0 && abs(p.point.z-2) <= 1e-6)
        }
        for pair in geometry.pairs { for stratum in pair.geometry.strata {
            try require(stratum.parameterDimension == 0 && stratum.imageDimension == 0 && stratum.fiberDimension == 0)
        } }
    }
    static func run() async throws {
        let selected = group(),(curve,surface) = try input(),opt = try options()
        let counter = Counter()
        if selected == "ordinary" {
            let port = DraftZeroRuledPort.DefaultCurveSurfaceIntersector()
            try numeric(port.intersections(curve:curve,surface:surface,options:opt,tolerance:.standard))
            try rich(port.intersectionResult(curve:curve,surface:surface,options:opt,tolerance:.standard))
            try numeric(port.intersections(curve:curve,surface:surface,options:opt,tolerance:.standard,
                maximumSpanCount:262_144,maximumSubdivisionDepth:8,remainingSourceDepth:8,
                consumeWork:{try counter.consume($0)},consumeStorage:{try counter.retain($0)},maximumAlgebraicDepth:32))
            let result = try query(curve,surface,Counter(),options:opt)
            try rich(result);try generatorMapping(surface,result)
#if hasFeature(Embedded)
            logCount("ordinaryCallbackWork",counter.totals.work);logCount("ordinaryCallbackBytes",counter.totals.bytes)
#else
            print("ordinaryCallbackWork",counter.totals.work,"ordinaryCallbackBytes",counter.totals.bytes)
#endif
            marker("PASS draft zero finite original line ordinary/callback bare/rich; exactT0/U2over3/Vhalf/XYZhalf0two; one incident; image/fiber0")
        } else if selected == "grouping" {
            for corner in [false,true] {
                let (c,s) = try input(folded:true,lineX:corner ? 1:0.5)
                try grouped(query(c,s,Counter(),options:opt),corner:corner)
                let port = DraftZeroRuledPort.DefaultCurveSurfaceIntersector()
                try grouped(port.intersectionResult(curve:c,surface:s,options:opt,tolerance:.standard),corner:corner)
                try require(port.intersections(curve:c,surface:s,options:opt,tolerance:.standard).count == (corner ? 1:2))
            }
            marker("PASS draft original two-chart generator: equalXYZ/distinctUV remain2groups; shared-knot exactTUV keeps2incidents/1group")
        } else if selected == "regressions" {
            for kind in [1,2,3] {
                let (c,s) = try input(regression:kind),port = DraftZeroRuledPort.DefaultCurveSurfaceIntersector()
                let result = try port.intersectionResult(curve:c,surface:s,options:.init(),tolerance:.standard)
                if kind == 3 { try derivativeRegression(result) } else { try regression(result,coons:kind == 1) }
                try require(port.intersections(curve:c,surface:s,options:.init(),tolerance:.standard).count == result.points.count)
                let admitted = try query(c,s,Counter(),options:.init())
                if kind == 3 { try derivativeRegression(admitted) } else { try regression(admitted,coons:kind == 1) }
                let count = Counter()
                try require(port.intersections(curve:c,surface:s,options:.init(),tolerance:.standard,
                    maximumSpanCount:262_144,maximumSubdivisionDepth:8,remainingSourceDepth:8,
                    consumeWork:{try count.consume($0)},consumeStorage:{try count.retain($0)},maximumAlgebraicDepth:32).count == result.points.count)
            }
            marker("PASS draft port existing Coons/correction/derivative lift regressions on all4 public entries")
        } else if selected == "selections" {
            for range in [try ScalarInterval(lower:0,upper:0),try ScalarInterval(lower:-0.25,upper:0.25)] {
                var selected = opt;selected.curveRange = range;try rich(query(curve,surface,Counter(),options:selected))
            }
            var singleton = opt;singleton.surfaceVRange = try .init(lower:0.5,upper:0.5)
            singleton.surfaceURange = try .init(lower:0.6,upper:0.7)
            try rich(query(curve,surface,Counter(),options:singleton))
            for axis in 0..<3 {
                var selected = opt
                if axis == 0 { selected.curveRange = try .init(lower:0.1,upper:0.2) }
                if axis == 1 { selected.surfaceURange = try .init(lower:2,upper:3) }
                if axis == 2 { selected.surfaceVRange = try .init(lower:0,upper:0.25) }
                try empty(query(curve,surface,Counter(),options:selected))
            }
            marker("PASS draft exactT/V singleton, finite subrequest and completeT/U/V exclusion")
        } else if selected == "guards" {
            for kind in 0..<2 {
                let (c,s) = try input(angle:kind == 0 ? 1e-12:0,oblique:kind == 1)
                try require(OriginalDraftedZeroLinePublicProducer().resolve(curve:c,surface:s,options:opt,tolerance:.standard) == nil)
            }
            try require(OriginalDraftedZeroLinePublicProducer().resolve(curve:curve,surface:surface,options:.init(),tolerance:.standard) == nil)
            let (negativeZeroCurve,negativeZeroSurface) = try input(angle:-0.0)
            try rich(query(negativeZeroCurve,negativeZeroSurface,Counter(),options:opt))
            let result = try query(curve,surface,Counter(),options:opt);try generatorMapping(surface,result)
            marker("PASS source-owned gate declines nonzero tiny angle/oblique axis/wholeline before selection; signedzero same authority; checked child map")
        } else if selected == "query-work" {
            let finite = Counter(work:8_388_608);try rich(query(curve,surface,finite,options:opt))
            for cap in [1,100_000] {
                let count = Counter(work:cap)
                do { _ = try query(curve,surface,count,options:opt);throw Failure(line:#line) }
                catch let error as KernelError { try require(error.code == .resourceLimitExceeded) }
                try require(count.totals.work == cap)
            }
#if hasFeature(Embedded)
            logCount("successfulWork",finite.totals.work);logCount("successfulBytes",finite.totals.bytes)
#else
            print("successfulWork",finite.totals.work,"successfulBytes",finite.totals.bytes)
#endif
            marker("PASS draft existing finite allowance and fixedwork1/100000 exactcallback refusals")
        } else if selected == "query-storage" {
            try rich(query(curve,surface,counter,options:opt));let bytes = counter.totals.bytes
            let exact = Counter(bytes:bytes);try rich(query(curve,surface,exact,options:opt));try require(exact.totals.bytes == bytes)
            do { _ = try query(curve,surface,Counter(bytes:bytes-1),options:opt);throw Failure(line:#line) }
            catch let error as KernelError { try require(error.code == .resourceLimitExceeded) }
#if hasFeature(Embedded)
            logCount("queryBytes",bytes)
#else
            print("queryBytes",bytes)
#endif
            marker("PASS draft independent exactstorage and onebyte-less refusal")
        } else if selected == "depth" {
            for depth in [0,1] {
                marker(depth == 0 ? "DEPTH_SOURCE0_REFUSAL_BEGIN":"DEPTH_SOURCE1_REFUSAL_BEGIN")
                do { _ = try query(curve,surface,Counter(),options:opt,sourceDepth:depth);throw Failure(line:#line) }
                catch let error as KernelError { try require(error.code == .resourceLimitExceeded) }
            }
            marker("DEPTH_SOURCE2_SUCCESS_BEGIN")
            try rich(query(curve,surface,Counter(),options:opt,sourceDepth:2))
            marker("DEPTH_ALGEBRAIC0_REFUSAL_BEGIN")
            do { _ = try query(curve,surface,Counter(),options:opt,algebraicDepth:0);throw Failure(line:#line) }
            catch let error as KernelError { try require(error.code == .resourceLimitExceeded) }
            marker("DEPTH_CANDIDATE1_SUCCESS_BEGIN")
            var candidates = opt;candidates.maximumCandidateCount = 1;try rich(query(curve,surface,Counter(),options:candidates))
            for kind in 0..<2 {
                var selected = opt
                if kind == 0 { selected.maximumCandidateCount = 0 } else { selected.maximumPolynomialDegree = 0 }
                do { _ = try query(curve,surface,Counter(),options:selected);throw Failure(line:#line) }
                catch let error as KernelError { try require(error.code == .resourceLimitExceeded) }
            }
            marker("PASS draft sourceDepth2/candidate1/default32 success; sourceDepth1/algebraic0/candidate0/polynomial0 typed refusal")
        } else if selected == "cancel-entry" {
            withUnsafeCurrentTask { $0?.cancel() }
            do { _ = try query(curve,surface,counter,options:opt);throw Failure(line:#line) }
            catch is CancellationError { }
            try require(counter.totals.work == 0 && counter.totals.bytes == 0)
            marker("PASS draft entryTask cancellation before work/storage")
        } else if selected == "cancel-callbacks" {
            for tick in [1,100_000] {
                let count = Counter(cancelAt:tick)
                do { _ = try query(curve,surface,count,options:opt);throw Failure(line:#line) }
                catch is CancellationError { }
                try require(count.totals.work == tick)
            }
            marker("PASS draft entry/mid callback cancellation exactticks")
        } else if selected == "cancel-final" || selected == "cancel-empty" {
            var selectedOptions = opt
            if selected == "cancel-empty" { selectedOptions.curveRange = try .init(lower:0.1,upper:0.2) }
            let result = try query(curve,surface,counter,options:selectedOptions)
            if selected == "cancel-empty" { try empty(result) } else { try rich(result) }
            let count = Counter(cancelStorageAt:counter.totals.bytes)
            do { _ = try query(curve,surface,count,options:selectedOptions);throw Failure(line:#line) }
            catch is CancellationError { }
            try require(count.totals.bytes == counter.totals.bytes)
            marker("PASS draft finalTask cancellation at empty/nonempty result allocation before publication")
        } else if selected == "lifetime" {
            let result:Result
            do {
                let (c,s) = try input();result = try query(c,s,Counter(),options:opt)
                guard case .procedural(.originalDrafted(let wall)) = s,case .bSpline(let generator) = wall.start.generator.source else { throw ExactScalarFailure.invalidEvidence }
                var changed = generator;changed.controlPoints[0].x = 7
                try require(generator.controlPoints[0].x == 0 && changed.controlPoints[0].x == 7)
                try generatorMapping(s,result)
            }
            try rich(result)
            try await withThrowingTaskGroup(of:Void.self) { readers in
                for _ in 0..<2 { readers.addTask { try rich(result) } }
                try await readers.waitForAll()
            }
            marker("PASS draft detachedsource/result lifetime, generatorCOW and concurrent independent exactreaders")
        } else { throw ExactScalarFailure.invalidEvidence }
    }
    static func main() async {
        do { try await run() }
        catch {
            marker("FAIL draft zero finite line public acceptance")
#if !hasFeature(Embedded)
            if let error = error as? KernelError { print("PUBLIC_KERNEL_CODE",error.code,"MESSAGE",error.message) }
            print(error)
#endif
            exit(1)
        }
    }
}
