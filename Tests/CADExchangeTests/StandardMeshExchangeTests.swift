import Foundation
import Testing
import CADCore
import CADIR
@testable import CADExchange

@Suite("Standard mesh exchange")
struct StandardMeshExchangeTests {
    @Test(.timeLimit(.minutes(1)))
    func complexVRMLPolygonReturnsTypedResourceFailure() throws {
        let indices = Array(repeating: "0 1 2", count: 16_000).joined(separator: " ")
        let data = Data("#VRML V2.0 utf8\nShape { geometry IndexedFaceSet { coord Coordinate { point [0 0 0, 1 0 0, 0 1 0] } coordIndex [\(indices) -1] } }".utf8)
        do {
            _ = try OfficialFormatExchange(tolerance: .standard).import(data, as: .vrml)
            Issue.record("Polygon work exceeding a 32-bit range must be rejected.")
        } catch let error as KernelError {
            #expect(error.code == .resourceLimitExceeded)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func overflowingPLYFaceCountReturnsTypedResourceFailure() throws {
        let data = Data("""
        ply
        format ascii 1.0
        comment unit meter
        element vertex 3
        property float x
        property float y
        property float z
        element face \(Int.max)
        property list uchar int vertex_indices
        end_header

        """.utf8)
        let facade = OfficialFormatExchange(tolerance: .standard,
            standardMeshExchange: StandardMeshExchange(tolerance: .standard,
                resourceLimits: .init(maximumEntities: Int.max)))
        do {
            _ = try facade.import(data, as: .ply)
            Issue.record("An overflowing face declaration must be rejected.")
        } catch let error as KernelError {
            #expect(error.code == .resourceLimitExceeded)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func overflowingCombinedMeshStorageReturnsTypedResourceFailure() throws {
        var resources = try ExchangeResourceAccountant(
            limits: .init(maximumBytes: Int.max, maximumEntities: Int.max), format: .ply)
        do {
            try meshStorageAdmission(vertexCount: 1, indexCount: Int.max / 4, resources: &resources)
            Issue.record("Combined derived storage must reject integer overflow.")
        } catch let error as KernelError {
            #expect(error.code == .resourceLimitExceeded)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func independentGLTFInterleavedAttributesAndReflectedScene() throws {
        let data = try gltfFixture()
        let imported = try OfficialFormatExchange(tolerance: .standard).import(data, as: .gltf, explicitUnit: .inch)
        #expect(imported.units == .meters)
        let mesh = try #require(imported.meshes.values.first)
        #expect(mesh.positions == [Point3D(x: 4, y: 6, z: 8), Point3D(x: 2, y: 6, z: 8), Point3D(x: 4, y: 9, z: 8)])
        #expect(mesh.indices == [0, 2, 1])
        #expect(mesh.normals == Array(repeating: Vector3D(x: 0, y: 0, z: 1), count: 3))
        #expect(mesh.textureCoordinates == [Point2D(x: 0, y: 0), Point2D(x: 1, y: 0), Point2D(x: 0, y: 1)])
        #expect(mesh.vertexColors[0] == ColorRGBA(r: 1, g: 0, b: 0, a: 1))
        #expect(mesh.vertexColors[1] == ColorRGBA(r: 0, g: 1, b: 0, a: 1))
        try mesh.validate(tolerance: .standard)
    }

    @Test(.timeLimit(.minutes(1)))
    func independentGLBAndUnindexedPrimitives() throws {
        var json = try gltfFixtureObject()
        var buffers = try #require(json["buffers"] as? [[String: Any]])
        let uri = try #require(buffers[0]["uri"] as? String)
        var binary = try #require(Data(base64Encoded: String(uri.split(separator: ",")[1])))
        buffers[0].removeValue(forKey: "uri"); json["buffers"] = buffers
        var sourceMeshes = try #require(json["meshes"] as? [[String: Any]])
        var primitives = try #require(sourceMeshes[0]["primitives"] as? [[String: Any]])
        primitives[0].removeValue(forKey: "indices"); sourceMeshes[0]["primitives"] = primitives; json["meshes"] = sourceMeshes
        var encoded = try JSONSerialization.data(withJSONObject: json)
        while !encoded.count.isMultiple(of: 4) { encoded.append(32) }
        while !binary.count.isMultiple(of: 4) { binary.append(0) }
        var glb = Data()
        fixtureUInt32(0x46546c67, to: &glb); fixtureUInt32(2, to: &glb); fixtureUInt32(UInt32(28 + encoded.count + binary.count), to: &glb)
        fixtureUInt32(UInt32(encoded.count), to: &glb); fixtureUInt32(0x4e4f534a, to: &glb); glb.append(encoded)
        fixtureUInt32(UInt32(binary.count), to: &glb); fixtureUInt32(0x004e4942, to: &glb); glb.append(binary)
        let mesh = try #require(OfficialFormatExchange(tolerance: .standard).import(glb, as: .glb).meshes.values.first)
        #expect(mesh.positions[1].x == 2)
        #expect(mesh.indices == [0, 2, 1])
        var malformed = glb; malformed[8] = 0
        #expect(throws: ImportError.self) { _ = try StandardMeshExchange(tolerance: .standard).read(malformed, as: .glb) }
    }

    @Test(.timeLimit(.minutes(1)))
    func independentPLYPolygonUnitNormalsColorsAndBinaryEndianness() throws {
        let ascii = Data("""
        ply
        format ascii 1.0
        comment unit inch
        element vertex 4
        property double x
        property double y
        property double z
        property float nx
        property float ny
        property float nz
        property uchar red
        property uchar green
        property uchar blue
        element face 1
        property list uchar int vertex_indices
        end_header
        0 0 0 0 0 2 255 0 0
        1 0 0 0 0 2 0 255 0
        1 1 0 0 0 2 0 0 255
        0 1 0 0 0 2 255 255 255
        4 0 1 2 3

        """.utf8)
        let imported = try OfficialFormatExchange(tolerance: .standard).import(ascii, as: .ply, explicitUnit: .meter)
        let mesh = try #require(imported.meshes.values.first)
        #expect(imported.units.length == .inch)
        #expect(mesh.positions[1].x == 0.0254)
        #expect(mesh.indices.count == 6)
        #expect(mesh.normals[0].z == 1)
        #expect(mesh.vertexColors[2].b == 1)
        for little in [true, false] {
            let binary = plyBinaryFixture(little: little)
            let model = try StandardMeshExchange(tolerance: .standard).read(binary, as: .ply, explicitUnit: .millimeter)
            let parsed = try #require(model.meshes.values.first)
            #expect(parsed.positions[1] == Point3D(x: 0.001, y: 0, z: 0))
            #expect(parsed.indices == [0, 1, 2])
            #expect(parsed.normals[2] == Vector3D(x: 0, y: 0, z: 1))
        }
        #expect(throws: ImportError.self) { _ = try StandardMeshExchange(tolerance: .standard).read(plyBinaryFixture(little: true), as: .ply) }
    }

    @Test(.timeLimit(.minutes(1)))
    func independentVRMLNestedTransformInstancingAndSeparateAttributeIndices() throws {
        let data = Data("""
        #VRML V2.0 utf8
        DEF triangle Shape {
          geometry IndexedFaceSet {
            coord Coordinate { point [0 0 0, 1 0 0, 0 1 0] }
            coordIndex [0 1 2 -1]
            normalPerVertex FALSE
            normal Normal { vector [0 0 1] }
            normalIndex [0]
            colorPerVertex FALSE
            color Color { color [1 0 0] }
            texCoord TextureCoordinate { point [0 0, 1 0, 0 1] }
            texCoordIndex [1 2 0 -1]
          }
        }
        Group { children [
          Transform { translation 2 3 4 scale 2 3 1 children [USE triangle] }
        ] }

        """.utf8)
        let imported = try OfficialFormatExchange(tolerance: .standard).import(data, as: .vrml, explicitUnit: .foot)
        #expect(imported.units == .meters)
        #expect(imported.meshes.count == 2)
        let transformed = try #require(imported.meshes.values.first { $0.positions[0].z == 4 })
        #expect(transformed.positions == [Point3D(x: 2, y: 3, z: 4), Point3D(x: 4, y: 3, z: 4), Point3D(x: 2, y: 6, z: 4)])
        #expect(transformed.normals[0].z == 1)
        #expect(transformed.textureCoordinates == [Point2D(x: 1, y: 0), Point2D(x: 0, y: 1), Point2D(x: 0, y: 0)])
        #expect(transformed.vertexColors.allSatisfy { $0.r == 1 && $0.g == 0 })
        try transformed.validate(tolerance: .standard)
    }

    @Test(.timeLimit(.minutes(1)))
    func gltfNormalInverseTransposeAndQuaternionPlacement() throws {
        let mesh = Mesh(positions: [Point3D(x: 0, y: 0, z: 0), Point3D(x: 1, y: 0, z: 0), Point3D(x: 0, y: 1, z: 1)],
                        normals: Array(repeating: Vector3D(x: 0, y: -1/sqrt(2), z: 1/sqrt(2)), count: 3), indices: [0, 1, 2])
        let exchange = StandardMeshExchange(tolerance: .standard)
        let sink = DataByteSink(); try exchange.write(meshes: [BodyID(): mesh], as: .gltf, to: sink)
        var object = try #require(JSONSerialization.jsonObject(with: sink.bytes) as? [String: Any])
        object["nodes"] = [["mesh": 0, "scale": [2, 3, 4], "rotation": [0, 0, sin(Double.pi/4), cos(Double.pi/4)]]]
        let result = try #require(exchange.read(JSONSerialization.data(withJSONObject: object), as: .gltf).meshes.values.first)
        let expected = Vector3D(x: 1.0/3, y: 0, z: 1.0/4)
        #expect((result.normals[0] - expected / expected.length).length < 1e-7)
        #expect(abs(result.positions[1].y - 2) < 1e-12)
        try result.validate(tolerance: .standard)
    }

    @Test(.timeLimit(.minutes(1)))
    func roundTripsAllFormatsPreserveMeshAttributesAndUnits() throws {
        let original = standardTriangle()
        let exchange = StandardMeshExchange(tolerance: .standard)
        for format: ExchangeFileFormat in [.glb, .gltf, .ply, .vrml] {
            let sink = DataByteSink()
            try exchange.write(meshes: [BodyID(): original], as: format, unit: .inch, to: sink)
            let model = try exchange.read(sink.bytes, as: format)
            let result = try #require(model.meshes.values.first)
            #expect(model.units.length == (format == .ply ? .inch : .meter))
            #expect(result.indices == original.indices)
            #expect(zip(result.positions, original.positions).allSatisfy { ($0 - $1).length < 1e-7 })
            #expect(result.normals == original.normals)
            #expect(result.textureCoordinates == original.textureCoordinates)
            #expect(result.vertexColors == original.vertexColors)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func unsupportedSemanticsAndMalformedReferencesAreTypedFailures() throws {
        let exchange = StandardMeshExchange(tolerance: .standard)
        for key in ["materials", "animations", "skins", "extensions", "textures"] {
            var object = try gltfFixtureObject(); object[key] = []
            #expect(throws: ImportError.self) { _ = try exchange.read(JSONSerialization.data(withJSONObject: object), as: .gltf) }
        }
        var source = try gltfFixtureObject(); source["scenes"] = [["nodes": [0]], ["nodes": [0]]]
        #expect(throws: ImportError.self) { _ = try exchange.read(JSONSerialization.data(withJSONObject: source), as: .gltf) }
        source = try gltfFixtureObject(); source["nodes"] = [["children": [0]]]
        #expect(throws: ImportError.self) { _ = try exchange.read(JSONSerialization.data(withJSONObject: source), as: .gltf) }
        source = try gltfFixtureObject(); var accessors = try #require(source["accessors"] as? [[String: Any]]); accessors[0]["count"] = Int.max; source["accessors"] = accessors
        #expect(throws: ImportError.self) { _ = try exchange.read(JSONSerialization.data(withJSONObject: source), as: .gltf) }
        source = try gltfFixtureObject(); source["nodes"] = [["mesh": 0, "scale": [0, 1, 1]]]
        #expect(throws: ImportError.self) { _ = try exchange.read(JSONSerialization.data(withJSONObject: source), as: .gltf) }
        #expect(throws: ImportError.self) { _ = try exchange.read(Data("#VRML V2.0 utf8\nShape { appearance Appearance {} }".utf8), as: .vrml) }
        #expect(throws: ImportError.self) { _ = try exchange.read(Data("#VRML V2.0 utf8\nTransform { children [ USE missing ] }".utf8), as: .vrml) }
        var materialMesh = standardTriangle(); materialMesh.material = MaterialID()
        for format: ExchangeFileFormat in [.glb, .gltf, .ply, .vrml] {
            let sink = DataByteSink()
            #expect(throws: ExportError.self) { try exchange.write(meshes: [BodyID(): materialMesh], as: format, to: sink) }
            #expect(sink.bytes.isEmpty)
        }
        var alphaMesh = standardTriangle(); alphaMesh.vertexColors[0].a = 0.5
        for format in [ExchangeFileFormat.glb, .gltf, .vrml] {
            let sink = DataByteSink()
            #expect(throws: ExportError.self) { try exchange.write(meshes: [BodyID(): alphaMesh], as: format, to: sink) }
            #expect(sink.bytes.isEmpty)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func boundedAdmissionAndCancellationNeverPublishPartialOutput() async throws {
        let fixture = try gltfFixture()
        for limits in [ExchangeResourceLimits(maximumBytes: 10), ExchangeResourceLimits(maximumEntities: 4),
                       ExchangeResourceLimits(maximumNesting: 2), ExchangeResourceLimits(maximumIterations: 10),
                       ExchangeResourceLimits(maximumProcessingDuration: .nanoseconds(1))] {
            let exchange = StandardMeshExchange(tolerance: .standard, resourceLimits: limits)
            #expect(throws: KernelError.self) { _ = try exchange.read(fixture, as: .gltf) }
        }
        let sink = DataByteSink()
        #expect(throws: KernelError.self) { try StandardMeshExchange(tolerance: .standard, resourceLimits: .init(maximumBytes: 10)).write(meshes: [BodyID(): standardTriangle()], as: .glb, to: sink) }
        #expect(sink.bytes.isEmpty)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try StandardMeshExchange(tolerance: .standard).read(fixture, as: .gltf)
        }
        do { _ = try await task.value; Issue.record("Cancelled exchange succeeded.") }
        catch is CancellationError { }
        catch { Issue.record("Cancellation was converted into \(error).") }
    }

    @Test(.timeLimit(.minutes(1)))
    func externalBufferURLFacadeAndDirectoryContainment() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("standard-mesh-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record("Fixture cleanup failed: \(error)") } }
        var object = try gltfFixtureObject()
        var buffers = try #require(object["buffers"] as? [[String: Any]])
        let uri = try #require(buffers[0]["uri"] as? String)
        let binary = try #require(Data(base64Encoded: String(uri.split(separator: ",")[1])))
        try binary.write(to: directory.appendingPathComponent("mesh.bin"))
        buffers[0]["uri"] = "mesh.bin"; object["buffers"] = buffers
        let url = directory.appendingPathComponent("mesh.gltf")
        try JSONSerialization.data(withJSONObject: object).write(to: url)
        let facade = OfficialFormatExchange(tolerance: .standard)
        let mesh = try #require(facade.import(from: url).meshes.values.first)
        #expect(mesh.positions[2] == Point3D(x: 4, y: 9, z: 8))
        #expect(throws: ImportError.self) { _ = try facade.import(JSONSerialization.data(withJSONObject: object), as: .gltf) }
        for unsafeURI in ["../outside.bin", "%2e%2e/outside.bin", "https://example.com/mesh.bin", "/mesh.bin"] {
            buffers[0]["uri"] = unsafeURI; object["buffers"] = buffers
            try JSONSerialization.data(withJSONObject: object).write(to: url)
            #expect(throws: ImportError.self) { _ = try facade.import(from: url) }
        }
    }
}

private func standardTriangle() -> Mesh {
    Mesh(positions: [Point3D(x: 0, y: 0, z: 0), Point3D(x: 1, y: 0, z: 0), Point3D(x: 0, y: 1, z: 0)],
         normals: Array(repeating: Vector3D(x: 0, y: 0, z: 1), count: 3), indices: [0, 1, 2],
         textureCoordinates: [Point2D(x: 0, y: 0), Point2D(x: 1, y: 0), Point2D(x: 0, y: 1)],
         vertexColors: Array(repeating: ColorRGBA(r: 1, g: 0, b: 0, a: 1), count: 3))
}

private func gltfFixture() throws -> Data { try JSONSerialization.data(withJSONObject: gltfFixtureObject()) }

private func gltfFixtureObject() throws -> [String: Any] {
    var binary = Data()
    for tuple: [Float] in [[0, 0, 0, 0, 0, 1, 0, 0], [1, 0, 0, 0, 0, 1, 1, 0], [0, 1, 0, 0, 0, 1, 0, 1]] {
        for v in tuple { fixtureUInt32(v.bitPattern, to: &binary) }
    }
    binary.append(contentsOf: [255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255])
    binary.append(contentsOf: [0, 0, 1, 0, 2, 0])
    return ["asset": ["version": "2.0"],
            "buffers": [["byteLength": binary.count, "uri": "data:application/octet-stream;base64," + binary.base64EncodedString()]],
            "bufferViews": [["buffer": 0, "byteOffset": 0, "byteLength": 96, "byteStride": 32],
                            ["buffer": 0, "byteOffset": 96, "byteLength": 12], ["buffer": 0, "byteOffset": 108, "byteLength": 6]],
            "accessors": [["bufferView": 0, "byteOffset": 0, "componentType": 5126, "count": 3, "type": "VEC3"],
                          ["bufferView": 0, "byteOffset": 12, "componentType": 5126, "count": 3, "type": "VEC3"],
                          ["bufferView": 0, "byteOffset": 24, "componentType": 5126, "count": 3, "type": "VEC2"],
                          ["bufferView": 1, "componentType": 5121, "count": 3, "type": "VEC4", "normalized": true],
                          ["bufferView": 2, "componentType": 5123, "count": 3, "type": "SCALAR"]],
            "meshes": [["primitives": [["attributes": ["POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2, "COLOR_0": 3], "indices": 4]]]],
            "nodes": [["translation": [1, 2, 3], "children": [1]], ["mesh": 0, "translation": [3, 4, 5], "scale": [-2, 3, 1]]],
            "scenes": [["nodes": [0]]], "scene": 0]
}

private func fixtureUInt32(_ value: UInt32, to data: inout Data, little: Bool = true) {
    var v = little ? value.littleEndian : value.bigEndian
    Swift.withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
}

private func plyBinaryFixture(little: Bool) -> Data {
    var data = Data("""
    ply
    format binary_\(little ? "little" : "big")_endian 1.0
    element vertex 3
    property float z
    property float x
    property float y
    property float nx
    property float ny
    property float nz
    element face 1
    property list uchar int vertex_indices
    end_header

    """.utf8)
    for values: [Float] in [[0, 0, 0, 0, 0, 1], [0, 1, 0, 0, 0, 1], [0, 0, 1, 0, 0, 1]] {
        for value in values { fixtureUInt32(value.bitPattern, to: &data, little: little) }
    }
    data.append(3)
    for index: UInt32 in [0, 1, 2] { fixtureUInt32(index, to: &data, little: little) }
    return data
}
