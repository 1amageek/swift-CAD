import Foundation
import Testing
import CADCore
import CADIR
@testable import CADExchange

@Suite("USD Exchange Topology")
struct USDExchangeTopologyTests {
    @Test(.timeLimit(.minutes(1)))
    func importTriangulatesQuadFacesWithFanTopology() throws {
        let data = Data("""
        #usda 1.0
        (
            defaultPrim = "Quad"
            metersPerUnit = 1
            upAxis = "Z"
        )

        def Mesh "Quad"
        {
            point3f[] points = [(0, 0, 0), (1, 0, 0), (1, 1, 0), (0, 1, 0)]
            int[] faceVertexCounts = [4]
            int[] faceVertexIndices = [0, 1, 2, 3]
            uniform token subdivisionScheme = "none"
        }
        """.utf8)

        let model = try USDExchange(importBackend: .pureSwift).import(BorrowedBytes(data), as: .usda)

        #expect(model.meshes.count == 1)
        let mesh = try #require(model.meshes.values.first)
        #expect(mesh.positions.count == 4)
        #expect(mesh.indices == [0, 1, 2, 0, 2, 3])
    }

    @Test(.timeLimit(.minutes(1)))
    func importRejectsFaceWithTooFewVertices() throws {
        let data = Data("""
        #usda 1.0
        (
            defaultPrim = "Line"
            metersPerUnit = 1
            upAxis = "Z"
        )

        def Mesh "Line"
        {
            point3f[] points = [(0, 0, 0), (1, 0, 0), (0, 1, 0)]
            int[] faceVertexCounts = [2]
            int[] faceVertexIndices = [0, 1]
            uniform token subdivisionScheme = "none"
        }
        """.utf8)

        #expect(throws: ImportError.self) {
            _ = try USDExchange(importBackend: .pureSwift).import(BorrowedBytes(data), as: .usda)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func importRejectsMismatchedFaceVertexIndexCount() throws {
        let data = Data("""
        #usda 1.0
        (
            defaultPrim = "Broken"
            metersPerUnit = 1
            upAxis = "Z"
        )

        def Mesh "Broken"
        {
            point3f[] points = [(0, 0, 0), (1, 0, 0), (0, 1, 0)]
            int[] faceVertexCounts = [3]
            int[] faceVertexIndices = [0, 1]
            uniform token subdivisionScheme = "none"
        }
        """.utf8)

        #expect(throws: ImportError.self) {
            _ = try USDExchange(importBackend: .pureSwift).import(BorrowedBytes(data), as: .usda)
        }
    }
}
