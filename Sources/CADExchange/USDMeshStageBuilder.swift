import Foundation
import CADCore
import CADIR
import OpenUSD

struct USDMeshStageBuilder {
    func stage(
        meshes: [BodyID: Mesh],
        unit: LengthUnit,
        tolerance: ModelingTolerance
    ) throws -> USDStage {
        guard !meshes.isEmpty else {
            throw ExportError.emptyMesh
        }
        var stage = USDStage.createInMemory(
            metersPerUnit: unit.metersPerUnit,
            upAxis: .z
        )
        let scenePath = try SdfPath("/SwiftCADScene")
        let scene = try USDGeomXform.define(in: &stage, at: scenePath)
        try stage.setDefaultPrim(scene.prim)

        for (bodyID, mesh) in meshes.sorted(by: { $0.key.description < $1.key.description }) {
            let indices = try integerIndices(mesh.indices)
            try mesh.validate(tolerance: tolerance)
            let meshPath = try SdfPath(
                "/SwiftCADScene/Body_\(bodyID.rawValue.uuidString.replacingOccurrences(of: "-", with: "_"))"
            )
            let usdMesh = try USDGeomMesh.define(in: &stage, at: meshPath)
            try usdMesh.setTopology(
                points: try points(mesh.positions, unit: unit),
                faceVertexCounts: Array(repeating: 3, count: indices.count / 3),
                faceVertexIndices: indices,
                in: &stage
            )
            try usdMesh.setOrientation(.rightHanded, in: &stage)
            try usdMesh.setSubdivisionScheme("none", in: &stage)
            try authorNormals(mesh.normals, for: usdMesh, in: &stage)
            try authorTextureCoordinates(mesh.textureCoordinates, for: usdMesh, in: &stage)
            try authorVertexColors(mesh.vertexColors, for: usdMesh, in: &stage)
        }
        return stage
    }

    private func points(
        _ points: [Point3D],
        unit: LengthUnit
    ) throws -> [USDPoint3D] {
        try points.enumerated().map { index, point in
            let x = unit.fromInternal(point.x)
            let y = unit.fromInternal(point.y)
            let z = unit.fromInternal(point.z)
            guard Float(x).isFinite, Float(y).isFinite, Float(z).isFinite else {
                throw ExportError.invalidMesh(
                    "USD point \(index) is outside the point3f range."
                )
            }
            return USDPoint3D(x: x, y: y, z: z)
        }
    }

    private func integerIndices(_ indices: [UInt32]) throws -> [Int] {
        try indices.map { index in
            guard let converted = Int(exactly: index) else {
                throw ExportError.invalidMesh(
                    "USD mesh index \(index) exceeds the platform integer range."
                )
            }
            return converted
        }
    }

    private func authorNormals(
        _ normals: [Vector3D],
        for mesh: USDGeomMesh,
        in stage: inout USDStage
    ) throws {
        guard !normals.isEmpty else { return }
        let values = normals.map {
            SdfVector(
                precision: .float,
                role: .normal,
                values: [$0.x, $0.y, $0.z]
            )
        }
        let attribute = try stage.createAttribute(
            at: mesh.prim.path,
            name: "normals",
            typeName: "normal3f[]",
            typedDefaultValue: .vectorArray(values)
        )
        try stage.setField(
            .token(USDGeomPrimvarInterpolation.vertex.rawValue),
            named: "interpolation",
            at: attribute.path
        )
    }

    private func authorTextureCoordinates(
        _ textureCoordinates: [Point2D],
        for mesh: USDGeomMesh,
        in stage: inout USDStage
    ) throws {
        guard !textureCoordinates.isEmpty else { return }
        let values = try textureCoordinates.enumerated().map { index, value in
            guard Float(value.x).isFinite, Float(value.y).isFinite else {
                throw ExportError.invalidMesh(
                    "USD texture coordinate \(index) is outside the texCoord2f range."
                )
            }
            return SdfVector(
                precision: .float,
                role: .texCoord,
                values: [value.x, value.y]
            )
        }
        _ = try USDGeomPrimvarsAPI(prim: mesh.prim).createPrimvar(
            named: "st",
            typeName: "texCoord2f[]",
            interpolation: .vertex,
            defaultValue: .vectorArray(values),
            in: &stage
        )
    }

    private func authorVertexColors(
        _ colors: [ColorRGBA],
        for mesh: USDGeomMesh,
        in stage: inout USDStage
    ) throws {
        guard !colors.isEmpty else { return }
        let colorValues = colors.map {
            SdfVector(
                precision: .float,
                role: .color,
                values: [$0.r, $0.g, $0.b]
            )
        }
        let opacityValues = colors.map { Float($0.a) }
        let primvars = USDGeomPrimvarsAPI(prim: mesh.prim)
        _ = try primvars.createPrimvar(
            named: "displayColor",
            typeName: "color3f[]",
            interpolation: .vertex,
            defaultValue: .vectorArray(colorValues),
            in: &stage
        )
        _ = try primvars.createPrimvar(
            named: "displayOpacity",
            typeName: "float[]",
            interpolation: .vertex,
            defaultValue: .floatArray(opacityValues),
            in: &stage
        )
    }
}
