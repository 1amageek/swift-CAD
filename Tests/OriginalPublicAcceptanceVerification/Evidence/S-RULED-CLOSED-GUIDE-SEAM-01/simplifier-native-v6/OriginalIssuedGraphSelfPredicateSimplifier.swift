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
/// Domain-wide exact affine bounds simplify only the checked residual formula.
struct OriginalIssuedGraphSelfPredicateSimplifier {
    typealias Base = OriginalExactScalarDomain
    typealias Field = ExactAlgebraicScalarDomain<Base>
    typealias Predicate = ExactRealCellPredicate<Base>
    struct Result {
        let predicate: Predicate
        let depth: ExactScalarDepth
    }
    private enum Node {
        case literal(Bool)
        case atom(Int, ExactRealCellSignRelation)
        case not(Int)
        case and(Int, Int)
        case or(Int, Int)
    }
    static func simplify<A: ExactScalarAdmission & ~Copyable>(_ predicate: Predicate,
        cells: ExactRealCellDomain<Base>, using admission: inout A) throws -> Result {
        try OriginalSourceProofAdmission.withBorrow(&admission) { a in
            try a.checkpoint()
            try a.admitDepth(value: predicate.depth.value, coefficient: predicate.depth.coefficient)
            let field = try cells.coefficientField(of: predicate.source, using: &a)
            let count = predicate.instructions.count
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: Node.self))
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: Int.self))
            var nodes: [Node] = [], stack: [Int] = []
            nodes.reserveCapacity(count); stack.reserveCapacity(count)
            for instruction in predicate.instructions {
                try a.consumeWork(1)
                switch instruction {
                case .literal(let value):
                    nodes.append(.literal(value)); stack.append(nodes.count - 1)
                case .sign(let index, let relation):
                    guard predicate.source.polynomials.indices.contains(index) else { throw NativeExactRelationFailure.invalidDomain }
                    if let value = try truth(of: predicate.source.polynomials[index], relation: relation,
                        domains: predicate.source.domains, field: field, using: &a) {
                        nodes.append(.literal(value))
                    } else { nodes.append(.atom(index, relation)) }
                    stack.append(nodes.count - 1)
                case .not:
                    guard let child = stack.popLast() else { throw NativeExactRelationFailure.invalidDomain }
                    if case .literal(let value) = nodes[child] { nodes.append(.literal(!value)) }
                    else { nodes.append(.not(child)) }
                    stack.append(nodes.count - 1)
                case .and, .or:
                    guard let right = stack.popLast(), let left = stack.popLast() else { throw NativeExactRelationFailure.invalidDomain }
                    let isAnd: Bool
                    if case .and = instruction { isAnd = true } else { isAnd = false }
                    if case .literal(let value) = nodes[left] {
                        stack.append(value == isAnd ? right : left)
                    } else if case .literal(let value) = nodes[right] {
                        stack.append(value == isAnd ? left : right)
                    } else {
                        nodes.append(isAnd ? .and(left, right) : .or(left, right)); stack.append(nodes.count - 1)
                    }
                }
            }
            guard stack.count == 1 else { throw NativeExactRelationFailure.invalidDomain }
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: (Int, Bool).self))
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: ExactRealCellInstruction.self))
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: predicate.source.polynomials.count, of: Bool.self))
            var pending: [(Int, Bool)] = [(stack[0], false)]
            pending.reserveCapacity(count)
            var program: [ExactRealCellInstruction] = []
            program.reserveCapacity(count)
            var referenced = Array(repeating: false, count: predicate.source.polynomials.count)
            while let (index, visited) = pending.popLast() {
                try a.consumeWork(1)
                switch nodes[index] {
                case .literal(let value): program.append(.literal(value))
                case .atom(let law, let relation):
                    referenced[law] = true; program.append(.sign(polynomial: law, relation: relation))
                case .not(let child):
                    if visited { program.append(.not) }
                    else { pending.append((index, true)); pending.append((child, false)) }
                case .and(let left, let right), .or(let left, let right):
                    if visited {
                        if case .and = nodes[index] { program.append(.and) } else { program.append(.or) }
                    } else { pending.append((index, true)); pending.append((right, false)); pending.append((left, false)) }
                }
            }
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: referenced.count, of: Int.self))
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: referenced.count, of: ExactPolynomial<Field>.self))
            var indices = Array(repeating: -1, count: referenced.count)
            var laws: [ExactPolynomial<Field>] = []
            laws.reserveCapacity(referenced.count)
            for index in referenced.indices {
                try a.consumeWork(1)
                if referenced[index] { indices[index] = laws.count; laws.append(predicate.source.polynomials[index]) }
            }
            for index in program.indices {
                try a.consumeWork(1)
                if case .sign(let law, let relation) = program[index] {
                    program[index] = .sign(polynomial: indices[law], relation: relation)
                }
            }
            let source = try cells.bind(polynomials: laws, domains: predicate.source.domains, using: &a)
            let simplified = try cells.predicate(instructions: program, for: source, using: &a)
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Result.self))
            let result = Result(predicate: simplified, depth: try a.depth)
            try a.checkpoint(); return result
        }
    }
    private static func truth<A: ExactScalarAdmission & ~Copyable>(of law: ExactPolynomial<Field>,
        relation: ExactRealCellSignRelation, domains: [ExactRealRootInterval<Field.Value>],
        field: Field, using a: inout A) throws -> Bool? {
        try a.admitDepth(value: law.depth.value, coefficient: law.depth.coefficient)
        for domain in domains {
            try a.consumeWork(1)
            try a.admitDepth(value: domain.depth.value, coefficient: domain.depth.coefficient)
            if domain.isEmpty { return nil }
        }
        var lower = try field.integer(0, using: &a), upper = lower
        for term in law.terms {
            try a.consumeWork(1)
            guard term.powers.count == domains.count else { throw NativeExactRelationFailure.invalidDomain }
            var variable: Int?
            for axis in term.powers.indices {
                try a.consumeWork(1)
                if term.powers[axis] != 0 {
                    guard term.powers[axis] == 1, variable == nil else { return nil }
                    variable = axis
                }
            }
            let coefficient = try field.importing(term.coefficient, using: &a)
            let sign = try field.sign(of: coefficient, using: &a)
            if sign == .zero { continue }
            if let variable {
                guard case .finite(let lo) = domains[variable].lower,
                    case .finite(let hi) = domains[variable].upper else { return nil }
                let minimum = sign == .positive ? lo : hi, maximum = sign == .positive ? hi : lo
                lower = try field.adding(lower, field.multiplying(coefficient, field.importing(minimum, using: &a), using: &a), using: &a)
                upper = try field.adding(upper, field.multiplying(coefficient, field.importing(maximum, using: &a), using: &a), using: &a)
            } else {
                lower = try field.adding(lower, coefficient, using: &a)
                upper = try field.adding(upper, coefficient, using: &a)
            }
        }
        let lo = try field.sign(of: lower, using: &a), hi = try field.sign(of: upper, using: &a)
        switch relation {
        case .equal:
            if lo == .positive || hi == .negative { return false }
            if lo == .zero && hi == .zero { return true }
        case .notEqual:
            if lo == .positive || hi == .negative { return true }
            if lo == .zero && hi == .zero { return false }
        case .less:
            if hi == .negative { return true }; if lo != .negative { return false }
        case .lessOrEqual:
            if hi != .positive { return true }; if lo == .positive { return false }
        case .greater:
            if lo == .positive { return true }; if hi != .positive { return false }
        case .greaterOrEqual:
            if lo != .negative { return true }; if hi == .negative { return false }
        }
        return nil
    }
}
