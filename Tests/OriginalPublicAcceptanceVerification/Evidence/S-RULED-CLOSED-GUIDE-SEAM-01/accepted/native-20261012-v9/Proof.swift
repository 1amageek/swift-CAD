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


import enum RetainedHostAdapters.OriginalDomainAccess
import class RetainedHostAdapters.OriginalIdentityReadmission
import CADCore
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#endif
@testable import CADGeometry
@testable import RetainedHostAdapters
@testable import CallerAdapters
@testable import GuideSeamPort
@testable import PublicLiftPlane
@testable import RuledObservationAdapters

/// Observes the actual single-parent closed guide source before checked seam issuance.
@main struct ClosedGuideSeamAcceptance {
    typealias F = OriginalExactScalarDomain
    typealias G = CallerAdapters.OriginalRetainedGuideCurveSnapshot
    typealias S = RuledObservationAdapters.OriginalRuledSurfaceSnapshot<G,G>
    typealias Q = OriginalRuledChartSelection<G,Int,G,Int,F>
    typealias Law = OriginalRationalChartReceipt<S,Q,F>
    typealias Cover = OriginalIssuedDomainCover<S,Q,F>
    typealias Raw = GuideSeamPort.OriginalIssuedGraphRelations<S,Law,Cover,S,Law,Cover>
    typealias Cells = PublicLiftPlane.ExactRealCellDomain<F>
    struct Admission: ~Copyable, ExactScalarAdmission {
        var ledger: ExactScalarLedger
        var checkpoints=0
        let cancelAt:Int?
        let cancelWork:Int?
        let cancelStorage:Int?
        init(depth:Int = 32,work:Int = 8_388_608,storageBytes:Int = 400_000_000,
            cancelAt:Int? = nil,cancelWork:Int? = nil,cancelStorage:Int? = nil) throws {
            ledger = .init(limits:try .init(work:work,storageBytes:storageBytes,valueDepth:depth,coefficientDepth:depth))
            self.cancelAt=cancelAt;self.cancelWork=cancelWork;self.cancelStorage=cancelStorage
        }
        mutating func checkpoint() throws(ExactScalarFailure) {
            checkpoints += 1
            if checkpoints == cancelAt { throw .cancelled }
            if let cancelWork,ledger.work >= cancelWork { throw .cancelled }
            if let cancelStorage,ledger.storageBytes >= cancelStorage { throw .cancelled }
            try ledger.checkpoint()
        }
        mutating func consumeWork(_ n:Int) throws(ExactScalarFailure) { try ledger.consumeWork(n) }
        mutating func retainStorage(bytes:Int) throws(ExactScalarFailure) { try ledger.retainStorage(bytes:bytes) }
        mutating func visitCell(axis:ExactScalarRootAxis,depth:Int) throws(ExactScalarFailure) { try ledger.visitCell(axis:axis,depth:depth) }
        mutating func admitDepth(value:Int,coefficient:Int) throws(ExactScalarFailure) { try ledger.admitDepth(value:value,coefficient:coefficient) }
    }
    struct Failure:Error { let line:Int }
    static func require(_ value:Bool,line:Int = #line) throws { if !value { throw Failure(line:line) } }
    static func marker(_ text:StaticString) { print(text);fflush(nil) }
    static func logCount(_ label:StaticString,_ value:Int) {
        print(label,terminator:": ")
        var divisor=1
        while divisor <= value / 10 { divisor *= 10 }
        repeat { putchar(Int32(48 + value / divisor % 10));divisor /= 10 } while divisor > 0
        putchar(10);fflush(nil)
    }
    static func environmentCount(work:Bool,fallback:Int) -> Int {
        let pointer=work ? getenv("CAD_QUERY_WORK"):getenv("CAD_QUERY_STORAGE")
        guard let pointer,let count=Int(String(cString:pointer)) else { return fallback };return count
    }
    static func parent(using a:inout Admission) throws -> RuledSurface3D {
        try ExactScalarNumericAccess.withAdmission(&a) { usage in
            func guide(_ z:Double) throws -> Curve3D {
                let vertices:[Point3D] = [.init(x:0,y:0,z:z),.init(x:1,y:0,z:z),.init(x:0,y:1,z:z),.init(x:0,y:0,z:z)]
                var spans:[OriginalCurveRootSpan3D] = []
                for i in 0..<3 {
                    let native = Curve3D.bSpline(.init(degree:1,knots:[0,0,1,1],controlPoints:[vertices[i],vertices[i+1]],weights:[1,1]))
                    spans.append(try .init(source:native,start:.authored(0),end:.authored(1),nativeSpanIndex:1,
                        maximumParameterWidth:ModelingTolerance.standard.relative,maximumSubdivisionDepth:0,tolerance:.standard,
                        storageByteStride:MemoryLayout<UInt32>.stride,usage:&usage,maximumSpanCount:4,remainingSourceDepth:0,maximumAlgebraicDepth:0))
                }
                let quarter = try ExactRationalCoefficient.one.divided(by:.originalDouble(4,usage:&usage),usage:&usage)
                let threeQuarters = try quarter.multiplied(by:.originalDouble(3,usage:&usage),usage:&usage)
                return .originalGuideTraversalChain(try .init(traversals:spans,stations:[.zero,quarter,threeQuarters,.one],
                    sourceSegmentOrdinals:[0,1,2],remainingSourceDepth:2,tolerance:.standard,usage:&usage))
            }
            return RuledSurface3D(startBoundary:try guide(0),endBoundary:try guide(1),uDomain:.closed(0,1))
        }.value
    }
    static func source(using a:inout Admission) throws -> (OriginalSourceBinding<S>,F,OriginalDomainIdentityLimits,[Law]) {
        let original = try parent(using:&a)
        marker("PASS actual closed-guide and ruled constructors")
        let f = try F(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
        let limits = try OriginalDomainIdentityLimits(source:.init(remainingSourceDepth:3),maximumTransportDepth:32,
            maximumCharts:16,maximumFamilies:2,maximumIdentityProofs:8)
        let guide = CallerAdapters.OriginalRetainedGuideCurveSnapshotProvider(field:f,tolerance:.standard)
        let binding = try DefaultOriginalSourceBindingIssuer(provider:RuledObservationAdapters.OriginalRuledSurfaceSnapshotProvider(first:guide,second:guide,tolerance:.standard))
            .bind(original,limits:limits.source,using:&a)
        try require(binding.sourceDepth == 3 && binding.original.original == original)
        let first = try DefaultOriginalFiniteRetainedCurveChartPreparer<G>().prepare(source:binding.original.firstBoundary,
            maximumCharts:4,limits:.init(remainingSourceDepth:2),using:&a)
        let second = try DefaultOriginalFiniteRetainedCurveChartPreparer<G>().prepare(source:binding.original.secondBoundary,
            maximumCharts:4,limits:.init(remainingSourceDepth:2),using:&a)
        try require(first.laws.count == 3 && second.laws.count == 3)
        for family in [first,second] {
            for law in family.laws { try require(family.source.owns(law.chart)) }
        }
        let laws = try DefaultOriginalFiniteRuledChartPreparer<S,Int,Int,F>().prepare(source:binding,first:first.laws,
            second:second.laws,field:f,maximumCharts:16,limits:limits.source,using:&a)
        try require(laws.count == 7)
        for law in laws {
            try require(binding.owns(law.chart) && binding.original.firstBoundary.owns(law.chart.selection.first.chart)
                && binding.original.secondBoundary.owns(law.chart.selection.second.chart))
            let r = law.polynomials,u = try r.variable(0,using:&a),v = try r.variable(1,using:&a)
            let one = try r.constant(f.integer(1,using:&a),using:&a),zero = try r.constant(f.integer(0,using:&a),using:&a)
            // Independent triangle vertex/station oracle, never used to issue a source law.
            func xy(_ piece:Int) throws -> [ExactPolynomial<F>] {
                if piece == 0 { return [try r.scaled(u,by:f.integer(4,using:&a),using:&a),zero] }
                if piece == 1 {
                    let twoU = try r.scaled(u,by:f.integer(2,using:&a),using:&a)
                    let half = try r.constant(f.dividing(f.integer(1,using:&a),f.integer(2,using:&a),using:&a),using:&a)
                    return [try r.subtracting(r.scaled(half,by:f.integer(3,using:&a),using:&a),twoU,using:&a),try r.subtracting(twoU,half,using:&a)]
                }
                return [zero,try r.subtracting(r.constant(f.integer(4,using:&a),using:&a),r.scaled(u,by:f.integer(4,using:&a),using:&a),using:&a)]
            }
            let left = try xy(law.chart.selection.first.chart.selection),right = try xy(law.chart.selection.second.chart.selection)
            for axis in 0..<2 {
                let expected = try r.adding(r.multiplying(r.subtracting(one,v,using:&a),left[axis],using:&a),r.multiplying(v,right[axis],using:&a),using:&a)
                try require(r.equals(law.homogeneous[axis],expected,using:&a))
            }
            try require(r.equals(law.homogeneous[2],v,using:&a) && r.equals(law.homogeneous[3],one,using:&a))
            for (axis,p) in [u,v].enumerated() {
                try require(r.equals(law.parameterTransport.numerators[axis],p,using:&a)
                    && r.equals(law.parameterTransport.denominators[axis],one,using:&a))
            }
        }
        marker("PASS depth3 single parent, two retained depth2 guides, all seven closed ruled laws and exact authored UV/XYZ")
        return (binding,f,limits,laws)
    }
    static func simplifierControls() throws {
        var a = try Admission()
        let f = try F(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
        let field = try PublicLiftPlane.ExactAlgebraicScalarDomain.base(field:f,maximumExtensionLevel:32,using:&a)
        let cells = try Cells(field:field,variableCount:1,using:&a),ring=cells.polynomials
        let zero = try field.integer(0,using:&a),one = try field.integer(1,using:&a)
        let roots = try ExactRealRootDomain(field:field,using:&a)
        let unit = try roots.domain(lower:.finite(zero),upper:.finite(one),using:&a)
        let x = try ring.variable(0,using:&a),c0=try ring.constant(zero,using:&a),c1=try ring.constant(one,using:&a)
        func simplify(_ law:ExactPolynomial<PublicLiftPlane.ExactAlgebraicScalarDomain<F>>,
            _ relation:ExactRealCellSignRelation,_ domain:ExactRealRootInterval<PublicLiftPlane.ExactAlgebraicScalarDomain<F>.Value>,
            _ prefix:[ExactRealCellInstruction] = [],_ suffix:[ExactRealCellInstruction] = []) throws -> GuideSeamPort.OriginalIssuedGraphSelfPredicateSimplifier.Result {
            let source=try cells.bind(polynomials:[law],domains:[domain],using:&a)
            let predicate=try cells.predicate(instructions:prefix+[.sign(polynomial:0,relation:relation)]+suffix,for:source,using:&a)
            return try GuideSeamPort.OriginalIssuedGraphSelfPredicateSimplifier.simplify(predicate,cells:cells,using:&a)
        }
        func literal(_ result:GuideSeamPort.OriginalIssuedGraphSelfPredicateSimplifier.Result,_ value:Bool) throws {
            try require(result.predicate.source.polynomials.isEmpty && result.predicate.instructions.count == 1)
            guard case .literal(let actual)=result.predicate.instructions[0] else { throw Failure(line:#line) }
            try require(actual == value)
        }
        for (relation,value) in [(ExactRealCellSignRelation.equal,true),(.notEqual,false),(.less,false),(.lessOrEqual,true),(.greater,false),(.greaterOrEqual,true)] {
            try literal(simplify(c0,relation,unit),value)
        }
        let outside=try ring.subtracting(x,ring.constant(field.integer(2,using:&a),using:&a),using:&a)
        let positive=try ring.adding(x,c1,using:&a)
        let half=try field.dividing(one,field.integer(2,using:&a),using:&a)
        let straddling=try ring.subtracting(x,ring.constant(half,using:&a),using:&a)
        try literal(simplify(outside,.less,unit),true)
        try literal(simplify(positive,.greater,unit),true)
        try literal(simplify(ring.subtracting(c1,x,using:&a),.greaterOrEqual,unit),true)
        try require(simplify(straddling,.equal,unit).predicate.source.polynomials.count == 1)
        let open=try roots.domain(lower:.finite(zero),upper:.finite(one),includesLower:false,using:&a)
        try require(simplify(x,.greater,open).predicate.source.polynomials.count == 1)
        let singleton=try roots.domain(lower:.finite(zero),upper:.finite(zero),using:&a)
        try literal(simplify(x,.equal,singleton),true)
        let unbounded=try roots.domain(lower:.negativeInfinity,upper:.positiveInfinity,using:&a)
        try require(simplify(positive,.greater,unbounded).predicate.source.polynomials.count == 1)
        let nonlinear=try ring.adding(ring.multiplying(x,x,using:&a),c1,using:&a)
        try require(simplify(nonlinear,.greater,unit).predicate.source.polynomials.count == 1)
        try literal(simplify(positive,.notEqual,unit),true)
        try require(simplify(x,.notEqual,unit).predicate.source.polynomials.count == 1)
        try literal(simplify(nonlinear,.greater,unit,[.literal(false)],[.and]),false)
        try literal(simplify(nonlinear,.greater,unit,[.literal(true)],[.or]),true)
        // Conservative injected history strengthens only depth; the rational law remains identical.
        let history=ExactPolynomial(context:c1.context,terms:c1.terms,depth:try .init(value:9,coefficient:7))
        let pruned=try simplify(history,.greater,unit)
        try literal(pruned,true);try require(pruned.depth.value >= 9 && pruned.depth.coefficient >= 7)
        marker("PASS exact constant/affine enclosures, singleton/open/unbounded/nonlinear guards, Boolean pruning and conservative history")
    }
    static func observe() throws {
        var a = try Admission()
        let (source,f,limits,laws) = try source(using:&a)
        let zero = try f.integer(0,using:&a),one = try f.integer(1,using:&a)
        let unit = try ExactParameterInterval.checked(field:f,lower:.finite(zero),upper:.finite(one),depth:.zero,using:&a)
        let frame = try DefaultOriginalParameterTransporter<S,F>().frame(source:source,field:f,support:[[unit],[unit]],
            semantics:[.authoredScalar,.authoredScalar],limits:limits,using:&a)
        let request = try frame.fullSelection(limits:limits,using:&a)
        let cover = try DefaultOriginalIssuedDomainBinder<S,Q,F>().bind(laws:laws,request:request,limits:limits,using:&a)
        let field = try PublicLiftPlane.ExactAlgebraicScalarDomain.base(field:f,maximumExtensionLevel:32,using:&a)
        let family = try GuideSeamPort.DefaultOriginalRationalGraphFamilyPreparer<S,Q>().prepare(cover:cover,field:field,
            maximumGraphs:16,limits:limits,using:&a)
        try require(family.graphs.count == 7 && family.parameterCount == 2 && family.source.owner === source.owner)
        var ranges:[[Double]] = []
        let stations = [0.0,0.25,0.75,1.0]
        for graph in family.graphs {
            let law = graph.original.graph
            try require(law.layout.variableCount == 2 && law.layout.auxiliaries.isEmpty && law.support.count == 2)
            var interval:[Double] = []
            for end in [law.support[0].lower,law.support[0].upper] {
                var found:Double?
                for t in stations { if try f.compare(end,f.binary64(exactly:t,using:&a),using:&a) == .equal { found=t } }
                guard let found else { throw Failure(line:#line) };interval.append(found)
            }
            ranges.append(interval)
        }
        marker("PASS complete fullUV issued cover and seven two-axis original graphs")
        let raw:Raw = try GuideSeamPort.DefaultOriginalIssuedGraphRelationResolver().resolve(kind:.surfaceSurface,
            first:family,second:family,maximumPairs:256,limits:limits,
            cellLimits:.init(maximumStoredCells:20_000,maximumRootsPerStack:100),
            topologyLimits:.init(maximumGeneratedCells:20_000,maximumRootsPerStack:100,maximumClosures:20_000,
                maximumAttachmentPieces:100_000,maximumComponents:1_000),using:&a)
        try require(raw.pairs.count == 49 && raw.first.source.owner === raw.second.source.owner)
        marker("PASS complete ordered raw self product, 49 original chart pairs")
        let classes=[0,1,1,3,4,4,6]
        var canonicalPairs=0
        for ordinal in raw.pairs.indices {
            let pair=raw.pairs[ordinal],i=ordinal/7,j=ordinal%7,ci=classes[i],cj=classes[j]
            try require(pair.firstGraphIndex == i && pair.secondGraphIndex == j
                && pair.canonicalFirstGraphIndex == ci && pair.canonicalSecondGraphIndex == cj)
            try require((pair.firstEquivalence != nil) == (i != ci) && (pair.secondEquivalence != nil) == (j != cj))
            let canonical=raw.pairs[ci*7+cj]
            try require(pair.relation.projection.original.partition.source.owner === canonical.relation.projection.original.partition.source.owner)
            try require(pair.sharesSolver(with:canonical))
            let legacy=GuideSeamPort.OriginalIssuedGraphRelationPair(firstGraphIndex:i,secondGraphIndex:j,
                relation:pair.relation,canonicalFirstGraphIndex:ci,canonicalSecondGraphIndex:cj)
            try require(!legacy.sharesSolver(with:pair) && !legacy.sharesSolver(with:legacy))
            if i == ci && j == cj { canonicalPairs += 1 }
        }
        try require(canonicalPairs == 25)
#if !hasFeature(Embedded)
        print("PASS 49 actual pair ordinals retain checked aliases of 25 canonical solver pairs; rawWork",a.ledger.work,"rawBytes",a.ledger.storageBytes);fflush(nil)
#endif

#if !hasFeature(Embedded)
        print("productionBeforeIdentity",a.ledger.work,a.ledger.storageBytes);fflush(nil)
#endif
        let point = try ExactParameterInterval.checked(field:f,lower:.finite(zero),upper:.finite(zero),depth:.zero,using:&a)
        let scope = try frame.selection(intervals:[[point],[unit]],limits:limits,using:&a)
        let declaration = GuideSeamPort.OriginalRationalSourceBoundaryDeclaration(left:laws[0],right:laws[6],leftAxis:0,rightAxis:0,leftSide:.lower,rightSide:.upper)
        let issuer = DefaultOriginalParameterIdentityIssuer<S,F>()
        let identity = try issuer.declaredBoundary(declaration:declaration,scope:scope,rightFrame:frame,
            permutation:[0,1],gains:[one,one],offsets:[one,zero],limits:limits,using:&a)
        marker("PASS actual law-bound directed whole seam under original ledger")
#if !hasFeature(Embedded)
        print("productionAfterIdentityBeforeSelf",a.ledger.work,a.ledger.storageBytes);fflush(nil)
#endif
        var query = try Admission()
#if !hasFeature(Embedded)
        print("preparedQueryBeforeSelf",query.ledger.work,query.ledger.storageBytes);fflush(nil)
#endif
        let result = try GuideSeamPort.DefaultOriginalIssuedGraphSelfContactQuery().contacts(in:raw,excluding:[identity],
            domainLimits:limits,cellLimits:.init(maximumStoredCells:20_000,maximumRootsPerStack:100),
            topologyLimits:.init(maximumGeneratedCells:20_000,maximumRootsPerStack:100,maximumClosures:20_000,
                maximumAttachmentPieces:100_000,maximumComponents:1_000),using:&query)
#if !hasFeature(Embedded)
        print("preparedQueryAfterSelf",query.ledger.work,query.ledger.storageBytes);fflush(nil)
#endif
        logCount("QUERY_WORK",query.ledger.work);logCount("QUERY_STORAGE",query.ledger.storageBytes)
        var verification = try Admission()
        try raw.admitProof(limits:limits,using:&verification)
        var nonempty = 0
        for pair in raw.pairs {
            let selected = pair.relation.projection.original,partition = selected.partition
            try require(partition.source.variableCount == 4 && pair.relation.original.firstCoordinates == [0,1]
                && pair.relation.original.secondCoordinates == [2,3])
            let cells = try Cells(retaining:partition.source,using:&verification),r = cells.polynomials
            let first = ranges[pair.firstGraphIndex],second = ranges[pair.secondGraphIndex]
            func cut(_ axis:Int,_ value:Double) throws -> ExactRealCellSignInvariant<F> {
                let p = try r.subtracting(r.variable(axis,using:&verification),r.constant(r.field.importingBase(f.binary64(exactly:value,using:&verification),using:&verification),using:&verification),using:&verification)
                guard let result = try cells.signInvariant(for:p,in:partition,using:&verification) else { throw Failure(line:#line) };return result
            }
            let bounds = try [cut(0,first[0]),cut(0,first[1]),cut(2,second[0]),cut(2,second[1])]
            let v = try r.subtracting(r.variable(1,using:&verification),r.variable(3,using:&verification),using:&verification)
            guard let vs = try cells.signInvariant(for:v,in:partition,using:&verification) else { throw Failure(line:#line) }
            let lo = max(first[0],second[0]),hi = min(first[1],second[1])
            var diagonal:ExactRealCellSignInvariant<F>?
            var atJoin:[ExactRealCellSignInvariant<F>] = []
            if lo < hi {
                let p = try r.subtracting(r.variable(0,using:&verification),r.variable(2,using:&verification),using:&verification)
                guard let found = try cells.signInvariant(for:p,in:partition,using:&verification) else { throw Failure(line:#line) };diagonal=found
            } else if lo == hi { atJoin = try [cut(0,lo),cut(2,lo)] }
            var forward:[ExactRealCellSignInvariant<F>] = [],reverse:[ExactRealCellSignInvariant<F>] = []
            if first[0] == 0 && second[1] == 1 { forward = try [cut(0,0),cut(2,1)] }
            if first[1] == 1 && second[0] == 0 { reverse = try [cut(0,1),cut(2,0)] }
            var count = 0
            for cell in partition.cells where cell.axis == 3 {
                func vanishes(_ cuts:[ExactRealCellSignInvariant<F>]) throws -> Bool {
                    if cuts.isEmpty { return false }
                    for cut in cuts { if try cells.sign(of:cut,at:cell,using:&verification) != .zero { return false } };return true
                }
                var inside = true
                for (i,b) in bounds.enumerated() {
                    let sign = try cells.sign(of:b,at:cell,using:&verification)
                    if i % 2 == 0 ? sign == .negative:sign == .positive { inside=false }
                }
                let authored = try diagonal.map { try cells.sign(of:$0,at:cell,using:&verification) == .zero } ?? vanishes(atJoin)
                let expected = try inside && cells.sign(of:vs,at:cell,using:&verification) == .zero
                    && (authored || vanishes(forward) || vanishes(reverse))
                try require(selected.cells.contains(cell) == expected)
                if selected.cells.contains(cell) { count += 1 }
            }
            if count > 0 { nonempty += 1 }
        }
#if !hasFeature(Embedded)
        print("nonemptyRawPairs",nonempty)
#endif
        marker("PASS every full raw cell equals authored diagonal plus both directed whole endpoint seams")
        try require(result.raw.pairs.count == 49 && result.refinements.count == 49 && result.authoredDiagonals.count == 49)
        var residualPairs=0,reusedRefinements=0
        for ordinal in result.refinements.indices {
            let refined=result.refinements[ordinal],pullback=refined.pullback
            if let proof=refined.predicateEquivalence {
                reusedRefinements += 1
                try proof.admitProof(using:&verification)
                let pair=raw.pairs[ordinal]
                let previous=result.refinements.indices.first { $0 < ordinal
                    && pair.sharesSolver(with:raw.pairs[$0])
                    && pullback.region.partition.source.owner === result.refinements[$0].pullback.region.partition.source.owner }
                try require(previous != nil)
            }
            try require(refined.pairOrdinal == ordinal && pullback.coordinateMap == [0,1,2,3])
            let original=raw.pairs[ordinal].relation.projection.original.cells
            try require(pullback.source.cells.count == original.count)
            for index in original.indices { try require(pullback.source.cells[index] == original[index]) }
            let region=pullback.region
            try require(region.coordinateCount == 4 && region.cells.count == region.included.count
                && pullback.sourceCellOrdinals.count == region.cells.count)
            var terminalOrdinal=0
            for cell in region.partition.cells where cell.axis == 3 {
                try require(terminalOrdinal < region.cells.count && region.cells[terminalOrdinal] == cell)
                terminalOrdinal += 1
            }
            try require(terminalOrdinal == region.cells.count)
            if ordinal == 42 {
                let cells=try Cells(retaining:region.partition.source,using:&verification),ring=cells.polynomials
                func cut(_ axis:Int,_ value:Int) throws -> ExactRealCellSignInvariant<F> {
                    let law=try ring.subtracting(ring.variable(axis,using:&verification),ring.constant(ring.field.integer(value,using:&verification),using:&verification),using:&verification)
                    guard let proof=try cells.signInvariant(for:law,in:region.partition,using:&verification) else { throw Failure(line:#line) };return proof
                }
                let u0=try cut(0,1),u1=try cut(2,0)
                let v00=try cut(1,0),v01=try cut(1,1),v10=try cut(3,0),v11=try cut(3,1)
                let v=try ring.subtracting(ring.variable(1,using:&verification),ring.variable(3,using:&verification),using:&verification)
                guard let vs=try cells.signInvariant(for:v,in:region.partition,using:&verification) else { throw Failure(line:#line) }
                for i in region.cells.indices {
                    let cell=region.cells[i]
                    let expected=try cells.sign(of:u0,at:cell,using:&verification) == .zero
                        && cells.sign(of:u1,at:cell,using:&verification) == .zero
                        && cells.sign(of:vs,at:cell,using:&verification) == .zero
                        && cells.sign(of:v00,at:cell,using:&verification) != .negative
                        && cells.sign(of:v01,at:cell,using:&verification) != .positive
                        && cells.sign(of:v10,at:cell,using:&verification) != .negative
                        && cells.sign(of:v11,at:cell,using:&verification) != .positive
                    try require(region.included[i] == expected)
                    if expected { try require(pullback.sourceCellOrdinals[i] >= 0 && pullback.sourceCellOrdinals[i] < original.count) }
                    else { try require(pullback.sourceCellOrdinals[i] == -1) }
                }
            }
            if pullback.region.included.contains(true) {
                residualPairs += 1
                try require(ordinal == 42)
            } else {
                for sourceOrdinal in pullback.sourceCellOrdinals { try require(sourceOrdinal == -1) }
            }
        }
        try require(residualPairs == 1 && reusedRefinements > 0)
#if !hasFeature(Embedded)
        print("reusedRefinements",reusedRefinements);fflush(nil)
#endif
        func contains(_ ordinal:Int,_ tuple:[Double]) throws -> Bool {
            var reader=try Admission()
            var values:[PublicLiftPlane.ExactAlgebraicScalarDomain<F>.Value]=[]
            for value in tuple { values.append(try field.importingBase(f.binary64(exactly:value,using:&reader),using:&reader)) }
            return try result.contains(pairOrdinal:ordinal,liftedCoordinates:values,queryField:field,
                domainLimits:limits,rootLimits:.init(maximumRoots:100),using:&reader)
        }
        try require(contains(42,[1,0.5,0,0.5]))
        try require(!contains(6,[0,0.5,1,0.5]))
        try require(!contains(0,[0.125,0.5,0.125,0.5]))
        try require(!contains(42,[1,0.5,0,0.25]))
        try require(!contains(42,[1,-0.25,0,-0.25]))
        try require(!contains(42,[1,1.25,0,1.25]))
        marker("PASS reverse membership and forward/diagonal/wrongV/outside-authored-V refusal")
        // Inject conservative source-proof history while retaining the actual equations and owners.
        func historyLaw(_ law:Law) throws -> Law {
            .init(chart:law.chart,field:law.field,polynomials:law.polynomials,homogeneous:law.homogeneous,
                support:law.support,parameterTransport:law.parameterTransport,periods:law.periods,
                proofDepth:try .init(value:9,coefficient:7))
        }
        let historyDeclaration=GuideSeamPort.OriginalRationalSourceBoundaryDeclaration(left:try historyLaw(laws[0]),
            right:try historyLaw(laws[6]),leftAxis:0,rightAxis:0,leftSide:.lower,rightSide:.upper)
        let historyIdentity=try issuer.declaredBoundary(declaration:historyDeclaration,scope:scope,rightFrame:frame,
            permutation:[0,1],gains:[one,one],offsets:[one,zero],limits:limits,using:&verification)
        let historyView=try issuer.relation(of:historyIdentity,limits:limits,using:&verification)
        let historyDiagonal=try issuer.relation(of:result.authoredDiagonals[0],limits:limits,using:&verification)
        var historyCompiler=try GuideSeamPort.OriginalIssuedGraphSelfIdentityCompiler(raw.pairs[0].relation.projection.original,using:&verification)
        let historyPredicate=try historyCompiler.residual(first:family.graphs[0],second:family.graphs[0],
            firstPlacement:[0,1],secondPlacement:[2,3],diagonal:historyDiagonal,identities:[historyView],using:&verification)
        guard let decisionDepth=historyCompiler.predicateDecisionDepth else { throw Failure(line:#line) }
        try require(decisionDepth.value >= 9 && decisionDepth.coefficient >= 7)
        try require(historyPredicate.depth.value < decisionDepth.value)
        let historyRefinement=GuideSeamPort.OriginalIssuedGraphParameterRefinement(raw:raw,pairOrdinal:0,
            pullback:result.refinements[0].pullback,predicateDecisionDepth:decisionDepth)
        try require(!historyRefinement.pullback.region.included.contains(true))
        var shallow=try Admission(depth:8)
        try raw.admitProof(limits:limits,using:&shallow)
        let coordinates=try [field.integer(0,using:&verification),field.integer(0,using:&verification),
            field.integer(0,using:&verification),field.integer(0,using:&verification)]
        do {
            _=try historyRefinement.contains(liftedCoordinates:coordinates,queryField:field,limits:limits,
                rootLimits:.init(maximumRoots:100),using:&shallow)
            throw Failure(line:#line)
        } catch GuideSeamPort.NativeExactRelationFailure.scalar(.resourceLimit(.valueDepth)) {
        } catch GuideSeamPort.NativeExactRelationFailure.scalar(.resourceLimit(.coefficientDepth)) {}
        marker("PASS pruned actual forward seam retains injected history9 and rejects later depth8 empty membership")
        let pair=raw.pairs[6],firstGraph=family.graphs[0],secondGraph=family.graphs[6]
        let diagonal=try issuer.relation(of:result.authoredDiagonals[6],limits:limits,using:&verification)
        let seam=try issuer.relation(of:identity,limits:limits,using:&verification)
        func compiled(_ placements:[Int],_ identities:[OriginalParameterIdentityRelation<S,F>]) throws -> ExactRealCellPredicate<F> {
            var compiler=try GuideSeamPort.OriginalIssuedGraphSelfIdentityCompiler(pair.relation.projection.original,using:&verification)
            return try compiler.residual(first:firstGraph,second:secondGraph,firstPlacement:placements,secondPlacement:[2,3],
                diagonal:diagonal,identities:identities,using:&verification)
        }
        let baseline=try compiled([0,1],[seam])
        let moved=try compiled([1,0],[seam]),differentScope=try compiled([0,1],[])
        try require(GuideSeamPort.OriginalIssuedGraphPredicateEquivalence.checked(baseline,baseline,field:field,using:&verification) != nil)
        try require(GuideSeamPort.OriginalIssuedGraphPredicateEquivalence.checked(baseline,moved,field:field,using:&verification) == nil)
        try require(GuideSeamPort.OriginalIssuedGraphPredicateEquivalence.checked(baseline,differentScope,field:field,using:&verification) == nil)
        let comparisonCells=try Cells(retaining:baseline.source,using:&verification),ring=comparisonCells.polynomials
        func altered(_ laws:[ExactPolynomial<PublicLiftPlane.ExactAlgebraicScalarDomain<F>>],
            _ instructions:[ExactRealCellInstruction],_ domains:[ExactRealRootInterval<PublicLiftPlane.ExactAlgebraicScalarDomain<F>.Value>]) throws -> ExactRealCellPredicate<F> {
            let source=try comparisonCells.bind(polynomials:laws,domains:domains,using:&verification)
            return try comparisonCells.predicate(instructions:instructions,for:source,using:&verification)
        }
        let guardChanged=try altered(baseline.source.polynomials,baseline.instructions+[.not],baseline.source.domains)
        try require(GuideSeamPort.OriginalIssuedGraphPredicateEquivalence.checked(baseline,guardChanged,field:field,using:&verification) == nil)
        var coefficients=baseline.source.polynomials
        try require(!coefficients.isEmpty)
        coefficients[0]=try ring.adding(coefficients[0],ring.constant(field.importingBase(f.binary64(exactly:Double.ulpOfOne,using:&verification),using:&verification),using:&verification),using:&verification)
        let coefficientChanged=try altered(coefficients,baseline.instructions,baseline.source.domains)
        try require(GuideSeamPort.OriginalIssuedGraphPredicateEquivalence.checked(baseline,coefficientChanged,field:field,using:&verification) == nil)
        let roots=try ExactRealRootDomain(field:field,using:&verification)
        var domains=baseline.source.domains
        domains[0]=try roots.domain(lower:domains[0].lower,upper:domains[0].upper,includesLower:false,using:&verification)
        let domainChanged=try altered(baseline.source.polynomials,baseline.instructions,domains)
        try require(GuideSeamPort.OriginalIssuedGraphPredicateEquivalence.checked(baseline,domainChanged,field:field,using:&verification) == nil)
        marker("PASS sealed-owner nil refusal and full predicate transport/scope/guard/near-coefficient/closure nonreuse")
#if !hasFeature(Embedded)
        print("PASS separate explicit raw and prepared-query operations; reverse seam sole residual pair; preparationWork",a.ledger.work,"totalBytes",a.ledger.storageBytes);fflush(nil)
#endif
#if !hasFeature(Embedded)
        print("verificationOnlyWork",verification.ledger.work,"verificationOnlyBytes",verification.ledger.storageBytes);fflush(nil)
#endif

    }
    typealias Result=GuideSeamPort.OriginalIssuedGraphSelfContacts<S,Law,Cover,Law,Cover>
    typealias Field=PublicLiftPlane.ExactAlgebraicScalarDomain<F>
    struct Prepared {
        let raw:Raw
        let identity:OriginalParameterIdentity<S,F>
        let field:Field
        let limits:OriginalDomainIdentityLimits
    }
    static func prepared() throws -> Prepared {
        var a=try Admission()
        let (source,f,limits,laws)=try source(using:&a)
        let zero=try f.integer(0,using:&a),one=try f.integer(1,using:&a)
        let unit=try ExactParameterInterval.checked(field:f,lower:.finite(zero),upper:.finite(one),depth:.zero,using:&a)
        let frame=try DefaultOriginalParameterTransporter<S,F>().frame(source:source,field:f,support:[[unit],[unit]],
            semantics:[.authoredScalar,.authoredScalar],limits:limits,using:&a)
        let cover=try DefaultOriginalIssuedDomainBinder<S,Q,F>().bind(laws:laws,request:frame.fullSelection(limits:limits,using:&a),limits:limits,using:&a)
        let field=try Field.base(field:f,maximumExtensionLevel:32,using:&a)
        let family=try GuideSeamPort.DefaultOriginalRationalGraphFamilyPreparer<S,Q>().prepare(cover:cover,field:field,maximumGraphs:16,limits:limits,using:&a)
        let raw:Raw=try GuideSeamPort.DefaultOriginalIssuedGraphRelationResolver().resolve(kind:.surfaceSurface,first:family,second:family,
            maximumPairs:49,limits:limits,cellLimits:.init(maximumStoredCells:20_000,maximumRootsPerStack:100),
            topologyLimits:.init(maximumGeneratedCells:20_000,maximumRootsPerStack:100,maximumClosures:20_000,
                maximumAttachmentPieces:100_000,maximumComponents:1_000),using:&a)
        let point=try ExactParameterInterval.checked(field:f,lower:.finite(zero),upper:.finite(zero),depth:.zero,using:&a)
        let scope=try frame.selection(intervals:[[point],[unit]],limits:limits,using:&a)
        let declaration=GuideSeamPort.OriginalRationalSourceBoundaryDeclaration(left:laws[0],right:laws[6],leftAxis:0,rightAxis:0,leftSide:.lower,rightSide:.upper)
        let identity=try DefaultOriginalParameterIdentityIssuer<S,F>().declaredBoundary(declaration:declaration,scope:scope,rightFrame:frame,
            permutation:[0,1],gains:[one,one],offsets:[one,zero],limits:limits,using:&a)
        return Prepared(raw:raw,identity:identity,field:field,limits:limits)
    }
    static func query(_ p:Prepared,using a:inout Admission) throws -> Result {
        try GuideSeamPort.DefaultOriginalIssuedGraphSelfContactQuery().contacts(in:p.raw,excluding:[p.identity],domainLimits:p.limits,
            cellLimits:.init(maximumStoredCells:20_000,maximumRootsPerStack:100),
            topologyLimits:.init(maximumGeneratedCells:20_000,maximumRootsPerStack:100,maximumClosures:20_000,
                maximumAttachmentPieces:100_000,maximumComponents:1_000),using:&a)
    }
    // Read typed failure wrappers without interpreting a message or dynamic type name.
    static func scalarCause(_ error:any Error) -> ExactScalarFailure? {
        if let e=error as? ExactScalarFailure { if case .admissionRejected(let cause)=e { return scalarCause(cause) };return e }
        if let e=error as? GuideSeamPort.NativeExactRelationFailure {
            switch e { case .scalar(let e):return e;case .cell(let e):return scalarCause(e)
            case .root(let e):return scalarCause(e);case .relation(let e):return scalarCause(e)
            case .geometry(let e):return scalarCause(e);case .domain(let e):return scalarCause(e)
            case .source(let e):return scalarCause(e);default:return nil }
        }
        if let e=error as? OriginalDomainIdentityFailure {
            switch e { case .scalar(let e):return scalarCause(e);case .source(let e):return scalarCause(e)
            case .polynomial(let e):return scalarCause(e);case .operationRejected(let e):return scalarCause(e);default:return nil }
        }
        if let e=error as? OriginalSourceIssuanceFailure {
            switch e { case .scalar(let e):return scalarCause(e);case .polynomial(let e):return scalarCause(e)
            case .sourceRejected(let e):return scalarCause(e);default:return nil }
        }
        if let e=error as? ExactRealCellFailure {
            switch e { case .scalar(let e):return e;case .root(let e):return scalarCause(e)
            case .polynomial(let e):return scalarCause(e);case .operationRejected(let e):return scalarCause(e);default:return nil }
        }
        if let e=error as? ExactRealTopologyFailure {
            switch e { case .scalar(let e):return e;case .cell(let e):return scalarCause(e)
            case .root(let e):return scalarCause(e);case .polynomial(let e):return scalarCause(e)
            case .operationRejected(let e):return scalarCause(e);default:return nil }
        }
        if let e=error as? ExactParametricRelationFailure {
            switch e { case .scalar(let e):return e;case .cell(let e):return scalarCause(e)
            case .topology(let e):return scalarCause(e);case .polynomial(let e):return scalarCause(e)
            case .operationRejected(let e):return scalarCause(e);default:return nil }
        }
        if let e=error as? ExactRealRootFailure {
            switch e { case .scalar(let e):return e;case .polynomial(let e):return scalarCause(e)
            case .operationRejected(let e):return scalarCause(e);default:return nil }
        }
        if let e=error as? ExactPolynomialFailure {
            switch e { case .scalar(let e):return e;case .operationRejected(let e):return scalarCause(e);default:return nil }
        }
        return nil
    }
    static func graphControls() throws {
        let p=try prepared(),actual=p.raw.first.graphs[1]
        var a=try Admission()
        let cells=try Cells(retaining:actual.graph.predicate.source,using:&a),ring=cells.polynomials
        let domain=PublicLiftPlane.ExactParametricRelationDomain<F,Cells,PublicLiftPlane.ExactRealTopology<F>>(
            cells:Cells.self,topology:.init(cells:Cells.self))
        func changed(_ laws:[ExactPolynomial<Field>],_ program:[ExactRealCellInstruction],
            _ intervals:[ExactRealRootInterval<Field.Value>],parameters:Int=2) throws -> GuideSeamPort.OriginalIssuedGraphPreparation<S,Law> {
            let source=try cells.bind(polynomials:laws,domains:intervals,using:&a)
            let predicate=try cells.predicate(instructions:program,for:source,using:&a)
            return .init(original:actual.original,graph:try domain.graph(from:predicate,parameterCount:parameters,using:&a),field:p.field,depth:actual.depth)
        }
        let predicate=actual.graph.predicate
        try require(GuideSeamPort.OriginalIssuedGraphSolverEquivalence.checked(actual,actual,using:&a) != nil)
        var laws=predicate.source.polynomials
        laws[0]=try ring.adding(laws[0],ring.constant(p.field.integer(1,using:&a),using:&a),using:&a)
        let coefficient=try changed(laws,predicate.instructions,predicate.source.domains)
        let guardChange=try changed(predicate.source.polynomials,predicate.instructions+[.not],predicate.source.domains)
        let roots=try ExactRealRootDomain(field:p.field,using:&a)
        var intervals=predicate.source.domains
        intervals[0]=try roots.domain(lower:intervals[0].lower,upper:intervals[0].upper,includesLower:false,using:&a)
        let support=try changed(predicate.source.polynomials,predicate.instructions,intervals)
        let count=try changed(predicate.source.polynomials,predicate.instructions,predicate.source.domains,parameters:1)
        for altered in [coefficient,guardChange,support,count] {
            try require(GuideSeamPort.OriginalIssuedGraphSolverEquivalence.checked(actual,altered,using:&a) == nil)
        }
        // Negative comparison-only metadata; never issue, solve or publish this altered receipt.
        let old=actual.original.graph
        let layout=try OriginalParametricVariableLayout.checked(variableCount:2,parameters:[1,0],auxiliaries:[],using:&a)
        let receipt=OriginalParametricGraphReceipt(source:old.source,evidence:old.evidence,field:old.field,polynomials:old.polynomials,
            homogeneous:old.homogeneous,support:old.support,includesUpperBoundary:old.includesUpperBoundary,layout:layout,
            conditions:old.conditions,parameterTransport:old.parameterTransport,proofDepth:old.proofDepth)
        let bound=OriginalDomainBoundParametricGraph(graph:receipt,request:actual.original.request,depth:actual.original.depth)
        let reordered=GuideSeamPort.OriginalIssuedGraphPreparation(original:bound,graph:actual.graph,field:p.field,depth:actual.depth)
        try require(GuideSeamPort.OriginalIssuedGraphSolverEquivalence.checked(actual,reordered,using:&a) == nil)
        let history=GuideSeamPort.OriginalIssuedGraphPreparation(original:actual.original,graph:actual.graph,field:p.field,
            depth:try .init(value:9,coefficient:7))
        guard let proof=try GuideSeamPort.OriginalIssuedGraphSolverEquivalence.checked(actual,history,using:&a) else { throw Failure(line:#line) }
        try require(proof.depth.value >= 9 && proof.depth.coefficient >= 7)
        var reader=try Admission(depth:8)
        do { try proof.admitProof(using:&reader);throw Failure(line:#line) }
        catch GuideSeamPort.NativeExactRelationFailure.scalar(.resourceLimit(.valueDepth)) {
        } catch GuideSeamPort.NativeExactRelationFailure.scalar(.resourceLimit(.coefficientDepth)) {}
        var countAdmission=try Admission()
        do {
            _=try GuideSeamPort.DefaultOriginalIssuedGraphRelationResolver().resolve(kind:.surfaceSurface,first:p.raw.first,second:p.raw.second,
                maximumPairs:48,limits:p.limits,cellLimits:.init(maximumStoredCells:20_000,maximumRootsPerStack:100),
                topologyLimits:.init(maximumGeneratedCells:20_000,maximumRootsPerStack:100,maximumClosures:20_000,maximumAttachmentPieces:100_000,maximumComponents:1_000),using:&countAdmission)
            throw Failure(line:#line)
        } catch GuideSeamPort.NativeExactRelationFailure.domain(.chartLimit) {}
        marker("PASS complete graph coefficient/guard/domain/layout/parameter-count nonreuse, raw pair limit49/48 and later alias history depth9/8")
    }
    static func emptyPublicationControls() throws {
        var a=try Admission()
        let (source,f,limits,laws)=try source(using:&a)
        let unit=try ExactParameterInterval.checked(field:f,lower:.finite(f.integer(0,using:&a)),upper:.finite(f.integer(1,using:&a)),depth:.zero,using:&a)
        let frame=try DefaultOriginalParameterTransporter<S,F>().frame(source:source,field:f,support:[[unit],[unit]],semantics:[.authoredScalar,.authoredScalar],limits:limits,using:&a)
        let empty=try frame.selection(intervals:[[],[]],limits:limits,using:&a)
        let cover=try DefaultOriginalIssuedDomainBinder<S,Q,F>().bind(laws:laws,request:empty,limits:limits,using:&a)
        let field=try Field.base(field:f,maximumExtensionLevel:32,using:&a)
        let family=try GuideSeamPort.DefaultOriginalRationalGraphFamilyPreparer<S,Q>().prepare(cover:cover,field:field,maximumGraphs:16,limits:limits,using:&a)
        try require(family.graphs.isEmpty)
        let raw:Raw=try GuideSeamPort.DefaultOriginalIssuedGraphRelationResolver().resolve(kind:.surfaceSurface,first:family,second:family,maximumPairs:0,limits:limits,
            cellLimits:.init(maximumStoredCells:20_000,maximumRootsPerStack:100),
            topologyLimits:.init(maximumGeneratedCells:20_000,maximumRootsPerStack:100,maximumClosures:20_000,maximumAttachmentPieces:100_000,maximumComponents:1_000),using:&a)
        func emptyQuery(_ admission:inout Admission) throws -> Result {
            try GuideSeamPort.DefaultOriginalIssuedGraphSelfContactQuery().contacts(in:raw,domainLimits:limits,
                cellLimits:.init(maximumStoredCells:20_000,maximumRootsPerStack:100),
                topologyLimits:.init(maximumGeneratedCells:20_000,maximumRootsPerStack:100,maximumClosures:20_000,maximumAttachmentPieces:100_000,maximumComponents:1_000),using:&admission)
        }
        var measured=try Admission()
        let result=try emptyQuery(&measured)
        try require(result.raw.pairs.isEmpty && result.refinements.isEmpty)
        var cancelled=try Admission(cancelStorage:measured.ledger.storageBytes)
        do { _=try emptyQuery(&cancelled);throw Failure(line:#line) }
        catch { guard case .cancelled?=scalarCause(error) else { throw error } }
        marker("PASS actual complete empty request and final empty-publication cancellation")
    }
    static func resourceControls(storage:Bool) throws {
        let p=try prepared()
        // These counts belong only to the normal successful v6/v7 frozen prepared query.
        let measuredWork=environmentCount(work:true,fallback:7_068_697)
        let measuredStorage=environmentCount(work:false,fallback:212_593_418)
        var exact=try Admission(work:storage ? 8_388_608:measuredWork,storageBytes:storage ? measuredStorage:400_000_000)
        let result=try query(p,using:&exact)
        try require(result.refinements.count == 49 && exact.ledger.work == measuredWork && exact.ledger.storageBytes == measuredStorage)
        var short=try Admission(work:storage ? 8_388_608:measuredWork-1,storageBytes:storage ? measuredStorage-1:400_000_000)
        do { _=try query(p,using:&short);throw Failure(line:#line) }
        catch {
            guard let cause=scalarCause(error) else { throw error }
            switch cause {
            case .resourceLimit(.work):try require(!storage)
            case .resourceLimit(.storage):try require(storage)
            default:throw error
            }
        }
        if !storage {
            for cap in [1,100_000] {
                var limited=try Admission(work:cap)
                do { _=try query(p,using:&limited);throw Failure(line:#line) }
                catch { guard case .resourceLimit(.work)?=scalarCause(error) else { throw error } }
            }
        }
        marker("PASS frozen prepared-query exact and one-less resource boundary")
    }
    static func cancellationControls(final:Bool) throws {
        let p=try prepared()
        let admissions:[(Int?,Int?,Int?)]=final ? [(nil,nil,environmentCount(work:false,fallback:212_593_418))]:[(1,nil,nil),(nil,100_000,nil)]
        for (entry,work,storage) in admissions {
            var a=try Admission(cancelAt:entry,cancelWork:work,cancelStorage:storage)
            do { _=try query(p,using:&a);throw Failure(line:#line) }
            catch { guard case .cancelled?=scalarCause(error) else { throw error } }
        }
        marker("PASS prepared-query entry/processing or final-publication cancellation")
    }
    static func lifetimeControls() throws {
        func detached() throws -> (Result,Field,OriginalDomainIdentityLimits) {
            let p=try prepared();var a=try Admission()
            return (try query(p,using:&a),p.field,p.limits)
        }
        let (result,field,limits)=try detached()
        var changed=result.refinements
        changed.removeAll()
        try require(changed.isEmpty && result.refinements.count == 49)
        var later=try Admission()
        let values=try [field.integer(1,using:&later),field.integer(0,using:&later),field.integer(0,using:&later),field.integer(0,using:&later)]
        try require(result.contains(pairOrdinal:42,liftedCoordinates:values,queryField:field,domainLimits:limits,rootLimits:.init(maximumRoots:100),using:&later))
        var cancelled=try Admission(cancelAt:1)
        do {
            _=try result.contains(pairOrdinal:42,liftedCoordinates:values,queryField:field,domainLimits:limits,rootLimits:.init(maximumRoots:100),using:&cancelled)
            throw Failure(line:#line)
        } catch { guard case .cancelled?=scalarCause(error) else { throw error } }
        let low=try OriginalDomainIdentityLimits(source:.init(remainingSourceDepth:2),maximumTransportDepth:32,maximumCharts:16,maximumFamilies:2,maximumIdentityProofs:8)
        var shallow=try Admission()
        do { try result.raw.admitProof(limits:low,using:&shallow);throw Failure(line:#line) }
        catch GuideSeamPort.NativeExactRelationFailure.domain(.sourceDepthLimit) {}
        marker("PASS detached prepared owners, COW result array, independent later admission/cancellation and source depth3/2")
    }
    static func main() {
        do {
            let group:String
#if hasFeature(Embedded)
            if let value=getenv("CAD_PROOF_GROUP") { group=String(cString:value) } else { group="oracle" }
#else
            group=CommandLine.arguments.count > 1 ? CommandLine.arguments[1]:"oracle"
#endif
            switch group {
            case "oracle":try simplifierControls();try observe()
            case "graphs":try graphControls()
            case "empty":try emptyPublicationControls()
            case "work":try resourceControls(storage:false)
            case "storage":try resourceControls(storage:true)
            case "cancel":try cancellationControls(final:false)
            case "cancel-final":try cancellationControls(final:true)
            case "lifetime":try lifetimeControls()
            case "identity":try LawBoundGuideSeamIdentity.run()
            case "coons":try GuideSeamCoonsRegression.run()
            default:throw Failure(line:#line)
            }
        } catch {
#if hasFeature(Embedded)
            marker("ACCEPTANCE_STOP")
#else
            print("ACCEPTANCE_STOP",error)
#endif
            exit(1)
        }
    }
}

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


import enum RetainedHostAdapters.OriginalDomainAccess
import class RetainedHostAdapters.OriginalIdentityReadmission
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#endif
@testable import CallerAdapters
@testable import RuledObservationAdapters
#if GUIDE_SEAM_COMBINED_ACCEPTANCE
import GuideSeamPort
#endif

/// Exercises the additive identity theorem without resolving a chart-pair product.
#if !GUIDE_SEAM_COMBINED_ACCEPTANCE
@main
#endif
struct LawBoundGuideSeamIdentity {
    typealias F = OriginalExactScalarDomain
    typealias G = CallerAdapters.OriginalRetainedGuideCurveSnapshot
    typealias S = RuledObservationAdapters.OriginalRuledSurfaceSnapshot<G,G>
    typealias Q = OriginalRuledChartSelection<G,Int,G,Int,F>
    typealias Law = OriginalRationalChartReceipt<S,Q,F>
    typealias Declaration = OriginalRationalSourceBoundaryDeclaration<S,Q,Q,F>
    struct Admission: ~Copyable, ExactScalarAdmission {
        var ledger: ExactScalarLedger
        var checkpoints = 0
        let cancelAt: Int?
        init(depth:Int = 32,work:Int = 8_388_608,storageBytes:Int = 400_000_000,cancelAt:Int? = nil) throws {
            ledger = .init(limits:try .init(work:work,storageBytes:storageBytes,valueDepth:depth,coefficientDepth:depth))
            self.cancelAt = cancelAt
        }
        mutating func checkpoint() throws(ExactScalarFailure) {
            checkpoints += 1
            if checkpoints == cancelAt { throw .cancelled }
            try ledger.checkpoint()
        }
        mutating func consumeWork(_ n:Int) throws(ExactScalarFailure) { try checkpoint();try ledger.consumeWork(n) }
        mutating func retainStorage(bytes:Int) throws(ExactScalarFailure) { try checkpoint();try ledger.retainStorage(bytes:bytes) }
        mutating func visitCell(axis:ExactScalarRootAxis,depth:Int) throws(ExactScalarFailure) { try checkpoint();try ledger.visitCell(axis:axis,depth:depth) }
        mutating func admitDepth(value:Int,coefficient:Int) throws(ExactScalarFailure) { try checkpoint();try ledger.admitDepth(value:value,coefficient:coefficient) }
    }
    struct Failure: Error { let line: Int }
    static func require(_ condition:Bool,line:Int = #line) throws { if !condition { throw Failure(line:line) } }
    static func prepare(weighted:Bool = false,using a:inout Admission) throws
        -> (F,OriginalDomainIdentityLimits,OriginalParameterFrame<S,F>,[Law]) {
        let parent = try ExactScalarNumericAccess.withAdmission(&a) { usage in
            func guide(_ z:Double) throws -> Curve3D {
                let vertices:[Point3D] = [.init(x:0,y:0,z:z),.init(x:1,y:0,z:z),.init(x:0,y:1,z:z),.init(x:0,y:0,z:z)]
                var spans:[OriginalCurveRootSpan3D] = []
                for i in 0..<3 {
                    let native = Curve3D.bSpline(.init(degree:1,knots:[0,0,1,1],controlPoints:[vertices[i],vertices[i+1]],weights:weighted && i == 0 ? [1,2]:[1,1]))
                    spans.append(try .init(source:native,start:.authored(0),end:.authored(1),nativeSpanIndex:1,
                        maximumParameterWidth:ModelingTolerance.standard.relative,maximumSubdivisionDepth:0,tolerance:.standard,
                        storageByteStride:MemoryLayout<UInt32>.stride,usage:&usage,maximumSpanCount:4,remainingSourceDepth:0,maximumAlgebraicDepth:0))
                }
                let quarter = try ExactRationalCoefficient.one.divided(by:.originalDouble(4,usage:&usage),usage:&usage)
                let threeQuarters = try quarter.multiplied(by:.originalDouble(3,usage:&usage),usage:&usage)
                return .originalGuideTraversalChain(try .init(traversals:spans,stations:[.zero,quarter,threeQuarters,.one],
                    sourceSegmentOrdinals:[0,1,2],remainingSourceDepth:2,tolerance:.standard,usage:&usage))
            }
            return RuledSurface3D(startBoundary:try guide(0),endBoundary:try guide(1),uDomain:.closed(0,1))
        }.value
        let f = try F(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
        let limits = try OriginalDomainIdentityLimits(source:.init(remainingSourceDepth:3),maximumTransportDepth:32,
            maximumCharts:16,maximumFamilies:2,maximumIdentityProofs:8)
        let guide = CallerAdapters.OriginalRetainedGuideCurveSnapshotProvider(field:f,tolerance:.standard)
        let source = try DefaultOriginalSourceBindingIssuer(provider:RuledObservationAdapters.OriginalRuledSurfaceSnapshotProvider(first:guide,second:guide,tolerance:.standard))
            .bind(parent,limits:limits.source,using:&a)
        let first = try DefaultOriginalFiniteRetainedCurveChartPreparer<G>().prepare(source:source.original.firstBoundary,
            maximumCharts:4,limits:.init(remainingSourceDepth:2),using:&a)
        let second = try DefaultOriginalFiniteRetainedCurveChartPreparer<G>().prepare(source:source.original.secondBoundary,
            maximumCharts:4,limits:.init(remainingSourceDepth:2),using:&a)
        let laws = try DefaultOriginalFiniteRuledChartPreparer<S,Int,Int,F>().prepare(source:source,first:first.laws,
            second:second.laws,field:f,maximumCharts:16,limits:limits.source,using:&a)
        try require(laws.count == 7)
        let unit = try ExactParameterInterval.checked(field:f,lower:.finite(f.integer(0,using:&a)),upper:.finite(f.integer(1,using:&a)),depth:.zero,using:&a)
        let frame = try DefaultOriginalParameterTransporter<S,F>().frame(source:source,field:f,support:[[unit],[unit]],
            semantics:[.authoredScalar,.authoredScalar],limits:limits,using:&a)
        return (f,limits,frame,laws)
    }
    static func issue<I:OriginalLawBoundParameterIdentityIssuing>(_ issuer:I,
        declaration:OriginalRationalSourceBoundaryDeclaration<S,Q,Q,F>,scope:OriginalParameterSelection<S,F>,
        frame:OriginalParameterFrame<S,F>,gains:[F.Value],offsets:[F.Value],limits:OriginalDomainIdentityLimits,
        using a:inout Admission) throws -> OriginalParameterIdentity<S,F> where I.Source == S,I.Field == F {
        try issuer.declaredBoundary(declaration:declaration,scope:scope,rightFrame:frame,
            permutation:[0,1],gains:gains,offsets:offsets,limits:limits,using:&a)
    }
    static func scopedControls(_ declaration:Declaration,frame:OriginalParameterFrame<S,F>,
        scope:OriginalParameterSelection<S,F>,field f:F,limits:OriginalDomainIdentityLimits,
        using a:inout Admission) throws {
        let issuer = DefaultOriginalParameterIdentityIssuer<S,F>()
        let zero = try f.integer(0,using:&a),one = try f.integer(1,using:&a)
        let half = try f.dividing(one,f.integer(2,using:&a),using:&a)
        let threeQuarters = try f.dividing(f.integer(3,using:&a),f.integer(4,using:&a),using:&a)
        // The reversed V correspondence agrees at the midpoint, but not on the edge.
        do {
            _ = try issue(issuer,declaration:declaration,scope:scope,frame:frame,
                gains:[one,f.integer(-1,using:&a)],offsets:[one,one],limits:limits,using:&a)
            throw Failure(line:#line)
        } catch OriginalDomainIdentityFailure.invalidIdentityProof {}
        let point = try ExactParameterInterval.checked(field:f,lower:.finite(zero),upper:.finite(zero),depth:.zero,using:&a)
        let halfV = try ExactParameterInterval.checked(field:f,lower:.finite(zero),upper:.finite(half),depth:.zero,using:&a)
        let restricted = try frame.selection(intervals:[[point],[halfV]],limits:limits,using:&a)
        let receipt = try issue(issuer,declaration:declaration,scope:restricted,frame:frame,
            gains:[one,one],offsets:[one,zero],limits:limits,using:&a)
        try require(issuer.decide(receipt,left:[zero,half],right:[one,half],limits:limits,using:&a) == .proven)
        try require(issuer.decide(receipt,left:[zero,threeQuarters],right:[one,threeQuarters],limits:limits,using:&a) == .notEstablished)
        var foreignAdmission = try Admission()
        let (_,_,foreignFrame,foreignLaws) = try prepare(using:&foreignAdmission)
        let foreignRight = Declaration(left:declaration.left,right:foreignLaws[6],leftAxis:0,rightAxis:0,leftSide:.lower,rightSide:.upper)
        do {
            _ = try issue(issuer,declaration:foreignRight,scope:scope,frame:frame,
                gains:[one,one],offsets:[one,zero],limits:limits,using:&a)
            throw Failure(line:#line)
        } catch OriginalDomainIdentityFailure.foreignOwner {}
        do {
            _ = try issue(issuer,declaration:declaration,scope:scope,frame:foreignFrame,
                gains:[one,one],offsets:[one,zero],limits:limits,using:&a)
            throw Failure(line:#line)
        } catch OriginalDomainIdentityFailure.foreignOwner {}
        print("PASS midpoint-only V reversal refused; half-V proof excludes outside; foreign law/frame refused")
    }
    static func germControls(_ laws:[Law],using a:inout Admission) throws {
        // W=1 on each entire chart makes these homogeneous derivatives exact XYZ germs.
        for (law,expected) in [(laws[0],[4,0,0]),(laws[6],[0,-4,0])] {
            let ring = law.polynomials,f = law.field
            let one = try ring.constant(f.integer(1,using:&a),using:&a)
            try require(ring.isZero(ring.subtracting(law.denominator,one,using:&a),using:&a))
            for axis in 0..<3 {
                let derivative = try ring.differentiated(law.homogeneous[axis],in:0,using:&a)
                let constant = try ring.constant(f.integer(expected[axis],using:&a),using:&a)
                try require(ring.isZero(ring.subtracting(derivative,constant,using:&a),using:&a))
            }
        }
        print("PASS exact whole-chart U germs 4X and -4Y remain unequal; identity is positional only")
    }
    static func detachedReceipt() throws -> (F,OriginalDomainIdentityLimits,OriginalParameterIdentity<S,F>) {
        var a = try Admission()
        let (f,limits,frame,laws) = try prepare(using:&a)
        let zero = try f.integer(0,using:&a),one = try f.integer(1,using:&a)
        let point = try ExactParameterInterval.checked(field:f,lower:.finite(zero),upper:.finite(zero),depth:.zero,using:&a)
        let unit = try ExactParameterInterval.checked(field:f,lower:.finite(zero),upper:.finite(one),depth:.zero,using:&a)
        let scope = try frame.selection(intervals:[[point],[unit]],limits:limits,using:&a)
        let declaration = Declaration(left:laws[0],right:laws[6],leftAxis:0,rightAxis:0,leftSide:.lower,rightSide:.upper)
        let receipt = try issue(DefaultOriginalParameterIdentityIssuer<S,F>(),declaration:declaration,scope:scope,frame:frame,
            gains:[one,one],offsets:[one,zero],limits:limits,using:&a)
        return (f,limits,receipt)
    }
    static func lifetimeControls() throws {
        // All construction locals and their admission have left scope before this query.
        let (f,limits,receipt) = try detachedReceipt()
        var source = [receipt]
        let retained = source
        source.append(retained[0])
        try require(source.count == 2 && retained.count == 1)
        source.removeAll(keepingCapacity:false)
        var a = try Admission()
        let zero = try f.integer(0,using:&a),one = try f.integer(1,using:&a)
        let issuer = DefaultOriginalParameterIdentityIssuer<S,F>()
        try require(issuer.decide(retained[0],left:[zero,zero],right:[one,zero],limits:limits,using:&a) == .proven)
        try require(issuer.decide(retained[0],left:[zero,one],right:[one,one],limits:limits,using:&a) == .proven)
        print("PASS detached receipt and copied array retain original source/laws after caller mutation")
    }
    static func admissionControls(_ declaration:Declaration,frame:OriginalParameterFrame<S,F>,
        scope:OriginalParameterSelection<S,F>,field f:F,limits:OriginalDomainIdentityLimits,
        using a:inout Admission) throws {
        let issuer = DefaultOriginalParameterIdentityIssuer<S,F>()
        let zero = try f.integer(0,using:&a),one = try f.integer(1,using:&a)
        // Only issuer work/storage is measured: source, law, scope and map inputs already exist.
        var measured = try Admission()
        _ = try issue(issuer,declaration:declaration,scope:scope,frame:frame,
            gains:[one,one],offsets:[one,zero],limits:limits,using:&measured)
        let work = measured.ledger.work,storage = measured.ledger.storageBytes,checkpoints = measured.checkpoints
        try require(work > 0 && storage > 0 && checkpoints > 2)
        var exact = try Admission(work:work,storageBytes:storage)
        let receipt = try issue(issuer,declaration:declaration,scope:scope,frame:frame,
            gains:[one,one],offsets:[one,zero],limits:limits,using:&exact)
        try require(exact.ledger.work == work && exact.ledger.storageBytes == storage)
        try require(issuer.decide(receipt,left:[zero,zero],right:[one,zero],limits:limits,using:&a) == .proven)
        var shortWork = try Admission(work:work-1,storageBytes:storage)
        do {
            _ = try issue(issuer,declaration:declaration,scope:scope,frame:frame,
                gains:[one,one],offsets:[one,zero],limits:limits,using:&shortWork)
            throw Failure(line:#line)
        } catch OriginalDomainIdentityFailure.scalar(.resourceLimit(.work)) {}
        var shortStorage = try Admission(work:work,storageBytes:storage-1)
        do {
            _ = try issue(issuer,declaration:declaration,scope:scope,frame:frame,
                gains:[one,one],offsets:[one,zero],limits:limits,using:&shortStorage)
            throw Failure(line:#line)
        } catch OriginalDomainIdentityFailure.scalar(.resourceLimit(.storage)) {}
        for stop in [1,checkpoints/2,checkpoints] {
            var cancelled = try Admission(work:work,storageBytes:storage,cancelAt:stop)
            do {
                _ = try issue(issuer,declaration:declaration,scope:scope,frame:frame,
                    gains:[one,one],offsets:[one,zero],limits:limits,using:&cancelled)
                throw Failure(line:#line)
            } catch OriginalDomainIdentityFailure.scalar(.cancelled) {}
            try require(cancelled.checkpoints == stop)
        }
#if hasFeature(Embedded)
        print("PASS issuer-only exact/one-less work/storage and entry/mid/final cancellation")
#else
        print("PASS issuer-only exact/one-less work/storage and entry/mid/final cancellation",work,storage,checkpoints)
#endif
    }
    static func nativeRegression() throws {
        var a = try Admission()
        let f = try F(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
        let limits = try OriginalDomainIdentityLimits(source:.init(remainingSourceDepth:3),maximumTransportDepth:32,
            maximumCharts:16,maximumFamilies:2,maximumIdentityProofs:8)
        func law(_ right:Bool) throws -> (OriginalParameterFrame<BSplineSurface3D,F>,OriginalRationalChartReceipt<BSplineSurface3D,OriginalBSplineChartSelection,F>) {
            let points:[[Point3D]] = right
                ? [[.init(x:1,y:0,z:0),.init(x:0,y:0,z:0)],[.init(x:1,y:-2,z:0),.init(x:0,y:-2,z:0)]]
                : [[.init(x:0,y:0,z:0),.init(x:1,y:0,z:0)],[.init(x:0,y:1,z:0),.init(x:1,y:1,z:0)]]
            let native = BSplineSurface3D(uDegree:1,vDegree:1,uKnots:[0,0,1,1],vKnots:[0,0,1,1],controlPoints:points,weights:[[1,1],[1,1]])
            let source = try DefaultOriginalSourceBindingIssuer(provider:OriginalBSplineSurfaceSnapshotProvider(tolerance:.standard))
                .bind(native,limits:limits.source,using:&a)
            let space = try DefaultOriginalBSplineDomainIssuer<BSplineSurface3D,F>().prepare(source:source,field:f,limits:limits,using:&a)
            let receipt = try DefaultOriginalBSplineChartIssuer<BSplineSurface3D,F>().issue(source:source,
                chart:space.sourceCharts[0],field:f,limits:limits.source,using:&a)
            return (space.frame,receipt)
        }
        let (leftFrame,left) = try law(false),(rightFrame,right) = try law(true)
        let zero = try f.integer(0,using:&a),one = try f.integer(1,using:&a)
        let half = try f.dividing(one,f.integer(2,using:&a),using:&a)
        let point = try ExactParameterInterval.checked(field:f,lower:.finite(zero),upper:.finite(zero),depth:.zero,using:&a)
        let unit = try ExactParameterInterval.checked(field:f,lower:.finite(zero),upper:.finite(one),depth:.zero,using:&a)
        let scope = try leftFrame.selection(intervals:[[unit],[point]],limits:limits,using:&a)
        let declaration = OriginalSourceBoundaryDeclaration(left:left.chart,right:right.chart,leftAxis:1,rightAxis:1,leftSide:.lower,rightSide:.lower)
        let issuer = DefaultOriginalParameterIdentityIssuer<BSplineSurface3D,F>()
        let receipt = try issuer.declaredBoundary(declaration:declaration,left:left,right:right,scope:scope,rightFrame:rightFrame,
            permutation:[0,1],gains:[f.integer(-1,using:&a),one],offsets:[one,zero],limits:limits,using:&a)
        try require(issuer.decide(receipt,left:[half,zero],right:[half,zero],limits:limits,using:&a) == .proven)
        try require(issuer.decide(receipt,left:[zero,zero],right:[one,zero],limits:limits,using:&a) == .proven)
        try require(issuer.decide(receipt,left:[one,zero],right:[zero,zero],limits:limits,using:&a) == .proven)
        do {
            _ = try issuer.declaredBoundary(declaration:declaration,left:left,right:right,scope:scope,rightFrame:rightFrame,
                permutation:[0,1],gains:[one,one],offsets:[zero,zero],limits:limits,using:&a)
            throw Failure(line:#line)
        } catch OriginalDomainIdentityFailure.invalidIdentityProof {}
        print("PASS fresh actual Native old-overload whole-boundary success and midpoint-only false refusal")
    }
    static func run() throws {
        var a = try Admission()
        let (f,limits,frame,laws) = try prepare(using:&a)
        let zero = try f.integer(0,using:&a),one = try f.integer(1,using:&a)
        let unit = try ExactParameterInterval.checked(field:f,lower:.finite(zero),upper:.finite(one),depth:.zero,using:&a)
        let point = try ExactParameterInterval.checked(field:f,lower:.finite(zero),upper:.finite(zero),depth:.zero,using:&a)
        let scope = try frame.selection(intervals:[[point],[unit]],limits:limits,using:&a)
        let declaration = OriginalRationalSourceBoundaryDeclaration(left:laws[0],right:laws[6],leftAxis:0,rightAxis:0,leftSide:.lower,rightSide:.upper)
        let issuer = DefaultOriginalParameterIdentityIssuer<S,F>()
        let receipt = try issue(issuer,declaration:declaration,scope:scope,frame:frame,gains:[one,one],offsets:[one,zero],limits:limits,using:&a)
        try require(receipt.kind == .declaredSharedBoundary)
        for v in [zero,try f.dividing(one,f.integer(2,using:&a),using:&a),one] {
            let result = try issuer.decide(receipt,left:[zero,v],right:[one,v],limits:limits,using:&a)
            try require(result == .proven)
        }
        try require(issuer.decide(receipt,left:[one,zero],right:[zero,zero],limits:limits,using:&a) == .notEstablished)
        print("PASS actual same-parent closed-guide directed whole seam through generic capability; reverse remains outside scope")
        let quarter = try f.dividing(one,f.integer(4,using:&a),using:&a)
        let falseBoundary = OriginalRationalSourceBoundaryDeclaration(left:laws[0],right:laws[0],leftAxis:0,rightAxis:0,leftSide:.lower,rightSide:.upper)
        do {
            _ = try issue(issuer,declaration:falseBoundary,scope:scope,frame:frame,gains:[one,one],offsets:[quarter,zero],limits:limits,using:&a)
            throw Failure(line:#line)
        } catch OriginalDomainIdentityFailure.invalidIdentityProof {}
        print("PASS false whole boundary rejected")
        try scopedControls(declaration,frame:frame,scope:scope,field:f,limits:limits,using:&a)
        try germControls(laws,using:&a)
        try lifetimeControls()
        try admissionControls(declaration,frame:frame,scope:scope,field:f,limits:limits,using:&a)
        try nativeRegression()
        var weightedAdmission = try Admission()
        let (wf,wl,wframe,weighted) = try prepare(weighted:true,using:&weightedAdmission)
        let wz = try wf.integer(0,using:&weightedAdmission),wo = try wf.integer(1,using:&weightedAdmission)
        let wp = try ExactParameterInterval.checked(field:wf,lower:.finite(wz),upper:.finite(wz),depth:.zero,using:&weightedAdmission)
        let ws = try ExactParameterInterval.checked(field:wf,lower:.finite(weighted[0].support[0].lower),upper:.finite(weighted[0].support[0].upper),depth:.zero,using:&weightedAdmission)
        let weightedScope = try wframe.selection(intervals:[[ws],[wp]],limits:wl,using:&weightedAdmission)
        let guarded = OriginalRationalSourceBoundaryDeclaration(left:weighted[0],right:weighted[0],leftAxis:1,rightAxis:1,leftSide:.lower,rightSide:.lower)
        do {
            _ = try issue(issuer,declaration:guarded,scope:weightedScope,frame:wframe,gains:[wo,wo],offsets:[wz,wz],limits:wl,using:&weightedAdmission)
            throw Failure(line:#line)
        } catch OriginalDomainIdentityFailure.unsupportedSourceProof {}
        print("PASS actual weighted ruled nonconstant guard explicitly unsupported")
        // Inject only conservative admission history; original owners and all laws stay unchanged.
        // The actual polynomial laws have depth zero. Optional decision history
        // is checked separately: absence is not a stored zero-depth certificate.
        let inherited = 9
        for law in [laws[0],laws[6]] {
            if let depth = law.proofDepth {
                try require(depth.value == 0 && depth.coefficient == 0)
                print("PASS actual receipt explicitly retains zero decision depth")
            } else {
                try require(law.proofDepth == nil)
                print("PASS actual receipt has no additional retained decision history")
            }
            for group in [law.homogeneous,law.parameterTransport.numerators,law.parameterTransport.denominators] {
                for polynomial in group {
                    try require(polynomial.depth.value == 0 && polynomial.depth.coefficient == 0)
                }
            }
        }
        func retainingHistory(_ law:Law) throws -> Law {
            .init(chart:law.chart,field:law.field,polynomials:law.polynomials,homogeneous:law.homogeneous,
                support:law.support,parameterTransport:law.parameterTransport,periods:law.periods,
                proofDepth:try .init(value:inherited,coefficient:7))
        }
        let history = OriginalRationalSourceBoundaryDeclaration(left:try retainingHistory(laws[0]),right:try retainingHistory(laws[6]),
            leftAxis:0,rightAxis:0,leftSide:.lower,rightSide:.upper)
        let historyReceipt = try issue(issuer,declaration:history,scope:scope,frame:frame,gains:[one,one],offsets:[one,zero],limits:limits,using:&a)
        var tight = try Admission(depth:inherited-1)
        do {
            _ = try issue(issuer,declaration:history,scope:scope,frame:frame,gains:[one,one],offsets:[one,zero],limits:limits,using:&tight)
            throw Failure(line:#line)
        } catch OriginalDomainIdentityFailure.scalar(.resourceLimit(.valueDepth)) {
        } catch OriginalDomainIdentityFailure.scalar(.resourceLimit(.coefficientDepth)) {}
        let reached = max(historyReceipt.evidenceDepth.value,historyReceipt.evidenceDepth.coefficient)
        try require(reached >= inherited)
        var reader = try Admission(depth:reached-1)
        do {
            _ = try issuer.decide(historyReceipt,left:[zero,zero],right:[one,zero],limits:limits,using:&reader)
            throw Failure(line:#line)
        } catch OriginalDomainIdentityFailure.scalar(.resourceLimit(.valueDepth)) {
        } catch OriginalDomainIdentityFailure.scalar(.resourceLimit(.coefficientDepth)) {}
#if hasFeature(Embedded)
        print("PASS conservative injected history admitted before proof and retained for later query")
        print("PASS identity-only checks")
#else
        print("PASS conservative injected history admitted before proof and retained for later query",inherited,reached)
        print("PASS identity-only Native checks; work",a.ledger.work,"storage",a.ledger.storageBytes)
#endif
    }
    static func main() {
        do { try run() }
        catch {
#if hasFeature(Embedded)
            print("IDENTITY_STOP")
#else
            print("IDENTITY_STOP",error)
#endif
            exit(1)
        }
    }
}

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


import enum RetainedHostAdapters.OriginalDomainAccess
import class RetainedHostAdapters.OriginalIdentityReadmission
import CADCore
@testable import CADGeometry
@testable import RetainedHostAdapters
@testable import PublicLiftPlane
@testable import GuideSeamPort

/// Reuses the accepted four-chart planar Coons input with the current self consumer.
enum GuideSeamCoonsRegression {
    typealias Admission = ClosedGuideSeamAcceptance.Admission
    typealias Base = OriginalExactScalarDomain
    typealias Source = RetainedHostAdapters.OriginalCoonsAtlasSnapshot
    typealias Cover = OriginalIssuedDomainCover<Source, Int, Base>
    typealias Evidence = OriginalRationalChartReceipt<Source, Int, Base>
    typealias Raw = GuideSeamPort.OriginalIssuedGraphRelations<Source, Evidence, Cover, Source, Evidence, Cover>
    typealias Cells = PublicLiftPlane.ExactRealCellDomain<Base>

    private static func require(_ condition: Bool) throws {
        if !condition { throw ExactScalarFailure.invalidEvidence }
    }

    private static func limits() throws -> OriginalDomainIdentityLimits {
        try .init(source: .init(remainingSourceDepth: 8), maximumTransportDepth: 16,
            maximumCharts: 32, maximumFamilies: 2, maximumIdentityProofs: 16)
    }

    // The multi:true branch of the accepted PolylineAtlasLiftProof.shape recipe.
    private static func shape(using a: inout Admission) throws -> OriginalCoonsSurface3D {
        try ExactScalarNumericAccess.withAdmission(&a) { usage in
            let t = [0.0, 0.5, 1.0], knots = [0.0, 0, 0.5, 1, 1]
            let native = BSplineSurface3D(uDegree: 1, vDegree: 1, uKnots: knots, vKnots: knots,
                controlPoints: t.map { v in t.map { u in .init(x: u, y: v, z: 0) } })
            let issuer = OriginalSurfaceBoundarySourceIssuer()
            func boundary(_ side: SurfaceParameterBoundary) throws -> OriginalCurveRootSpan3D {
                try issuer.boundary(of: .bSpline(native), at: side, maximumDepth: 0,
                    maximumSpanCount: 4, tolerance: .standard, usage: &usage)
            }
            let lower = try boundary(.vLower)
            return try OriginalCoonsSurface3D(vMinimumBoundary: lower, vMaximumBoundary: boundary(.vUpper),
                uMinimumBoundary: boundary(.uLower), uMaximumBoundary: boundary(.uUpper),
                tolerance: .standard, usage: &usage)
        }.value
    }

    static func raw(using a: inout Admission) throws -> Raw {
        let host = try shape(using: &a)
        let field = try Base(maximumValueDepth: 32, maximumCoefficientDepth: 32, using: &a)
        let limits = try limits()
        let source = try DefaultOriginalSourceBindingIssuer(
            provider: OriginalCoonsAtlasSnapshotProvider(field: field, tolerance: .standard))
            .bind(host, limits: limits.source, using: &a)
        let charts = try DefaultOriginalFiniteRetainedSurfaceChartPreparer<Source>()
            .prepare(source: source, maximumCharts: 4, limits: limits.source, using: &a)
        try require(charts.laws.count == 4 && charts.support.count == 2)
        for bound in charts.support {
            try require(field.compare(bound.lower, field.integer(0, using: &a), using: &a) == .equal)
            try require(field.compare(bound.upper, field.integer(1, using: &a), using: &a) == .equal)
        }
        var intervals: [[ExactParameterInterval<OriginalExactScalar>]] = []
        for bound in charts.support {
            intervals.append([try .checked(field: field, lower: .finite(bound.lower), upper: .finite(bound.upper),
                depth: .zero, using: &a)])
        }
        let frame = try DefaultOriginalParameterTransporter<Source, Base>().frame(source: source, field: field,
            support: intervals, semantics: [.authoredScalar, .authoredScalar], limits: limits, using: &a)
        let cover = try DefaultOriginalIssuedDomainBinder().bind(laws: charts.laws,
            request: frame.fullSelection(limits: limits, using: &a), limits: limits, using: &a)
        let algebraic = try PublicLiftPlane.ExactAlgebraicScalarDomain.base(field: field, maximumExtensionLevel: 32, using: &a)
        let family = try GuideSeamPort.DefaultOriginalRationalGraphFamilyPreparer().prepare(cover: cover, field: algebraic,
            maximumGraphs: 4, limits: limits, using: &a)
        try require(family.graphs.count == 4)
        for graph in family.graphs {
            let original = graph.original.graph, ring = original.polynomials
            let zero = try ring.constant(field.integer(0, using: &a), using: &a)
            let one = try ring.constant(field.integer(1, using: &a), using: &a)
            let expected = [try ring.variable(0, using: &a), try ring.variable(1, using: &a), zero, one]
            try require(original.layout.variableCount == 2)
            for axis in expected.indices {
                try require(ring.equals(original.homogeneous[axis], expected[axis], using: &a))
            }
            for axis in 0..<2 {
                try require(ring.equals(original.parameterTransport.numerators[axis], expected[axis], using: &a))
                try require(ring.equals(original.parameterTransport.denominators[axis], one, using: &a))
            }
        }
        return try GuideSeamPort.DefaultOriginalIssuedGraphRelationResolver().resolve(kind: .surfaceSurface,
            first: family, second: family, maximumPairs: 16, limits: limits,
            cellLimits: .init(maximumStoredCells: 20_000, maximumRootsPerStack: 100),
            topologyLimits: .init(maximumGeneratedCells: 20_000, maximumRootsPerStack: 100,
                maximumClosures: 20_000, maximumAttachmentPieces: 100_000, maximumComponents: 1_000), using: &a)
    }

    static func oracle(_ raw: Raw, using a: inout Admission) throws {
        try require(raw.pairs.count == 16 && raw.first.source.owner === raw.second.source.owner)
        // Independently authored knot grid; validate the chart cover before using
        // its ordinals to test both inclusion and exclusion over every full cell.
        let base = raw.first.graphs[0].original.graph.field
        var rectangles: [[Double]] = []
        for graph in raw.first.graphs {
            let original = graph.original.graph
            var matched: [Double]?
            for v in [0.0, 0.5] {
                for u in [0.0, 0.5] {
                    let candidate = [u, u + 0.5, v, v + 0.5]
                    var equal = original.support.count == 2 && original.includesUpperBoundary == [true, true]
                    for axis in 0..<2 {
                        equal = try equal && base.compare(original.support[axis].lower,
                            base.binary64(exactly: candidate[2 * axis], using: &a), using: &a) == .equal
                        equal = try equal && base.compare(original.support[axis].upper,
                            base.binary64(exactly: candidate[2 * axis + 1], using: &a), using: &a) == .equal
                    }
                    if equal { matched = candidate }
                }
            }
            guard let matched, !rectangles.contains(matched) else { throw ExactScalarFailure.invalidEvidence }
            rectangles.append(matched)
        }
        var nonemptyPairs = 0
        for pair in raw.pairs {
            let selected = pair.relation.projection.original, partition = selected.partition
            try require(partition.source.variableCount == 4)
            try require(pair.relation.original.firstCoordinates == [0, 1])
            try require(pair.relation.original.secondCoordinates == [2, 3])
            let cells = try Cells(retaining: partition.source, using: &a), ring = cells.polynomials
            let u = try ring.subtracting(ring.variable(0, using: &a), ring.variable(2, using: &a), using: &a)
            let v = try ring.subtracting(ring.variable(1, using: &a), ring.variable(3, using: &a), using: &a)
            guard let us = try cells.signInvariant(for: u, in: partition, using: &a),
                let vs = try cells.signInvariant(for: v, in: partition, using: &a) else { throw ExactScalarFailure.invalidEvidence }
            let bounds = rectangles[pair.firstGraphIndex] + rectangles[pair.secondGraphIndex]
            var constraints: [ExactPolynomial<PublicLiftPlane.ExactAlgebraicScalarDomain<Base>>] = []
            for axis in 0..<4 {
                for endpoint in 0..<2 {
                    let value = try ring.field.importingBase(base.binary64(exactly: bounds[2 * axis + endpoint], using: &a), using: &a)
                    constraints.append(try ring.subtracting(ring.variable(axis, using: &a), ring.constant(value, using: &a), using: &a))
                }
            }
            let invariants = try constraints.map { polynomial in
                guard let invariant = try cells.signInvariant(for: polynomial, in: partition, using: &a) else {
                    throw ExactScalarFailure.invalidEvidence
                }
                return invariant
            }
            var count = 0
            for cell in partition.cells where cell.axis == 3 {
                let diagonal = try cells.sign(of: us, at: cell, using: &a) == .zero && cells.sign(of: vs, at: cell, using: &a) == .zero
                var inside = true
                for index in invariants.indices {
                    let sign = try cells.sign(of: invariants[index], at: cell, using: &a)
                    if index % 2 == 0 ? sign == .negative : sign == .positive { inside = false }
                }
                try require(selected.cells.contains(cell) == (diagonal && inside))
                if selected.cells.contains(cell) { count += 1 }
            }
            if count > 0 { nonemptyPairs += 1 }
        }
        try require(nonemptyPairs == 16)
        print("PASS S-COONS-PLANE-01 all 16 chart pairs equal the complete independent closed-domain diagonal oracle")
    }

    static func run() throws {
        // Preserve the accepted Coons caller ceilings, separately for preparation and query.
        var preparation = try Admission(work: 80_000_000, storageBytes: 1_073_741_824)
        let original = try raw(using: &preparation)
        try oracle(original, using: &preparation)
        var query = try Admission(work: 80_000_000, storageBytes: 1_073_741_824)
        let domainLimits = try limits()
        let result = try GuideSeamPort.DefaultOriginalIssuedGraphSelfContactQuery().contacts(in: original,
            domainLimits: domainLimits,
            cellLimits: .init(maximumStoredCells: 20_000, maximumRootsPerStack: 100),
            topologyLimits: .init(maximumGeneratedCells: 20_000, maximumRootsPerStack: 100,
                maximumClosures: 20_000, maximumAttachmentPieces: 100_000, maximumComponents: 1_000), using: &query)
        try require(result.raw.pairs.count == 16 && result.refinements.count == 16
            && result.authoredDiagonals.count == 16 && result.identities.isEmpty)
        let issuer = DefaultOriginalParameterIdentityIssuer<Source, Base>()
        for ordinal in result.refinements.indices {
            let refined = result.refinements[ordinal], pullback = refined.pullback
            let pair = original.pairs[ordinal]
            try require(pair.firstGraphIndex == ordinal / 4 && pair.secondGraphIndex == ordinal % 4)
            try require(refined.pairOrdinal == ordinal && pullback.coordinateMap == [0, 1, 2, 3])
            let selected = pair.relation.projection.original.cells
            try require(pullback.source.cells.count == selected.count)
            for index in selected.indices { try require(pullback.source.cells[index] == selected[index]) }
            let region = pullback.region
            try require(region.coordinateCount == 4 && region.cells.count == region.included.count
                && region.cells.count == pullback.sourceCellOrdinals.count)
            var terminalCount = 0
            for cell in region.partition.cells where cell.axis == 3 {
                terminalCount += 1
                var occurrences = 0
                for retained in region.cells { if retained == cell { occurrences += 1 } }
                try require(occurrences == 1)
            }
            try require(terminalCount > 0 && terminalCount == region.cells.count)
            try require(region.included.allSatisfy { !$0 })
            for sourceOrdinal in pullback.sourceCellOrdinals { try require(sourceOrdinal == -1) }
            // The consumed authored diagonal retains each actual pair's complete request scopes.
            let diagonal = try issuer.relation(of: result.authoredDiagonals[ordinal],
                limits: domainLimits, using: &preparation)
            try require(diagonal.left.equals(original.first.graphs[pair.firstGraphIndex].original.request,
                limits: domainLimits, using: &preparation))
            try require(diagonal.right.equals(original.second.graphs[pair.secondGraphIndex].original.request,
                limits: domainLimits, using: &preparation))
            guard case .affine(let permutation, let gains, let offsets) = diagonal.constraints else {
                throw ExactScalarFailure.invalidEvidence
            }
            try require(permutation == [0, 1] && gains.count == 2 && offsets.count == 2)
            let field = diagonal.left.frame.scalarField
            for axis in 0..<2 {
                try require(field.compare(gains[axis], field.integer(1, using: &preparation), using: &preparation) == .equal)
                try require(field.compare(offsets[axis], field.integer(0, using: &preparation), using: &preparation) == .equal)
            }
        }
        print("PASS current Coons self regression: original four charts, whole ordered16 diagonal and complete empty residual")
    }
}

