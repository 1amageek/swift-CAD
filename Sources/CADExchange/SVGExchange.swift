import Foundation
import CADCore
import CADIR

public struct SVGExchange: Sendable {
    private let tolerance: ModelingTolerance
    private let resourceLimits: ExchangeResourceLimits
    private let triangulator: ExchangePolygonTriangulator

    public init(
        tolerance: ModelingTolerance,
        resourceLimits: ExchangeResourceLimits = .standard
    ) {
        self.tolerance = tolerance
        self.resourceLimits = resourceLimits
        triangulator = ExchangePolygonTriangulator()
    }

    public func write(meshes: [BodyID: Mesh], unit: LengthUnit = .meter, to sink: any ByteSink) throws {
        guard !meshes.isEmpty else {
            throw ExportError.emptyMesh
        }
        let sortedMeshes = meshes.sorted(by: { $0.key.description < $1.key.description })
        var resources = try ExchangeResourceAccountant(limits: resourceLimits, format: .svg)
        var bounds = SVGExportBounds()
        var polygonCount = 0
        for (_, mesh) in sortedMeshes {
            try mesh.validate(tolerance: tolerance)
            try resources.recordEntities(1 + mesh.positions.count + mesh.indices.count / 3)
            try resources.recordIterations(mesh.positions.count + mesh.indices.count)
            var index = 0
            while index < mesh.indices.count {
                let points = [
                    mesh.positions[Int(mesh.indices[index])],
                    mesh.positions[Int(mesh.indices[index + 1])],
                    mesh.positions[Int(mesh.indices[index + 2])]
                ]
                guard hasNonDegenerateXYProjection(points, tolerance: tolerance) else {
                    index += 3
                    continue
                }
                try includeSVGExportBounds(points: points, unit: unit, bounds: &bounds)
                polygonCount += 1
                index += 3
            }
        }
        guard polygonCount > 0 else {
            throw ExportError.invalidMesh("SVG projection contains no non-degenerate polygons.")
        }
        let output = try ExchangeBoundedByteSink(
            downstream: sink,
            limits: resourceLimits,
            format: .svg
        )
        try output.writeUTF8("<svg xmlns=\"http://www.w3.org/2000/svg\" data-generator=\"Swift-CAD\" data-unit=\"\(unit.rawValue)\" viewBox=\"\(bounds.viewBox)\">")
        for (_, mesh) in sortedMeshes {
            var index = 0
            while index < mesh.indices.count {
                let points = [
                    mesh.positions[Int(mesh.indices[index])],
                    mesh.positions[Int(mesh.indices[index + 1])],
                    mesh.positions[Int(mesh.indices[index + 2])]
                ]
                if hasNonDegenerateXYProjection(points, tolerance: tolerance) {
                    try writeSVGPolygon(points: points, unit: unit, to: output)
                }
                index += 3
            }
        }
        try output.writeUTF8("\n</svg>")
    }

    public func `import`(_ source: any ByteSource, unit: LengthUnit = .meter) throws -> ImportedExchangeModel {
        var resources = try ExchangeResourceAccountant(limits: resourceLimits, format: .svg)
        try resources.validateInputByteCount(source.count)
        try resources.recordIterations(source.count)
        return try source.withNoCopyData { data in
            guard String(data: data, encoding: .utf8) != nil else {
                throw ImportError.invalidData("SVG data is not UTF-8.")
            }
            return try importData(data, unit: unit, resources: &resources)
        }
    }

    private func importData(
        _ data: Data,
        unit: LengthUnit,
        resources: inout ExchangeResourceAccountant
    ) throws -> ImportedExchangeModel {
        let model = try SVGXMLReader.read(
            data,
            fallbackUnit: unit,
            tolerance: tolerance,
            resources: &resources
        )
        let importUnit = model.unit
        var positions: [Point3D] = []
        var indices: [UInt32] = []
        for points in model.polygons {
            let triangles = try triangulator.triangles(for: points, tolerance: tolerance)
            try resources.recordEntities(triangles.count)
            for triangle in triangles {
                for localIndex in [triangle.0, triangle.1, triangle.2] {
                    guard UInt64(positions.count) < UInt64(UInt32.max) else {
                        throw ImportError.invalidData("SVG mesh vertex count exceeds UInt32 range.")
                    }
                    let point = points[localIndex]
                    positions.append(point)
                    indices.append(UInt32(positions.count - 1))
                }
            }
        }
        let mesh = Mesh(positions: positions, normals: [], indices: indices)
        try validateImportedMesh(mesh, formatName: "SVG", tolerance: tolerance)
        try resources.checkTime()
        return ImportedExchangeModel(format: .svg, meshes: [BodyID(): mesh], units: UnitSystem(length: importUnit, angle: .radian))
    }
}

private func includeSVGExportBounds(points: [Point3D], unit: LengthUnit, bounds: inout SVGExportBounds) throws {
    for point in points {
        let x = try checkedExportUnitValue(
            unit.fromInternal(point.x),
            formatName: "SVG",
            component: "point.x"
        )
        let y = try checkedExportUnitValue(
            unit.fromInternal(-point.y),
            formatName: "SVG",
            component: "point.y"
        )
        bounds.include(x: x, y: y)
    }
}

private func writeSVGPolygon(points: [Point3D], unit: LengthUnit, to sink: any ByteSink) throws {
    try sink.writeUTF8("\n<polygon points=\"")
    var isFirst = true
    for point in points {
        let x = try checkedExportUnitValue(
            unit.fromInternal(point.x),
            formatName: "SVG",
            component: "point.x"
        )
        let y = try checkedExportUnitValue(
            unit.fromInternal(-point.y),
            formatName: "SVG",
            component: "point.y"
        )
        if !isFirst {
            try sink.writeUTF8(" ")
        }
        isFirst = false
        try sink.writeUTF8("\(svgNumber(x)),\(svgNumber(y))")
    }
    try sink.writeUTF8("\" fill=\"none\" stroke=\"black\"/>")
}

private struct SVGExportBounds {
    private var minX: Double?
    private var minY: Double?
    private var maxX: Double?
    private var maxY: Double?

    mutating func include(x: Double, y: Double) {
        minX = min(minX ?? x, x)
        minY = min(minY ?? y, y)
        maxX = max(maxX ?? x, x)
        maxY = max(maxY ?? y, y)
    }

    var viewBox: String {
        let x = minX ?? 0.0
        let y = minY ?? 0.0
        let width = max((maxX ?? x) - x, 1.0)
        let height = max((maxY ?? y) - y, 1.0)
        return "\(svgNumber(x)) \(svgNumber(y)) \(svgNumber(width)) \(svgNumber(height))"
    }
}

private func svgNumber(_ value: Double) -> String {
    String(format: "%.17g", locale: Locale(identifier: "en_US_POSIX"), value)
}

private func hasNonDegenerateXYProjection(
    _ points: [Point3D],
    tolerance: ModelingTolerance
) -> Bool {
    guard points.count == 3 else {
        return false
    }
    let first = points[0]
    let second = points[1]
    let third = points[2]
    let twiceArea = (second.x - first.x) * (third.y - first.y)
        - (second.y - first.y) * (third.x - first.x)
    return abs(twiceArea) > tolerance.distance * tolerance.distance
}
