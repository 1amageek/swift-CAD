import Foundation
import Testing
import CADUSD
import CADUSDC
import CADUSDZ

@Suite("CADUSD")
struct CADUSDTests {
    @Test(.timeLimit(.minutes(1)))
    func usdcReaderReadsBootstrapAndTableOfContents() throws {
        let data = makeUSDCFixture(sections: [
            ("TOKENS", Data([0x01])),
            ("STRINGS", Data([0x02])),
            ("FIELDS", Data([0x03])),
            ("FIELDSETS", Data([0x04])),
            ("PATHS", Data([0x05])),
            ("SPECS", Data([0x06])),
        ])

        let crate = try USDCReader().readCrate(from: data)

        #expect(crate.version == USDCCrateVersion(major: 0, minor: 8, patch: 0))
        #expect(crate.tableOfContentsOffset > USDCCrateFile.bootstrapByteCount)
        #expect(crate.sections.map(\.name) == ["TOKENS", "STRINGS", "FIELDS", "FIELDSETS", "PATHS", "SPECS"])
        #expect(crate.section(named: "TOKENS")?.size == 1)
        try crate.requireStructuralSections()
    }

    @Test(.timeLimit(.minutes(1)))
    func usdcReaderReadsUncompressedLegacyTokens() throws {
        let tokenBytes = nullSeparatedTokenData(["", "Mesh", "points"])
        let tokenSection = makeUSDCTokenSection(version: USDCCrateVersion(major: 0, minor: 3, patch: 0), tokenData: tokenBytes)
        let data = makeUSDCFixture(
            version: USDCCrateVersion(major: 0, minor: 3, patch: 0),
            sections: [
                ("TOKENS", tokenSection),
            ]
        )

        let crate = try USDCReader().readCrate(from: data)

        #expect(try crate.readTokens() == ["", "Mesh", "points"])
    }

    @Test(.timeLimit(.minutes(1)))
    func usdcReaderReadsCompressedTokens() throws {
        let tokenBytes = nullSeparatedTokenData(["", "Mesh", "faceVertexIndices", "subdivisionScheme"])
        let tokenSection = makeUSDCTokenSection(version: USDCCrateVersion(major: 0, minor: 8, patch: 0), tokenData: tokenBytes)
        let data = makeUSDCFixture(sections: [
            ("TOKENS", tokenSection),
        ])

        let crate = try USDCReader().readCrate(from: data)

        #expect(try crate.readTokens() == ["", "Mesh", "faceVertexIndices", "subdivisionScheme"])
    }

    @Test(.timeLimit(.minutes(1)))
    func usdcReaderReadsCompressedStringFieldAndFieldSetTables() throws {
        let version = USDCCrateVersion(major: 0, minor: 8, patch: 0)
        let tokenBytes = nullSeparatedTokenData(["", "specifier", "points", "faceVertexIndices"])
        let fields = [
            USDCCrateField(
                tokenIndex: 1,
                valueRep: USDCCrateValueRep(type: .specifier, isInlined: true, isArray: false, payload: 2)
            ),
            USDCCrateField(
                tokenIndex: 2,
                valueRep: USDCCrateValueRep(type: .vec3f, isInlined: false, isArray: true, payload: 128)
            ),
        ]
        let data = makeUSDCFixture(version: version, sections: [
            ("TOKENS", makeUSDCTokenSection(version: version, tokenData: tokenBytes)),
            ("STRINGS", makeUSDCStringsSection([1, 2])),
            ("FIELDS", makeUSDCFieldsSection(version: version, fields: fields)),
            ("FIELDSETS", makeUSDCFieldSetsSection(version: version, indexes: [0, 1, UInt32.max])),
        ])

        let crate = try USDCReader().readCrate(from: data)

        #expect(try crate.readStringTokenIndexes() == [1, 2])
        #expect(try crate.readStrings() == ["specifier", "points"])
        let parsedFields = try crate.readFields()
        #expect(parsedFields == fields)
        #expect(parsedFields[0].valueRep.type == .specifier)
        #expect(parsedFields[0].valueRep.isInlined)
        #expect(parsedFields[1].valueRep.type == .vec3f)
        #expect(parsedFields[1].valueRep.isArray)
        #expect(parsedFields[1].valueRep.payload == 128)
        #expect(try crate.readFieldSetIndexes() == [0, 1, UInt32.max])
        #expect(try crate.readFieldSets() == [[0, 1]])
    }

    @Test(.timeLimit(.minutes(1)))
    func usdcReaderReadsCompressedPathAndSpecTables() throws {
        let version = USDCCrateVersion(major: 0, minor: 8, patch: 0)
        let tokenBytes = nullSeparatedTokenData(["", "Root", "points", "specifier", "typeName"])
        let fields = [
            USDCCrateField(
                tokenIndex: 3,
                valueRep: USDCCrateValueRep(type: .specifier, isInlined: true, isArray: false, payload: 2)
            ),
            USDCCrateField(
                tokenIndex: 4,
                valueRep: USDCCrateValueRep(type: .token, isInlined: true, isArray: false, payload: 1)
            ),
        ]
        let specs = [
            USDCCrateSpec(pathIndex: 0, fieldSetIndex: 0, specType: .pseudoRoot),
            USDCCrateSpec(pathIndex: 1, fieldSetIndex: 0, specType: .prim),
            USDCCrateSpec(pathIndex: 2, fieldSetIndex: 2, specType: .attribute),
        ]
        let data = makeUSDCFixture(version: version, sections: [
            ("TOKENS", makeUSDCTokenSection(version: version, tokenData: tokenBytes)),
            ("STRINGS", makeUSDCStringsSection([])),
            ("FIELDS", makeUSDCFieldsSection(version: version, fields: fields)),
            ("FIELDSETS", makeUSDCFieldSetsSection(version: version, indexes: [0, UInt32.max, 1, UInt32.max])),
            ("PATHS", makeUSDCCompressedPathsSection(
                pathCount: 3,
                pathIndexes: [0, 1, 2],
                elementTokenIndexes: [0, 1, -2],
                jumps: [-1, -1, -2]
            )),
            ("SPECS", makeUSDCSpecsSection(version: version, specs: specs)),
        ])

        let crate = try USDCReader().readCrate(from: data)

        #expect(try crate.readPaths() == ["/", "/Root", "/Root.points"])
        #expect(try crate.readSpecs() == specs)
    }

    @Test(.timeLimit(.minutes(1)))
    func usdcSceneReaderMaterializesMeshExchangeScene() throws {
        let fixture = makeUSDCMeshSceneFixture()

        let scene = try USDCReader().read(from: fixture)

        #expect(scene.defaultPrim == "Triangle")
        #expect(scene.metersPerUnit == 1)
        #expect(scene.upAxis == .z)
        #expect(scene.meshes.count == 1)
        let mesh = try #require(scene.meshes.first)
        #expect(mesh.name == "Triangle")
        #expect(mesh.points == [
            USDPoint3D(x: 0, y: 0, z: 0),
            USDPoint3D(x: 1, y: 0, z: 0),
            USDPoint3D(x: 0, y: 1, z: 0),
        ])
        #expect(mesh.faceVertexCounts == [3])
        #expect(mesh.faceVertexIndices == [0, 1, 2])
        #expect(mesh.subdivisionScheme == "none")
    }

    @Test(.timeLimit(.minutes(1)))
    func generatedUSDCMeshFixtureMaterializesMeshExchangeScene() throws {
        let fixture = try generatedFixture("minimal_mesh.usdc")

        let scene = try USDCReader().read(from: fixture)

        #expect(scene.defaultPrim == "Triangle")
        #expect(scene.metersPerUnit == 1)
        #expect(scene.upAxis == .z)
        #expect(scene.meshes.count == 1)
        let mesh = try #require(scene.meshes.first)
        #expect(mesh.name == "Triangle")
        #expect(mesh.points == [
            USDPoint3D(x: 0, y: 0, z: 0),
            USDPoint3D(x: 1, y: 0, z: 0),
            USDPoint3D(x: 0, y: 1, z: 0),
        ])
        #expect(mesh.faceVertexCounts == [3])
        #expect(mesh.faceVertexIndices == [0, 1, 2])
        #expect(mesh.subdivisionScheme == "none")
        #expect(mesh.extent == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func generatedUSDCPoint3DMeshFixtureReadsDoublePrecisionPoints() throws {
        let fixture = try generatedFixture("point3d_mesh.usdc")

        let scene = try USDCReader().read(from: fixture)

        #expect(scene.defaultPrim == "Triangle")
        #expect(scene.metersPerUnit == 1)
        #expect(scene.upAxis == .z)
        #expect(scene.meshes.count == 1)
        let mesh = try #require(scene.meshes.first)
        #expect(mesh.name == "Triangle")
        #expect(mesh.points.count == 3)
        #expect(mesh.points[0] == USDPoint3D(x: 0, y: 0, z: 0))
        let highPrecisionX = 12345.6789012345
        let highPrecisionY = 0.12345678901234568
        #expect(abs(mesh.points[1].x - highPrecisionX) <= 1.0e-12)
        #expect(abs(mesh.points[2].y - highPrecisionY) <= 1.0e-15)
        #expect(abs(mesh.points[1].x - Double(Float32(highPrecisionX))) > 1.0e-5)
        #expect(abs(mesh.points[2].y - Double(Float32(highPrecisionY))) > 1.0e-10)
        #expect(mesh.faceVertexCounts == [3])
        #expect(mesh.faceVertexIndices == [0, 1, 2])
        #expect(mesh.subdivisionScheme == "none")
    }

    @Test(.timeLimit(.minutes(1)))
    func usdcSceneReaderReadsCompressedVec3fPointArray() throws {
        let fixture = makeUSDCMeshSceneFixture(compressedPoints: true)
        let crate = try USDCReader().readCrate(from: fixture)
        let pointsValueRep = try defaultFieldValueRep(in: crate, atPath: "/Triangle.points")

        #expect(pointsValueRep.type == .vec3f)
        #expect(pointsValueRep.isArray)
        #expect(pointsValueRep.isCompressed)

        let scene = try USDCReader().read(from: fixture)

        #expect(scene.defaultPrim == "Triangle")
        #expect(scene.meshes.count == 1)
        let mesh = try #require(scene.meshes.first)
        #expect(mesh.points == [
            USDPoint3D(x: 0, y: 0, z: 0),
            USDPoint3D(x: 1, y: 0, z: 0),
            USDPoint3D(x: 0, y: 1, z: 0),
        ])
        #expect(mesh.faceVertexCounts == [3])
        #expect(mesh.faceVertexIndices == [0, 1, 2])
        #expect(mesh.subdivisionScheme == "none")
    }

    @Test(.timeLimit(.minutes(1)))
    func generatedUSDCTranslatedMeshFixtureAppliesParentXform() throws {
        let fixture = try generatedFixture("translated_mesh.usdc")

        let scene = try USDCReader().read(from: fixture)

        #expect(scene.defaultPrim == "Root")
        #expect(scene.metersPerUnit == 1)
        #expect(scene.upAxis == .z)
        #expect(scene.meshes.count == 1)
        let mesh = try #require(scene.meshes.first)
        #expect(mesh.name == "Triangle")
        #expect(mesh.points == [
            USDPoint3D(x: 2, y: 3, z: 4),
            USDPoint3D(x: 3, y: 3, z: 4),
            USDPoint3D(x: 2, y: 4, z: 4),
        ])
        #expect(mesh.faceVertexCounts == [3])
        #expect(mesh.faceVertexIndices == [0, 1, 2])
        #expect(mesh.subdivisionScheme == "none")
    }

    @Test(.timeLimit(.minutes(1)))
    func generatedUSDCInvertedPivotFixtureAppliesInverseXformOp() throws {
        let fixture = try generatedFixture("inverted_pivot_mesh.usdc")

        let scene = try USDCReader().read(from: fixture)

        #expect(scene.defaultPrim == "Root")
        #expect(scene.metersPerUnit == 1)
        #expect(scene.upAxis == .z)
        #expect(scene.meshes.count == 1)
        let mesh = try #require(scene.meshes.first)
        #expect(mesh.name == "Triangle")
        expectPointsApproximatelyEqual(mesh.points, [
            USDPoint3D(x: 1, y: 1, z: 0),
            USDPoint3D(x: 1, y: 2, z: 0),
            USDPoint3D(x: 0, y: 1, z: 0),
        ])
        #expect(mesh.faceVertexCounts == [3])
        #expect(mesh.faceVertexIndices == [0, 1, 2])
        #expect(mesh.subdivisionScheme == "none")
    }

    @Test(.timeLimit(.minutes(1)))
    func usdaReaderReadsAuthoredMeshExtent() throws {
        let fixture = try generatedFixture("extent_mesh.usda")

        let scene = try USDAReader().read(from: fixture)

        let mesh = try #require(scene.meshes.first)
        #expect(mesh.extent == [
            USDPoint3D(x: 0, y: 0, z: 0),
            USDPoint3D(x: 1, y: 1, z: 0),
        ])
    }

    @Test(.timeLimit(.minutes(1)))
    func generatedUSDCExtentMeshFixtureReadsAuthoredExtent() throws {
        let fixture = try generatedFixture("extent_mesh.usdc")

        let scene = try USDCReader().read(from: fixture)

        #expect(scene.defaultPrim == "Triangle")
        #expect(scene.metersPerUnit == 1)
        #expect(scene.upAxis == .z)
        #expect(scene.meshes.count == 1)
        let mesh = try #require(scene.meshes.first)
        #expect(mesh.name == "Triangle")
        #expect(mesh.extent == [
            USDPoint3D(x: 0, y: 0, z: 0),
            USDPoint3D(x: 1, y: 1, z: 0),
        ])
        #expect(mesh.points == [
            USDPoint3D(x: 0, y: 0, z: 0),
            USDPoint3D(x: 1, y: 0, z: 0),
            USDPoint3D(x: 0, y: 1, z: 0),
        ])
        #expect(mesh.faceVertexCounts == [3])
        #expect(mesh.faceVertexIndices == [0, 1, 2])
        #expect(mesh.subdivisionScheme == "none")
    }

    @Test(.timeLimit(.minutes(1)))
    func generatedUSDCQuadMeshFixturePreservesFaceVertexTopology() throws {
        let fixture = try generatedFixture("quad_mesh.usdc")

        let scene = try USDCReader().read(from: fixture)

        #expect(scene.defaultPrim == "Quad")
        #expect(scene.metersPerUnit == 1)
        #expect(scene.upAxis == .z)
        #expect(scene.meshes.count == 1)
        let mesh = try #require(scene.meshes.first)
        #expect(mesh.name == "Quad")
        #expect(mesh.points == [
            USDPoint3D(x: 0, y: 0, z: 0),
            USDPoint3D(x: 1, y: 0, z: 0),
            USDPoint3D(x: 1, y: 1, z: 0),
            USDPoint3D(x: 0, y: 1, z: 0),
        ])
        #expect(mesh.faceVertexCounts == [4])
        #expect(mesh.faceVertexIndices == [0, 1, 2, 3])
        #expect(mesh.subdivisionScheme == "none")
    }

    @Test(.timeLimit(.minutes(1)))
    func usdaReaderReadsAuthoredSubdivisionScheme() throws {
        let fixture = try generatedFixture("subdivision_scheme_mesh.usda")

        let scene = try USDAReader().read(from: fixture)

        #expect(scene.defaultPrim == "Quad")
        #expect(scene.meshes.count == 1)
        let mesh = try #require(scene.meshes.first)
        #expect(mesh.name == "Quad")
        #expect(mesh.faceVertexCounts == [4])
        #expect(mesh.faceVertexIndices == [0, 1, 2, 3])
        #expect(mesh.subdivisionScheme == "catmullClark")
    }

    @Test(.timeLimit(.minutes(1)))
    func generatedUSDCSubdivisionSchemeFixtureReadsAuthoredScheme() throws {
        let fixture = try generatedFixture("subdivision_scheme_mesh.usdc")

        let scene = try USDCReader().read(from: fixture)

        #expect(scene.defaultPrim == "Quad")
        #expect(scene.metersPerUnit == 1)
        #expect(scene.upAxis == .z)
        #expect(scene.meshes.count == 1)
        let mesh = try #require(scene.meshes.first)
        #expect(mesh.name == "Quad")
        #expect(mesh.faceVertexCounts == [4])
        #expect(mesh.faceVertexIndices == [0, 1, 2, 3])
        #expect(mesh.subdivisionScheme == "catmullClark")
    }

    @Test(.timeLimit(.minutes(1)))
    func usdaReaderReadsTextureCoordinatePrimvar() throws {
        let fixture = try generatedFixture("uv_mesh.usda")

        let scene = try USDAReader().read(from: fixture)

        #expect(scene.defaultPrim == "Quad")
        #expect(scene.meshes.count == 1)
        let mesh = try #require(scene.meshes.first)
        let textureCoordinates = try #require(mesh.textureCoordinates)
        #expect(textureCoordinates.values == [
            USDPoint2D(x: 0, y: 0),
            USDPoint2D(x: 1, y: 0),
            USDPoint2D(x: 1, y: 1),
            USDPoint2D(x: 0, y: 1),
        ])
        #expect(textureCoordinates.indices == [0, 1, 2, 3])
        #expect(textureCoordinates.interpolation == "faceVarying")
    }

    @Test(.timeLimit(.minutes(1)))
    func generatedUSDCUVFixtureReadsTextureCoordinatePrimvar() throws {
        let fixture = try generatedFixture("uv_mesh.usdc")
        let crate = try USDCReader().readCrate(from: fixture)
        let stValueRep = try defaultFieldValueRep(in: crate, atPath: "/Quad.primvars:st")

        #expect(stValueRep.type == .vec2f)
        #expect(stValueRep.isArray)

        let scene = try USDCReader().read(from: fixture)

        #expect(scene.defaultPrim == "Quad")
        #expect(scene.meshes.count == 1)
        let mesh = try #require(scene.meshes.first)
        let textureCoordinates = try #require(mesh.textureCoordinates)
        #expect(textureCoordinates.values == [
            USDPoint2D(x: 0, y: 0),
            USDPoint2D(x: 1, y: 0),
            USDPoint2D(x: 1, y: 1),
            USDPoint2D(x: 0, y: 1),
        ])
        #expect(textureCoordinates.indices == [0, 1, 2, 3])
        #expect(textureCoordinates.interpolation == "faceVarying")
    }

    @Test(.timeLimit(.minutes(1)))
    func usdaReaderRejectsTextureCoordinateIndexOutsideValueRange() throws {
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
            texCoord2f[] primvars:st = [(0, 0), (1, 0)] (
                interpolation = "faceVarying"
            )
            int[] primvars:st:indices = [0, 1, 2, 0]
            uniform token subdivisionScheme = "none"
        }
        """.utf8)

        #expect(throws: USDImportError.self) {
            _ = try USDAReader().read(from: data)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func generatedUSDCRotatedMeshFixtureAppliesParentAxisRotations() throws {
        let fixture = try generatedFixture("rotated_mesh.usdc")

        let scene = try USDCReader().read(from: fixture)

        #expect(scene.defaultPrim == "Root")
        #expect(scene.metersPerUnit == 1)
        #expect(scene.upAxis == .z)
        #expect(scene.meshes.count == 3)
        let meshesByName = Dictionary(uniqueKeysWithValues: scene.meshes.compactMap { mesh in
            mesh.name.map { ($0, mesh) }
        })
        let rotateXMesh = try #require(meshesByName["TriangleX"])
        expectPointsApproximatelyEqual(rotateXMesh.points, [
            USDPoint3D(x: 0, y: 0, z: 0),
            USDPoint3D(x: 1, y: 0, z: 0),
            USDPoint3D(x: 0, y: 0, z: 1),
        ])
        let rotateYMesh = try #require(meshesByName["TriangleY"])
        expectPointsApproximatelyEqual(rotateYMesh.points, [
            USDPoint3D(x: 0, y: 0, z: 0),
            USDPoint3D(x: 0, y: 0, z: -1),
            USDPoint3D(x: 0, y: 1, z: 0),
        ])
        let rotateZMesh = try #require(meshesByName["TriangleZ"])
        expectPointsApproximatelyEqual(rotateZMesh.points, [
            USDPoint3D(x: 0, y: 0, z: 0),
            USDPoint3D(x: 0, y: 1, z: 0),
            USDPoint3D(x: -1, y: 0, z: 0),
        ])
        for mesh in [rotateXMesh, rotateYMesh, rotateZMesh] {
            #expect(mesh.faceVertexCounts == [3])
            #expect(mesh.faceVertexIndices == [0, 1, 2])
            #expect(mesh.subdivisionScheme == "none")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func generatedUSDCNormalsMeshFixtureReadsVertexNormals() throws {
        let fixture = try generatedFixture("normals_mesh.usdc")

        let scene = try USDCReader().read(from: fixture)

        #expect(scene.defaultPrim == "Root")
        #expect(scene.metersPerUnit == 1)
        #expect(scene.upAxis == .z)
        #expect(scene.meshes.count == 1)
        let mesh = try #require(scene.meshes.first)
        #expect(mesh.name == "Triangle")
        expectPointsApproximatelyEqual(mesh.points, [
            USDPoint3D(x: 0, y: 0, z: 0),
            USDPoint3D(x: 1, y: 0, z: 0),
            USDPoint3D(x: 0, y: 0, z: 1),
        ])
        expectPointsApproximatelyEqual(mesh.normals, [
            USDPoint3D(x: 0, y: -1, z: 0),
            USDPoint3D(x: 0, y: -1, z: 0),
            USDPoint3D(x: 0, y: -1, z: 0),
        ])
        #expect(mesh.normalsInterpolation == "vertex")
        #expect(mesh.faceVertexCounts == [3])
        #expect(mesh.faceVertexIndices == [0, 1, 2])
        #expect(mesh.subdivisionScheme == "none")
    }

    @Test(.timeLimit(.minutes(1)))
    func usdaReaderReadsMeshOrientation() throws {
        let fixture = try generatedFixture("left_handed_mesh.usda")

        let scene = try USDAReader().read(from: fixture)

        #expect(scene.defaultPrim == "Triangle")
        #expect(scene.meshes.count == 1)
        let mesh = try #require(scene.meshes.first)
        #expect(mesh.name == "Triangle")
        #expect(mesh.orientation == .leftHanded)
        expectPointsApproximatelyEqual(mesh.normals, [
            USDPoint3D(x: 0, y: 0, z: -1),
            USDPoint3D(x: 0, y: 0, z: -1),
            USDPoint3D(x: 0, y: 0, z: -1),
        ])
        #expect(mesh.normalsInterpolation == "vertex")
        #expect(mesh.faceVertexCounts == [3])
        #expect(mesh.faceVertexIndices == [0, 1, 2])
        #expect(mesh.subdivisionScheme == "none")
    }

    @Test(.timeLimit(.minutes(1)))
    func generatedUSDCLeftHandedMeshFixtureReadsOrientation() throws {
        let fixture = try generatedFixture("left_handed_mesh.usdc")

        let scene = try USDCReader().read(from: fixture)

        #expect(scene.defaultPrim == "Triangle")
        #expect(scene.metersPerUnit == 1)
        #expect(scene.upAxis == .z)
        #expect(scene.meshes.count == 1)
        let mesh = try #require(scene.meshes.first)
        #expect(mesh.name == "Triangle")
        #expect(mesh.orientation == .leftHanded)
        expectPointsApproximatelyEqual(mesh.normals, [
            USDPoint3D(x: 0, y: 0, z: -1),
            USDPoint3D(x: 0, y: 0, z: -1),
            USDPoint3D(x: 0, y: 0, z: -1),
        ])
        #expect(mesh.normalsInterpolation == "vertex")
        #expect(mesh.faceVertexCounts == [3])
        #expect(mesh.faceVertexIndices == [0, 1, 2])
        #expect(mesh.subdivisionScheme == "none")
    }

    @Test(.timeLimit(.minutes(1)))
    func generatedUSDCCombinedRotationFixtureAppliesPackedEulerRotation() throws {
        let fixture = try generatedFixture("combined_rotation_mesh.usdc")

        let scene = try USDCReader().read(from: fixture)

        #expect(scene.defaultPrim == "Root")
        #expect(scene.metersPerUnit == 1)
        #expect(scene.upAxis == .z)
        #expect(scene.meshes.count == 6)
        let meshesByName = Dictionary(uniqueKeysWithValues: scene.meshes.compactMap { mesh in
            mesh.name.map { ($0, mesh) }
        })
        let expectedPointsByName: [String: [USDPoint3D]] = [
            "TriangleXYZ": [
                USDPoint3D(x: 0, y: 0, z: -1),
                USDPoint3D(x: 0, y: 1, z: 0),
                USDPoint3D(x: 1, y: 0, z: 0),
            ],
            "TriangleXZY": [
                USDPoint3D(x: 0, y: 1, z: 0),
                USDPoint3D(x: 1, y: 0, z: 0),
                USDPoint3D(x: 0, y: 0, z: -1),
            ],
            "TriangleYXZ": [
                USDPoint3D(x: -1, y: 0, z: 0),
                USDPoint3D(x: 0, y: 0, z: 1),
                USDPoint3D(x: 0, y: 1, z: 0),
            ],
            "TriangleYZX": [
                USDPoint3D(x: 0, y: 1, z: 0),
                USDPoint3D(x: -1, y: 0, z: 0),
                USDPoint3D(x: 0, y: 0, z: 1),
            ],
            "TriangleZXY": [
                USDPoint3D(x: 1, y: 0, z: 0),
                USDPoint3D(x: 0, y: 0, z: 1),
                USDPoint3D(x: 0, y: -1, z: 0),
            ],
            "TriangleZYX": [
                USDPoint3D(x: 0, y: 0, z: 1),
                USDPoint3D(x: 0, y: -1, z: 0),
                USDPoint3D(x: 1, y: 0, z: 0),
            ],
        ]
        for (name, expectedPoints) in expectedPointsByName {
            let mesh = try #require(meshesByName[name])
            expectPointsApproximatelyEqual(mesh.points, expectedPoints)
            #expect(mesh.faceVertexCounts == [3])
            #expect(mesh.faceVertexIndices == [0, 1, 2])
            #expect(mesh.subdivisionScheme == "none")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func generatedUSDCOrientFixtureAppliesQuaternionTransforms() throws {
        let fixture = try generatedFixture("orient_mesh.usdc")

        let scene = try USDCReader().read(from: fixture)

        #expect(scene.defaultPrim == "Root")
        #expect(scene.metersPerUnit == 1)
        #expect(scene.upAxis == .z)
        #expect(scene.meshes.count == 3)
        let meshesByName = Dictionary(uniqueKeysWithValues: scene.meshes.compactMap { mesh in
            mesh.name.map { ($0, mesh) }
        })
        let expectedPointsByName: [String: [USDPoint3D]] = [
            "TriangleQuatf": [
                USDPoint3D(x: 0, y: 1, z: 0),
                USDPoint3D(x: -1, y: 0, z: 0),
                USDPoint3D(x: 0, y: 0, z: 1),
            ],
            "TriangleQuatd": [
                USDPoint3D(x: 1, y: 0, z: 0),
                USDPoint3D(x: 0, y: 0, z: 1),
                USDPoint3D(x: 0, y: -1, z: 0),
            ],
            "TriangleZero": [
                USDPoint3D(x: 1, y: 0, z: 0),
                USDPoint3D(x: 0, y: 1, z: 0),
                USDPoint3D(x: 0, y: 0, z: 1),
            ],
        ]
        for (name, expectedPoints) in expectedPointsByName {
            let mesh = try #require(meshesByName[name])
            expectPointsApproximatelyEqual(mesh.points, expectedPoints)
            #expect(mesh.faceVertexCounts == [3])
            #expect(mesh.faceVertexIndices == [0, 1, 2])
            #expect(mesh.subdivisionScheme == "none")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func generatedUSDCScalarXformFixtureAppliesScalarTranslateAndScaleOps() throws {
        let fixture = try generatedFixture("scalar_xform_mesh.usdc")

        let scene = try USDCReader().read(from: fixture)

        #expect(scene.defaultPrim == "Root")
        #expect(scene.metersPerUnit == 1)
        #expect(scene.upAxis == .z)
        #expect(scene.meshes.count == 6)
        let meshesByName = Dictionary(uniqueKeysWithValues: scene.meshes.compactMap { mesh in
            mesh.name.map { ($0, mesh) }
        })
        let expectedPointsByName: [String: [USDPoint3D]] = [
            "TriangleTranslateX": [
                USDPoint3D(x: 3, y: 1, z: 1),
                USDPoint3D(x: 4, y: 1, z: 1),
                USDPoint3D(x: 3, y: 2, z: 1),
            ],
            "TriangleTranslateY": [
                USDPoint3D(x: 1, y: 4, z: 1),
                USDPoint3D(x: 2, y: 4, z: 1),
                USDPoint3D(x: 1, y: 5, z: 1),
            ],
            "TriangleTranslateZ": [
                USDPoint3D(x: 1, y: 1, z: 5),
                USDPoint3D(x: 2, y: 1, z: 5),
                USDPoint3D(x: 1, y: 2, z: 5),
            ],
            "TriangleScaleX": [
                USDPoint3D(x: 2, y: 1, z: 1),
                USDPoint3D(x: 4, y: 1, z: 1),
                USDPoint3D(x: 2, y: 2, z: 1),
            ],
            "TriangleScaleY": [
                USDPoint3D(x: 1, y: 3, z: 1),
                USDPoint3D(x: 2, y: 3, z: 1),
                USDPoint3D(x: 1, y: 6, z: 1),
            ],
            "TriangleScaleZ": [
                USDPoint3D(x: 1, y: 1, z: 4),
                USDPoint3D(x: 2, y: 1, z: 4),
                USDPoint3D(x: 1, y: 2, z: 4),
            ],
        ]
        for (name, expectedPoints) in expectedPointsByName {
            let mesh = try #require(meshesByName[name])
            expectPointsApproximatelyEqual(mesh.points, expectedPoints)
            #expect(mesh.faceVertexCounts == [3])
            #expect(mesh.faceVertexIndices == [0, 1, 2])
            #expect(mesh.subdivisionScheme == "none")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func generatedUSDCTimeSampledMeshFixtureUsesFirstSampleSnapshot() throws {
        let fixture = try generatedFixture("animated_mesh.usdc")

        let scene = try USDCReader().read(from: fixture)

        #expect(scene.defaultPrim == "Triangle")
        #expect(scene.metersPerUnit == 1)
        #expect(scene.upAxis == .z)
        #expect(scene.meshes.count == 1)
        let mesh = try #require(scene.meshes.first)
        #expect(mesh.name == "Triangle")
        #expect(mesh.points == [
            USDPoint3D(x: 0, y: 0, z: 0),
            USDPoint3D(x: 1, y: 0, z: 0),
            USDPoint3D(x: 0, y: 1, z: 0),
        ])
        #expect(mesh.faceVertexCounts == [3])
        #expect(mesh.faceVertexIndices == [0, 1, 2])
        #expect(mesh.subdivisionScheme == "none")
    }

    @Test(.timeLimit(.minutes(1)))
    func generatedUSDCBlockedValueFixtureUsesFirstUnblockedSampleSnapshot() throws {
        let fixture = try generatedFixture("blocked_values_mesh.usdc")

        let scene = try USDCReader().read(from: fixture)

        #expect(scene.defaultPrim == "Triangle")
        #expect(scene.metersPerUnit == 1)
        #expect(scene.upAxis == .z)
        #expect(scene.meshes.count == 1)
        let mesh = try #require(scene.meshes.first)
        #expect(mesh.name == "Triangle")
        #expect(mesh.points == [
            USDPoint3D(x: 0, y: 0, z: 2),
            USDPoint3D(x: 1, y: 0, z: 2),
            USDPoint3D(x: 0, y: 1, z: 2),
        ])
        #expect(mesh.faceVertexCounts == [3])
        #expect(mesh.faceVertexIndices == [0, 1, 2])
        #expect(mesh.subdivisionScheme == nil)
        #expect(mesh.effectiveSubdivisionScheme == "catmullClark")
    }

    @Test(.timeLimit(.minutes(1)))
    func generatedUSDCBlockedRequiredDefaultFixtureReportsMissingField() throws {
        let fixture = try generatedFixture("blocked_required_default_mesh.usdc")

        do {
            _ = try USDCReader().read(from: fixture)
            Issue.record("Expected blocked points to be reported as a missing required field.")
        } catch USDImportError.missingRequiredField(let field) {
            #expect(field == "points")
        } catch {
            Issue.record("Expected missingRequiredField(\"points\"), got \(error).")
        }
    }

    #if CAD_ENABLE_USDC_READER
    @Test(.timeLimit(.minutes(1)))
    func usdzReaderMaterializesUSDCDefaultLayerMeshExchangeScene() throws {
        let fixture = makeUSDCMeshSceneFixture()
        let package = makeUSDZFixture(entries: [
            ("scene.usdc", fixture),
        ], alignPayloads: true)

        let scene = try USDZReader().read(from: package)

        #expect(scene.defaultPrim == "Triangle")
        #expect(scene.upAxis == .z)
        #expect(scene.meshes.first?.faceVertexIndices == [0, 1, 2])
    }
    #endif

    @Test(.timeLimit(.minutes(1)))
    func openUSDFileFormatCrateFixtureReadsStructuralTables() throws {
        let data = try openUSDFixture("testUsdFileFormats/crate.usd")

        let crate = try USDCReader().readCrate(from: data)

        #expect(crate.version == USDCCrateVersion(major: 0, minor: 0, patch: 1))
        try crate.requireStructuralSections()
        #expect(try crate.readTokens().contains("specifier"))
        #expect(try crate.readStringTokenIndexes() == [])
        #expect(!((try crate.readFields()).isEmpty))
        #expect(!((try crate.readFieldSetIndexes()).isEmpty))
        #expect(try crate.readPaths() == ["/", "/AirConditioner", "/Scope"])
        let specs = try crate.readSpecs()
        #expect(specs.count == 3)
        #expect(specs[1] == USDCCrateSpec(pathIndex: 2, fieldSetIndex: 2, specType: .prim))
        let tokens = try crate.readTokens()
        let fields = try crate.readFields()
        let fieldSetIndexes = try crate.readFieldSetIndexes()
        #expect(fieldSetIndexes[2...3].map { $0 } == [0, 1])
        #expect(tokens[Int(fields[1].tokenIndex)] == "typeName")
        #expect(fields[1].valueRep.type == .token)
        #expect(fields[1].valueRep.isInlined)
        #expect(fields[1].valueRep.payload == 3)
        #expect(tokens[Int(fields[1].valueRep.payload)] == "Scope")
    }

    @Test(.timeLimit(.minutes(1)))
    func openUSDSingleUSDCFixtureReadsCompressedStructuralTables() throws {
        let data = try openUSDFixture("testUsdUsdzFileFormat/single/test.usdc")

        let crate = try USDCReader().readCrate(from: data)

        #expect(crate.version == USDCCrateVersion(major: 0, minor: 7, patch: 0))
        try crate.requireStructuralSections()
        #expect(try crate.readTokens().contains("Root_USDC"))
        #expect(!((try crate.readFields()).isEmpty))
        #expect(!((try crate.readFieldSets()).isEmpty))
        #expect(try crate.readPaths() == ["/", "/Root_USDC"])
        let specs = try crate.readSpecs()
        #expect(specs == [
            USDCCrateSpec(pathIndex: 0, fieldSetIndex: 0, specType: .pseudoRoot),
            USDCCrateSpec(pathIndex: 1, fieldSetIndex: 2, specType: .prim),
        ])
        let tokens = try crate.readTokens()
        let fields = try crate.readFields()
        let fieldSetIndexes = try crate.readFieldSetIndexes()
        #expect(fieldSetIndexes[2] == 1)
        #expect(tokens[Int(fields[1].tokenIndex)] == "specifier")
        #expect(fields[1].valueRep.type == .specifier)
        #expect(fields[1].valueRep.isInlined)
        #expect(fields[1].valueRep.payload == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func openUSDUSDZFixtureRejectsFirstFileThatIsNotUSDLayer() throws {
        let data = try openUSDFixture("testUsdUsdzFileFormat/first_file_not_usd.usdz")

        #expect(throws: USDImportError.self) {
            _ = try USDZReader().read(from: data)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func openUSDUSDZFixtureWithUSDCDefaultLayerThrowsTypedUSDError() throws {
        let data = try openUSDFixture("testUsdUsdzFileFormat/single_usdc.usdz")

        #expect(throws: USDImportError.self) {
            _ = try USDZReader().read(from: data)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func usdcSceneReaderRequiresStructuralSections() throws {
        let data = makeUSDCFixture(sections: [
            ("TOKENS", Data([0x01])),
        ])

        #expect(throws: USDImportError.self) {
            _ = try USDCReader().read(from: data)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func usdzReaderReadsAlignedUSDADefaultLayer() throws {
        let usda = Data("""
        #usda 1.0
        (
            defaultPrim = "Scene"
            metersPerUnit = 1
            upAxis = "Z"
        )

        def Mesh "Triangle"
        {
            point3f[] points = [(0, 0, 0), (1, 0, 0), (0, 1, 0)]
            int[] faceVertexCounts = [3]
            int[] faceVertexIndices = [0, 1, 2]
            uniform token subdivisionScheme = "none"
        }
        """.utf8)
        let package = makeUSDZFixture(entries: [
            ("scene.usda", usda),
        ], alignPayloads: true)

        let scene = try USDZReader().read(from: package)

        #expect(scene.defaultPrim == "Scene")
        #expect(scene.upAxis == .z)
        #expect(scene.meshes.count == 1)
        #expect(scene.meshes.first?.points.count == 3)
        #expect(scene.meshes.first?.faceVertexIndices == [0, 1, 2])
    }

    @Test(.timeLimit(.minutes(1)))
    func usdzReaderRejectsUnalignedPayload() throws {
        let usda = Data("""
        #usda 1.0
        (
            metersPerUnit = 1
            upAxis = "Z"
        )

        def Mesh "Triangle"
        {
            point3f[] points = [(0, 0, 0), (1, 0, 0), (0, 1, 0)]
            int[] faceVertexCounts = [3]
            int[] faceVertexIndices = [0, 1, 2]
        }
        """.utf8)
        let package = makeUSDZFixture(entries: [
            ("scene.usda", usda),
        ], alignPayloads: false)

        #expect(throws: USDImportError.self) {
            _ = try USDZReader().read(from: package)
        }
    }
}

private func makeUSDCFixture(
    version: USDCCrateVersion = USDCCrateVersion(major: 0, minor: 8, patch: 0),
    valueData: Data = Data(),
    sections: [(String, Data)]
) -> Data {
    var offset = USDCCrateFile.bootstrapByteCount + valueData.count
    let sectionRanges = sections.map { section -> (name: String, start: Int, size: Int, data: Data) in
        let start = offset
        offset += section.1.count
        return (section.0, start, section.1.count, section.1)
    }
    let tableOfContentsOffset = offset

    var data = Data()
    data.append(contentsOf: USDCReader.fileSignature)
    data.append(contentsOf: [version.major, version.minor, version.patch, 0, 0, 0, 0, 0])
    data.appendLittleEndian(Int64(tableOfContentsOffset))
    for _ in 0..<8 {
        data.appendLittleEndian(Int64(0))
    }
    data.append(valueData)
    for section in sectionRanges {
        data.append(section.data)
    }
    data.appendLittleEndian(UInt64(sectionRanges.count))
    for section in sectionRanges {
        data.appendFixedASCII(section.name, byteCount: 16)
        data.appendLittleEndian(Int64(section.start))
        data.appendLittleEndian(Int64(section.size))
    }
    return data
}

private func expectPointsApproximatelyEqual(
    _ actual: [USDPoint3D],
    _ expected: [USDPoint3D],
    tolerance: Double = 1e-9
) {
    #expect(actual.count == expected.count)
    for index in 0..<min(actual.count, expected.count) {
        #expect(abs(actual[index].x - expected[index].x) <= tolerance)
        #expect(abs(actual[index].y - expected[index].y) <= tolerance)
        #expect(abs(actual[index].z - expected[index].z) <= tolerance)
    }
}

private func makeUSDCMeshSceneFixture(compressedPoints: Bool = false) -> Data {
    let version = USDCCrateVersion(major: 0, minor: 8, patch: 0)
    let tokens = [
        "defaultPrim",
        "Triangle",
        "metersPerUnit",
        "upAxis",
        "Z",
        "specifier",
        "typeName",
        "Mesh",
        "faceVertexCounts",
        "faceVertexIndices",
        "points",
        "subdivisionScheme",
        "default",
        "none",
    ]
    var valueData = Data()
    let faceVertexCountsOffset = appendUSDCIntArray([3], to: &valueData)
    let faceVertexIndicesOffset = appendUSDCIntArray([0, 1, 2], to: &valueData)
    let meshPoints = [
        USDPoint3D(x: 0, y: 0, z: 0),
        USDPoint3D(x: 1, y: 0, z: 0),
        USDPoint3D(x: 0, y: 1, z: 0),
    ]
    let pointsOffset: UInt64
    if compressedPoints {
        pointsOffset = appendUSDCCompressedVec3fArray(meshPoints, to: &valueData)
    } else {
        pointsOffset = appendUSDCVec3fArray(meshPoints, to: &valueData)
    }
    var pointsValueRep = USDCCrateValueRep(type: .vec3f, isInlined: false, isArray: true, payload: pointsOffset)
    if compressedPoints {
        pointsValueRep.rawValue |= USDCCrateValueRep.isCompressedBit
    }

    let fields = [
        USDCCrateField(
            tokenIndex: 0,
            valueRep: USDCCrateValueRep(type: .token, isInlined: true, isArray: false, payload: 1)
        ),
        USDCCrateField(
            tokenIndex: 2,
            valueRep: USDCCrateValueRep(type: .double, isInlined: true, isArray: false, payload: UInt64(Float32(1).bitPattern))
        ),
        USDCCrateField(
            tokenIndex: 3,
            valueRep: USDCCrateValueRep(type: .token, isInlined: true, isArray: false, payload: 4)
        ),
        USDCCrateField(
            tokenIndex: 5,
            valueRep: USDCCrateValueRep(type: .specifier, isInlined: true, isArray: false, payload: 0)
        ),
        USDCCrateField(
            tokenIndex: 6,
            valueRep: USDCCrateValueRep(type: .token, isInlined: true, isArray: false, payload: 7)
        ),
        USDCCrateField(
            tokenIndex: 12,
            valueRep: USDCCrateValueRep(type: .int, isInlined: false, isArray: true, payload: faceVertexCountsOffset)
        ),
        USDCCrateField(
            tokenIndex: 12,
            valueRep: USDCCrateValueRep(type: .int, isInlined: false, isArray: true, payload: faceVertexIndicesOffset)
        ),
        USDCCrateField(
            tokenIndex: 12,
            valueRep: pointsValueRep
        ),
        USDCCrateField(
            tokenIndex: 12,
            valueRep: USDCCrateValueRep(type: .token, isInlined: true, isArray: false, payload: 13)
        ),
    ]
    let fieldSetIndexes: [UInt32] = [
        0, 1, 2, UInt32.max,
        3, 4, UInt32.max,
        5, UInt32.max,
        6, UInt32.max,
        7, UInt32.max,
        8, UInt32.max,
    ]
    let specs = [
        USDCCrateSpec(pathIndex: 0, fieldSetIndex: 0, specType: .pseudoRoot),
        USDCCrateSpec(pathIndex: 1, fieldSetIndex: 4, specType: .prim),
        USDCCrateSpec(pathIndex: 2, fieldSetIndex: 7, specType: .attribute),
        USDCCrateSpec(pathIndex: 3, fieldSetIndex: 9, specType: .attribute),
        USDCCrateSpec(pathIndex: 4, fieldSetIndex: 11, specType: .attribute),
        USDCCrateSpec(pathIndex: 5, fieldSetIndex: 13, specType: .attribute),
    ]

    return makeUSDCFixture(version: version, valueData: valueData, sections: [
        ("TOKENS", makeUSDCTokenSection(version: version, tokenData: nullSeparatedTokenData(tokens))),
        ("STRINGS", makeUSDCStringsSection([])),
        ("FIELDS", makeUSDCFieldsSection(version: version, fields: fields)),
        ("FIELDSETS", makeUSDCFieldSetsSection(version: version, indexes: fieldSetIndexes)),
        ("PATHS", makeUSDCCompressedPathsSection(
            pathCount: 6,
            pathIndexes: [0, 1, 2, 3, 4, 5],
            elementTokenIndexes: [0, 1, -8, -9, -10, -11],
            jumps: [-1, -1, 0, 0, 0, -2]
        )),
        ("SPECS", makeUSDCSpecsSection(version: version, specs: specs)),
    ])
}

private func appendUSDCIntArray(_ values: [Int32], to data: inout Data) -> UInt64 {
    let offset = alignUSDCValueData(&data)
    data.appendLittleEndian(UInt64(values.count))
    for value in values {
        data.appendLittleEndian(value)
    }
    return offset
}

private func appendUSDCVec3fArray(_ points: [USDPoint3D], to data: inout Data) -> UInt64 {
    let offset = alignUSDCValueData(&data)
    data.appendLittleEndian(UInt64(points.count))
    for point in points {
        data.appendLittleEndianFloat32(Float32(point.x))
        data.appendLittleEndianFloat32(Float32(point.y))
        data.appendLittleEndianFloat32(Float32(point.z))
    }
    return offset
}

private func appendUSDCCompressedVec3fArray(_ points: [USDPoint3D], to data: inout Data) -> UInt64 {
    let offset = alignUSDCValueData(&data)
    data.appendLittleEndian(UInt64(points.count))
    var rawValueData = Data()
    for point in points {
        rawValueData.appendLittleEndianFloat32(Float32(point.x))
        rawValueData.appendLittleEndianFloat32(Float32(point.y))
        rawValueData.appendLittleEndianFloat32(Float32(point.z))
    }
    let compressed = testFastCompression(rawValueData)
    data.appendLittleEndian(UInt64(compressed.count))
    data.append(compressed)
    return offset
}

private func alignUSDCValueData(_ data: inout Data) -> UInt64 {
    while (USDCCrateFile.bootstrapByteCount + data.count) % MemoryLayout<UInt64>.size != 0 {
        data.append(0)
    }
    return UInt64(USDCCrateFile.bootstrapByteCount + data.count)
}

private func openUSDFixture(_ relativePath: String) throws -> Data {
    try fixtureData(root: "OpenUSD", relativePath: relativePath)
}

private func generatedFixture(_ relativePath: String) throws -> Data {
    try fixtureData(root: "Generated", relativePath: relativePath)
}

private func defaultFieldValueRep(in crate: USDCCrateFile, atPath path: String) throws -> USDCCrateValueRep {
    let paths = try crate.readPaths()
    let specs = try crate.readSpecs()
    let fieldSetIndexes = try crate.readFieldSetIndexes()
    let fields = try crate.readFields()
    let tokens = try crate.readTokens()
    guard let pathIndex = paths.firstIndex(of: path) else {
        throw USDImportError.invalidData("USDC fixture is missing path \(path).")
    }
    guard let spec = specs.first(where: { Int($0.pathIndex) == pathIndex }) else {
        throw USDImportError.invalidData("USDC fixture is missing spec for path \(path).")
    }
    var cursor = Int(spec.fieldSetIndex)
    while cursor < fieldSetIndexes.count {
        let fieldIndex = fieldSetIndexes[cursor]
        cursor += 1
        if fieldIndex == UInt32.max {
            break
        }
        guard fieldIndex < UInt32(fields.count) else {
            throw USDImportError.invalidData("USDC fixture field set references an out-of-range field.")
        }
        let field = fields[Int(fieldIndex)]
        guard field.tokenIndex < UInt32(tokens.count) else {
            throw USDImportError.invalidData("USDC fixture field references an out-of-range token.")
        }
        if tokens[Int(field.tokenIndex)] == "default" {
            return field.valueRep
        }
    }
    throw USDImportError.invalidData("USDC fixture is missing a default field for path \(path).")
}

private func fixtureData(root: String, relativePath: String) throws -> Data {
    #if SWIFT_PACKAGE
    if let resourceURL = Bundle.module.resourceURL {
        let fixtureURL = resourceURL
            .appendingPathComponent("Fixtures")
            .appendingPathComponent(root)
            .appendingPathComponent(relativePath)
        if FileManager.default.fileExists(atPath: fixtureURL.path) {
            return try Data(contentsOf: fixtureURL)
        }
    }
    #endif
    let testFileURL = URL(fileURLWithPath: #filePath)
    let fixturesURL = testFileURL
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")
        .appendingPathComponent(root)
    return try Data(contentsOf: fixturesURL.appendingPathComponent(relativePath))
}

private func makeUSDCTokenSection(version: USDCCrateVersion, tokenData: Data) -> Data {
    let tokens = tokenData.filter { $0 == 0 }.count
    var data = Data()
    data.appendLittleEndian(UInt64(tokens))
    if version < USDCCrateVersion(major: 0, minor: 4, patch: 0) {
        data.appendLittleEndian(UInt64(tokenData.count))
        data.append(tokenData)
    } else {
        let compressed = testFastCompression(tokenData)
        data.appendLittleEndian(UInt64(tokenData.count))
        data.appendLittleEndian(UInt64(compressed.count))
        data.append(compressed)
    }
    return data
}

private func makeUSDCStringsSection(_ tokenIndexes: [UInt32]) -> Data {
    var data = Data()
    data.appendLittleEndian(UInt64(tokenIndexes.count))
    for tokenIndex in tokenIndexes {
        data.appendLittleEndian(tokenIndex)
    }
    return data
}

private func makeUSDCFieldsSection(version: USDCCrateVersion, fields: [USDCCrateField]) -> Data {
    var data = Data()
    data.appendLittleEndian(UInt64(fields.count))
    if version < USDCCrateVersion(major: 0, minor: 4, patch: 0) {
        for field in fields {
            data.appendLittleEndian(UInt32(0))
            data.appendLittleEndian(field.tokenIndex)
            data.appendLittleEndian(field.valueRep.rawValue)
        }
    } else {
        data.append(compressedUInt32List(fields.map(\.tokenIndex)))
        var valueRepBytes = Data()
        for field in fields {
            valueRepBytes.appendLittleEndian(field.valueRep.rawValue)
        }
        let compressedValueReps = testFastCompression(valueRepBytes)
        data.appendLittleEndian(UInt64(compressedValueReps.count))
        data.append(compressedValueReps)
    }
    return data
}

private func makeUSDCFieldSetsSection(version: USDCCrateVersion, indexes: [UInt32]) -> Data {
    var data = Data()
    data.appendLittleEndian(UInt64(indexes.count))
    if version < USDCCrateVersion(major: 0, minor: 4, patch: 0) {
        for index in indexes {
            data.appendLittleEndian(index)
        }
    } else {
        data.append(compressedUInt32List(indexes))
    }
    return data
}

private func makeUSDCCompressedPathsSection(
    pathCount: Int,
    pathIndexes: [UInt32],
    elementTokenIndexes: [Int32],
    jumps: [Int32]
) -> Data {
    var data = Data()
    data.appendLittleEndian(UInt64(pathCount))
    data.appendLittleEndian(UInt64(pathIndexes.count))
    data.append(compressedUInt32List(pathIndexes))
    data.append(compressedInt32List(elementTokenIndexes))
    data.append(compressedInt32List(jumps))
    return data
}

private func makeUSDCSpecsSection(version: USDCCrateVersion, specs: [USDCCrateSpec]) -> Data {
    var data = Data()
    data.appendLittleEndian(UInt64(specs.count))
    if version == USDCCrateVersion(major: 0, minor: 0, patch: 1) {
        for spec in specs {
            data.appendLittleEndian(UInt32(0))
            data.appendLittleEndian(spec.pathIndex)
            data.appendLittleEndian(spec.fieldSetIndex)
            data.appendLittleEndian(spec.specType.rawValue)
        }
    } else if version < USDCCrateVersion(major: 0, minor: 4, patch: 0) {
        for spec in specs {
            data.appendLittleEndian(spec.pathIndex)
            data.appendLittleEndian(spec.fieldSetIndex)
            data.appendLittleEndian(spec.specType.rawValue)
        }
    } else {
        data.append(compressedUInt32List(specs.map(\.pathIndex)))
        data.append(compressedUInt32List(specs.map(\.fieldSetIndex)))
        data.append(compressedUInt32List(specs.map(\.specType.rawValue)))
    }
    return data
}

private func nullSeparatedTokenData(_ tokens: [String]) -> Data {
    var data = Data()
    for token in tokens {
        data.append(contentsOf: token.utf8)
        data.append(0)
    }
    return data
}

private func compressedInt32List(_ values: [Int32]) -> Data {
    compressedUInt32List(values.map { UInt32(bitPattern: $0) })
}

private func compressedUInt32List(_ values: [UInt32]) -> Data {
    let payload = compressedUInt32Payload(values)
    var data = Data()
    data.appendLittleEndian(UInt64(payload.count))
    data.append(payload)
    return data
}

private func compressedUInt32Payload(_ values: [UInt32]) -> Data {
    testFastCompression(integerEncodedData(values))
}

private func integerEncodedData(_ values: [UInt32]) -> Data {
    guard !values.isEmpty else {
        return Data()
    }
    let deltas = integerDeltas(values)
    let commonValue = mostCommonIntegerDelta(deltas)
    var output = Data()
    output.appendLittleEndian(commonValue)
    var codes = [UInt8](repeating: 0, count: (values.count * 2 + 7) / 8)
    var variableIntegers = Data()
    for (index, delta) in deltas.enumerated() {
        let code: UInt8
        if delta == commonValue {
            code = 0
        } else if delta >= Int32(Int8.min), delta <= Int32(Int8.max) {
            code = 1
            variableIntegers.append(UInt8(bitPattern: Int8(truncatingIfNeeded: delta)))
        } else if delta >= Int32(Int16.min), delta <= Int32(Int16.max) {
            code = 2
            variableIntegers.appendLittleEndian(Int16(truncatingIfNeeded: delta))
        } else {
            code = 3
            variableIntegers.appendLittleEndian(delta)
        }
        codes[index / 4] |= code << UInt8((index % 4) * 2)
    }
    output.append(contentsOf: codes)
    output.append(variableIntegers)
    return output
}

private func integerDeltas(_ values: [UInt32]) -> [Int32] {
    var previous = Int32(0)
    return values.map { value in
        let signedValue = Int32(bitPattern: value)
        let delta = signedValue &- previous
        previous = signedValue
        return delta
    }
}

private func mostCommonIntegerDelta(_ deltas: [Int32]) -> Int32 {
    var counts: [Int32: Int] = [:]
    for delta in deltas {
        counts[delta, default: 0] += 1
    }
    return counts.max { lhs, rhs in
        if lhs.value != rhs.value {
            return lhs.value < rhs.value
        }
        return lhs.key < rhs.key
    }?.key ?? 0
}

private func testFastCompression(_ data: Data) -> Data {
    var compressed = Data([0])
    compressed.append(testLZ4LiteralBlock(Array(data)))
    return compressed
}

private func testLZ4LiteralBlock(_ bytes: [UInt8]) -> Data {
    var output = Data()
    var literalCount = bytes.count
    let tokenHighNibble = min(literalCount, 15)
    output.append(UInt8(tokenHighNibble << 4))
    if literalCount >= 15 {
        literalCount -= 15
        while literalCount >= 255 {
            output.append(255)
            literalCount -= 255
        }
        output.append(UInt8(literalCount))
    }
    output.append(contentsOf: bytes)
    return output
}

private func makeUSDZFixture(entries: [(String, Data)], alignPayloads: Bool) -> Data {
    var data = Data()
    var centralRecords: [(path: String, localHeaderOffset: Int, crc: UInt32, size: Int)] = []

    for entry in entries {
        let localHeaderOffset = data.count
        let nameData = Data(entry.0.utf8)
        let crc = testCRC32(entry.1)
        let payloadStartWithoutPadding = localHeaderOffset + 30 + nameData.count
        let extraLength = alignPayloads ? ((64 - (payloadStartWithoutPadding % 64)) % 64) : 0

        data.appendLittleEndian(UInt32(0x04034b50))
        data.appendLittleEndian(UInt16(20))
        data.appendLittleEndian(UInt16(0))
        data.appendLittleEndian(UInt16(0))
        data.appendLittleEndian(UInt16(0))
        data.appendLittleEndian(UInt16(0))
        data.appendLittleEndian(crc)
        data.appendLittleEndian(UInt32(entry.1.count))
        data.appendLittleEndian(UInt32(entry.1.count))
        data.appendLittleEndian(UInt16(nameData.count))
        data.appendLittleEndian(UInt16(extraLength))
        data.append(nameData)
        data.append(Data(repeating: 0, count: extraLength))
        data.append(entry.1)
        centralRecords.append((entry.0, localHeaderOffset, crc, entry.1.count))
    }

    let centralDirectoryOffset = data.count
    var centralDirectory = Data()
    for record in centralRecords {
        let nameData = Data(record.path.utf8)
        centralDirectory.appendLittleEndian(UInt32(0x02014b50))
        centralDirectory.appendLittleEndian(UInt16(20))
        centralDirectory.appendLittleEndian(UInt16(20))
        centralDirectory.appendLittleEndian(UInt16(0))
        centralDirectory.appendLittleEndian(UInt16(0))
        centralDirectory.appendLittleEndian(UInt16(0))
        centralDirectory.appendLittleEndian(UInt16(0))
        centralDirectory.appendLittleEndian(record.crc)
        centralDirectory.appendLittleEndian(UInt32(record.size))
        centralDirectory.appendLittleEndian(UInt32(record.size))
        centralDirectory.appendLittleEndian(UInt16(nameData.count))
        centralDirectory.appendLittleEndian(UInt16(0))
        centralDirectory.appendLittleEndian(UInt16(0))
        centralDirectory.appendLittleEndian(UInt16(0))
        centralDirectory.appendLittleEndian(UInt16(0))
        centralDirectory.appendLittleEndian(UInt32(0))
        centralDirectory.appendLittleEndian(UInt32(record.localHeaderOffset))
        centralDirectory.append(nameData)
    }
    data.append(centralDirectory)
    data.appendLittleEndian(UInt32(0x06054b50))
    data.appendLittleEndian(UInt16(0))
    data.appendLittleEndian(UInt16(0))
    data.appendLittleEndian(UInt16(centralRecords.count))
    data.appendLittleEndian(UInt16(centralRecords.count))
    data.appendLittleEndian(UInt32(centralDirectory.count))
    data.appendLittleEndian(UInt32(centralDirectoryOffset))
    data.appendLittleEndian(UInt16(0))
    return data
}

private func testCRC32(_ data: Data) -> UInt32 {
    var crc: UInt32 = 0xffff_ffff
    for byte in data {
        let index = Int((crc ^ UInt32(byte)) & 0xff)
        crc = (crc >> 8) ^ testCRC32Table[index]
    }
    return crc ^ 0xffff_ffff
}

private let testCRC32Table: [UInt32] = {
    (0..<256).map { value in
        var crc = UInt32(value)
        for _ in 0..<8 {
            if crc & 1 == 1 {
                crc = (crc >> 1) ^ 0xedb88320
            } else {
                crc >>= 1
            }
        }
        return crc
    }
}()

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { bytes in
            append(contentsOf: bytes)
        }
    }

    mutating func appendLittleEndianFloat32(_ value: Float32) {
        appendLittleEndian(value.bitPattern)
    }

    mutating func appendFixedASCII(_ string: String, byteCount: Int) {
        let bytes = Array(string.utf8)
        append(contentsOf: bytes.prefix(byteCount))
        if bytes.count < byteCount {
            append(Data(repeating: 0, count: byteCount - bytes.count))
        }
    }
}
