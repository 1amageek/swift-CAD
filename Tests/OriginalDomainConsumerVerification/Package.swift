// swift-tools-version: 6.4
import PackageDescription
let adapterFiles = ["BSplineCurve3D+OriginalSourceReading.swift","BSplineSurface3D+OriginalSourceReading.swift","OriginalBSplineCurveSnapshotProvider.swift","OriginalBSplineSurfaceSnapshotProvider.swift"]
let package = Package(name:"OriginalDomainConsumerVerification",platforms:[.macOS(.v15),.custom("wasi",versionString:"0")],targets:[
 .target(name:"L0",exclude:["DESIGN.md"]),
 .target(name:"L1",dependencies:["L0"],exclude:["DESIGN.md"],swiftSettings:[.define("L1_ISOLATED_VERIFICATION")]),
 .target(name:"DI0",dependencies:["L0"],exclude:["DESIGN.md"],swiftSettings:[.define("EXACT_DOMAIN_ISOLATED_VERIFICATION")]),
 .target(name:"L2",dependencies:["L0","L1","DI0"],exclude:["DESIGN.md"],swiftSettings:[.define("L2_ISOLATED_VERIFICATION")]),
 .target(name:"L3",dependencies:["L0","L1","L2"],exclude:["DESIGN.md"],swiftSettings:[.define("L3_ISOLATED_VERIFICATION")]),
 .target(name:"L4",dependencies:["L0","L1","L2","L3"],exclude:["DESIGN.md"],swiftSettings:[.define("L4_ISOLATED_VERIFICATION")]),
 .target(name:"L5",dependencies:["L0","L1","L2","L3","L4"],exclude:["DESIGN.md"],swiftSettings:[.define("L5_ISOLATED_VERIFICATION")]),
 .target(name:"SourceIssuer",dependencies:["L0","L1"],exclude:["DESIGN.md"]+adapterFiles,swiftSettings:[.define("ORIGINAL_SOURCE_ISOLATED_VERIFICATION")]),
 .target(name:"DI",dependencies:["L0","L1","DI0","SourceIssuer"],exclude:["DESIGN.md","ExactParameterDomain","OriginalParameterTransport/DESIGN.md","OriginalDomainCoverage/DESIGN.md","OriginalParameterIdentity/DESIGN.md"],swiftSettings:[.define("ORIGINAL_DOMAIN_ISOLATED_VERIFICATION")])
])
