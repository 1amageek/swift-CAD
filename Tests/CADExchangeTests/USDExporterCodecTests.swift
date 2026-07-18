import Foundation
import Testing
import CADCore
import CADIR
@testable import CADExchange

@Suite("USD Exporter Codecs")
struct USDExporterCodecTests {
    @Test(.timeLimit(.minutes(1)))
    func typedPureSwiftCodecsRoundTripMeshAttributes() throws {
        let sourceMesh = Mesh(
            positions: [
                Point3D(x: 0.0, y: 0.0, z: 0.0),
                Point3D(x: 1.0, y: 0.0, z: 0.0),
                Point3D(x: 0.0, y: 1.0, z: 0.0),
            ],
            normals: Array(repeating: .unitZ, count: 3),
            indices: [0, 1, 2],
            textureCoordinates: [
                Point2D(x: 0.0, y: 0.0),
                Point2D(x: 1.0, y: 0.0),
                Point2D(x: 0.0, y: 1.0),
            ],
            vertexColors: [
                ColorRGBA(r: 1.0, g: 0.0, b: 0.0, a: 1.0),
                ColorRGBA(r: 0.0, g: 1.0, b: 0.0, a: 0.75),
                ColorRGBA(r: 0.0, g: 0.0, b: 1.0, a: 0.5),
            ]
        )

        for encoding in [USDEncoding.usd, .usda, .usdc, .usdz] {
            let sink = DataByteSink()
            try USDExporter(tolerance: .standard).write(
                meshes: [BodyID(): sourceMesh],
                encoding: encoding,
                unit: .meter,
                to: sink
            )
            let data = sink.bytes
            switch encoding {
            case .usd, .usda:
                #expect(data.starts(with: Data("#usda 1.0".utf8)))
            case .usdc:
                #expect(data.starts(with: Data("PXR-USDC".utf8)))
            case .usdz:
                #expect(data.starts(with: Data([0x50, 0x4b])))
            }
            let format: ExchangeFileFormat = switch encoding {
            case .usd: .usd
            case .usda: .usda
            case .usdc: .usdc
            case .usdz: .usdz
            }
            let imported = try USDExchange(tolerance: .standard).import(BorrowedBytes(data), as: format)
            let roundTrippedMesh = try #require(imported.meshes.values.first)
            #expect(roundTrippedMesh.positions == sourceMesh.positions)
            #expect(roundTrippedMesh.normals == sourceMesh.normals)
            #expect(roundTrippedMesh.indices == sourceMesh.indices)
            #expect(roundTrippedMesh.textureCoordinates == sourceMesh.textureCoordinates)
            #expect(roundTrippedMesh.vertexColors.count == sourceMesh.vertexColors.count)
            for (actual, expected) in zip(roundTrippedMesh.vertexColors, sourceMesh.vertexColors) {
                #expect(abs(actual.r - expected.r) < 1.0e-6)
                #expect(abs(actual.g - expected.g) < 1.0e-6)
                #expect(abs(actual.b - expected.b) < 1.0e-6)
                #expect(abs(actual.a - expected.a) < 1.0e-6)
            }
        }
    }
}
