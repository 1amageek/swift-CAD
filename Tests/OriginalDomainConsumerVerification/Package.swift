// swift-tools-version: 6.4
import PackageDescription
let adapterFiles = ["BSplineCurve3D+OriginalSourceReading.swift","BSplineSurface3D+OriginalSourceReading.swift","OriginalBSplineCurveSnapshotProvider.swift","OriginalBSplineSurfaceSnapshotProvider.swift"]
let package = Package(name:"OriginalDomainConsumerVerification",platforms:[.macOS(.v15),.custom("wasi",versionString:"0")],targets:[
 .target(name:"NativeFamilyAdapter",dependencies:["L0","L1","L2","L3","L4","L5","DI0","DI","SourceIssuer"],path:"Sources/NativeDomainAdapters",sources:["NativeExactParametricRelations.swift","NativeExactParametricRelationPiece.swift","NativeExactRelationFamilyResolving.swift","DefaultNativeExactRelationFamilyResolver.swift","NativeExactRelationFailure.swift"],swiftSettings:[.define("NATIVE_FAMILY_ISOLATED_VERIFICATION")]),
 .target(name:"L0",exclude:["DESIGN.md"]),
 .target(name:"L1",dependencies:["L0"],exclude:["DESIGN.md"],swiftSettings:[.define("L1_ISOLATED_VERIFICATION")]),
 .target(name:"DI0",dependencies:["L0"],exclude:["DESIGN.md"],swiftSettings:[.define("EXACT_DOMAIN_ISOLATED_VERIFICATION")]),
 // The coordinate bridge is compiled separately with its existing testable L0/L2 boundary.
 .target(name:"L2",dependencies:["L0","L1","DI0"],exclude:["DESIGN.md", "ExactOriginalScalarTransferring.swift", "ExactOriginalScalarTransferReceipt.swift",
 "DefaultExactOriginalScalarTransporter.swift", "OriginalCoordinateTransportState.swift", "OriginalCoordinateTransportState+Roots.swift"],swiftSettings:[.define("L2_ISOLATED_VERIFICATION")]),
 .target(name:"L3",dependencies:["L0","L1","L2"],exclude:["DESIGN.md"],swiftSettings:[.define("L3_ISOLATED_VERIFICATION")]),
 .target(name:"L4",dependencies:["L0","L1","L2","L3"],exclude:["DESIGN.md"],swiftSettings:[.define("L4_ISOLATED_VERIFICATION")]),
 .target(name:"L5",dependencies:["L0","L1","L2","L3","L4"],exclude:["DESIGN.md"],swiftSettings:[.define("L5_ISOLATED_VERIFICATION")]),
 .target(name:"SourceIssuer",dependencies:["L0","L1"],exclude:["DESIGN.md", "OriginalPhysicalAngle/DESIGN.md",
        "BSplineCurve3D+OriginalSourceReading.swift", "BSplineSurface3D+OriginalSourceReading.swift",
        "OriginalBSplineCurveSnapshotProvider.swift", "OriginalBSplineSurfaceSnapshotProvider.swift",
        "OriginalAnalyticCoordinateSnapshot.swift", "OriginalAnalyticCoordinateCurveSnapshotProvider.swift", "OriginalAnalyticCoordinateSurfaceSnapshotProvider.swift",
        "OriginalPlaneSnapshot.swift", "OriginalPlaneSnapshotProvider.swift", "OriginalStoredPlaneBasis.swift",
        "OriginalAnalyticPrimitiveSnapshot.swift", "OriginalAnalyticPrimitiveSnapshotProvider.swift",
        "OriginalAnalyticConeSnapshot.swift", "OriginalAnalyticConeSnapshotProvider.swift",
        "OriginalNativeCurveFamilySnapshotProvider.swift", "OriginalLinearCurveSnapshot.swift",
        "OriginalLinearCurveSnapshotProvider.swift", "OriginalRuledSurfaceSnapshot.swift",
        "OriginalRuledSurfaceSnapshotProvider.swift", "OriginalAffineWordSnapshot.swift",
        "OriginalAffineWordCoefficientImport.swift", "OriginalAffineWordCurveSnapshotProvider.swift",
        "OriginalAffineWordSurfaceSnapshotProvider.swift", "OriginalNativeSurfaceFamilySnapshotProvider.swift",
        "OriginalParameterImageSnapshot.swift", "OriginalParameterImageCurveSnapshotProvider.swift",
        "OriginalParameterImageSurfaceSnapshotProvider.swift", "OriginalTraversalSpanSnapshot.swift",
        "OriginalTraversalEndpointBinding.swift", "OriginalTraversalSpanSnapshotProvider.swift",
        "OriginalCoonsSurfaceSnapshot.swift", "OriginalCoonsSurfaceSnapshotProvider.swift"],swiftSettings:[.define("ORIGINAL_SOURCE_ISOLATED_VERIFICATION")]),
 .target(name:"DI",dependencies:["L0","L1","DI0","SourceIssuer"],exclude:["DESIGN.md","ExactParameterDomain","OriginalParameterTransport/DESIGN.md","OriginalDomainCoverage/DESIGN.md","OriginalParameterIdentity/DESIGN.md"],swiftSettings:[.define("ORIGINAL_DOMAIN_ISOLATED_VERIFICATION")])
])
