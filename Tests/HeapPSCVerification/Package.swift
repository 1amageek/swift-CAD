// swift-tools-version: 6.4
import PackageDescription
let package = Package(name:"HeapPSCVerification", platforms:[.macOS(.v14)], targets:[
 .target(name:"L0",path:"Sources/L0",exclude:["DESIGN.md"],swiftSettings:[.unsafeFlags(["-enable-testing"])]),
 .target(name:"L1",dependencies:["L0"],path:"Sources/L1",exclude:["DESIGN.md"],swiftSettings:[.define("L1_ISOLATED_VERIFICATION")]),
 .target(name:"L2",dependencies:["L0","L1"],path:"Sources/L2",exclude:["DESIGN.md"],swiftSettings:[.define("L2_ISOLATED_VERIFICATION")]),
 .target(name:"L3",dependencies:["L0","L1","L2"],path:"Sources/L3",exclude:["DESIGN.md"],swiftSettings:[.define("L3_ISOLATED_VERIFICATION")]),
 .target(name:"L4",dependencies:["L0","L1","L2","L3"],path:"Sources/L4",exclude:["DESIGN.md"],swiftSettings:[.define("L4_ISOLATED_VERIFICATION")]),
 .target(name:"L0Fixtures",dependencies:["L0"],path:"Sources/L0Fixtures"),
 .target(name:"L1Fixtures",dependencies:["L0","L1"],path:"Sources/L1Fixtures"),
 .target(name:"L2Fixtures",dependencies:["L0","L1","L2"],path:"Sources/L2Fixtures"),
 .target(name:"L3Fixtures",dependencies:["L0","L1","L2","L3"],path:"Sources/L3Fixtures"),
 .executableTarget(name:"LayerBenchmark",dependencies:["L0","L1","L2","L3","L4"],path:"Sources/LayerBenchmark"),
 .testTarget(name:"L0ScalarTests",dependencies:["L0","L0Fixtures"],path:"LowerTests/L0"),
 .testTarget(name:"L1PolynomialTests",dependencies:["L0","L1","L1Fixtures"],path:"LowerTests/L1"),
 .testTarget(name:"L2Tests",dependencies:["L2Fixtures"],path:"LowerTests/L2"),
 .testTarget(name:"L3Tests",dependencies:["L3Fixtures","L0","L1","L2","L3"],path:"LowerTests/L3"),
 .target(name:"L4Fixtures",dependencies:["L0","L1","L2","L3","L4"],path:"Sources/L4Fixtures"),
 .executableTarget(name:"L4Proof",dependencies:["L4Fixtures","L0Fixtures","L1Fixtures","L2Fixtures","L3Fixtures"],path:"Sources/L4Proof"),
 .target(name:"KernelFixtures",dependencies:["L0","L1","L2","L3","L4","L1Fixtures"],path:"Sources/KernelFixtures"),
 .executableTarget(name:"KernelBenchmark",dependencies:["KernelFixtures"],path:"Sources/KernelBenchmark"),
 .executableTarget(name:"KernelProof",dependencies:["KernelFixtures"],path:"Sources/KernelProof"),
 .testTarget(name:"KernelTests",dependencies:["KernelFixtures"],path:"Tests"),
 .testTarget(name:"L4Tests",dependencies:["L4Fixtures","L0","L1","L2","L3","L4"],path:"TopologyTests")
])
