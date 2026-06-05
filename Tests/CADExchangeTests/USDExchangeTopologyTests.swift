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
    func importPreservesVertexInterpolatedNormals() throws {
        let data = Data("""
        #usda 1.0
        (
            defaultPrim = "Triangle"
            metersPerUnit = 1
            upAxis = "Z"
        )

        def Mesh "Triangle"
        {
            point3f[] points = [(0, 0, 0), (1, 0, 0), (0, 1, 0)]
            normal3f[] normals = [(0, 0, 1), (0, 0, 1), (0, 0, 1)] (
                interpolation = "vertex"
            )
            int[] faceVertexCounts = [3]
            int[] faceVertexIndices = [0, 1, 2]
            uniform token subdivisionScheme = "none"
        }
        """.utf8)

        let model = try USDExchange(importBackend: .pureSwift).import(BorrowedBytes(data), as: .usda)

        let mesh = try #require(model.meshes.values.first)
        #expect(mesh.normals == Array(repeating: Vector3D.unitZ, count: 3))
    }

    @Test(.timeLimit(.minutes(1)))
    func importConvertsLeftHandedOrientationToRightHandedWinding() throws {
        let data = Data("""
        #usda 1.0
        (
            defaultPrim = "Triangle"
            metersPerUnit = 1
            upAxis = "Z"
        )

        def Mesh "Triangle"
        {
            uniform token orientation = "leftHanded"
            point3f[] points = [(0, 0, 0), (1, 0, 0), (0, 1, 0)]
            normal3f[] normals = [(0, 0, -1), (0, 0, -1), (0, 0, -1)] (
                interpolation = "vertex"
            )
            int[] faceVertexCounts = [3]
            int[] faceVertexIndices = [0, 1, 2]
            uniform token subdivisionScheme = "none"
        }
        """.utf8)

        let model = try USDExchange(importBackend: .pureSwift).import(BorrowedBytes(data), as: .usda)

        let mesh = try #require(model.meshes.values.first)
        #expect(mesh.indices == [0, 2, 1])
        #expect(mesh.normals == Array(repeating: Vector3D(x: 0, y: 0, z: -1), count: 3))
    }

    @Test(.timeLimit(.minutes(1)))
    func importConvertsYUpSceneToZUpMesh() throws {
        let data = Data("""
        #usda 1.0
        (
            defaultPrim = "Triangle"
            metersPerUnit = 1
            upAxis = "Y"
        )

        def Mesh "Triangle"
        {
            point3f[] points = [(0, 0, 0), (0, 0, 1), (1, 0, 0)]
            normal3f[] normals = [(0, 1, 0), (0, 1, 0), (0, 1, 0)] (
                interpolation = "vertex"
            )
            int[] faceVertexCounts = [3]
            int[] faceVertexIndices = [0, 1, 2]
            uniform token subdivisionScheme = "none"
        }
        """.utf8)

        let model = try USDExchange(importBackend: .pureSwift).import(BorrowedBytes(data), as: .usda)

        let mesh = try #require(model.meshes.values.first)
        #expect(mesh.positions == [
            Point3D(x: 0, y: 0, z: 0),
            Point3D(x: 0, y: -1, z: 0),
            Point3D(x: 1, y: 0, z: 0),
        ])
        #expect(mesh.normals == Array(repeating: Vector3D.unitZ, count: 3))
        #expect(mesh.indices == [0, 1, 2])
    }

    @Test(.timeLimit(.minutes(1)))
    func importRejectsSubdivisionSurfaceUntilTessellationExists() throws {
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
            uniform token subdivisionScheme = "catmullClark"
        }
        """.utf8)

        #expect(throws: ImportError.self) {
            _ = try USDExchange(importBackend: .pureSwift).import(BorrowedBytes(data), as: .usda)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func importRejectsMissingSubdivisionSchemeAsOpenUSDFallback() throws {
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
        }
        """.utf8)

        #expect(throws: ImportError.self) {
            _ = try USDExchange(importBackend: .pureSwift).import(BorrowedBytes(data), as: .usda)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func importRejectsTextureCoordinatesUntilMeshUVSupportExists() throws {
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
            texCoord2f[] primvars:st = [(0, 0), (1, 0), (1, 1), (0, 1)] (
                interpolation = "faceVarying"
            )
            int[] primvars:st:indices = [0, 1, 2, 3]
            uniform token subdivisionScheme = "none"
        }
        """.utf8)

        #expect(throws: ImportError.self) {
            _ = try USDExchange(importBackend: .pureSwift).import(BorrowedBytes(data), as: .usda)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func importRejectsFaceVaryingNormalsUntilMeshExpansionExists() throws {
        let data = Data("""
        #usda 1.0
        (
            defaultPrim = "Triangle"
            metersPerUnit = 1
            upAxis = "Z"
        )

        def Mesh "Triangle"
        {
            point3f[] points = [(0, 0, 0), (1, 0, 0), (0, 1, 0)]
            normal3f[] normals = [(0, 0, 1), (0, 0, 1), (0, 0, 1)] (
                interpolation = "faceVarying"
            )
            int[] faceVertexCounts = [3]
            int[] faceVertexIndices = [0, 1, 2]
            uniform token subdivisionScheme = "none"
        }
        """.utf8)

        #expect(throws: ImportError.self) {
            _ = try USDExchange(importBackend: .pureSwift).import(BorrowedBytes(data), as: .usda)
        }
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
