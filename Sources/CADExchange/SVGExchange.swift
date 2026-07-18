import Foundation
import CADCore
import CADIR

public struct SVGExchange: Sendable {
    private let tolerance: ModelingTolerance

    public init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    public func write(meshes: [BodyID: Mesh], unit: LengthUnit = .meter, to sink: any ByteSink) throws {
        guard !meshes.isEmpty else {
            throw ExportError.emptyMesh
        }
        let sortedMeshes = meshes.sorted(by: { $0.key.description < $1.key.description })
        var bounds = SVGExportBounds()
        var polygonCount = 0
        for (_, mesh) in sortedMeshes {
            try mesh.validate(tolerance: tolerance)
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
        try sink.writeUTF8("<svg xmlns=\"http://www.w3.org/2000/svg\" data-generator=\"Swift-CAD\" data-unit=\"\(unit.rawValue)\" viewBox=\"\(bounds.viewBox)\">")
        for (_, mesh) in sortedMeshes {
            var index = 0
            while index < mesh.indices.count {
                let points = [
                    mesh.positions[Int(mesh.indices[index])],
                    mesh.positions[Int(mesh.indices[index + 1])],
                    mesh.positions[Int(mesh.indices[index + 2])]
                ]
                if hasNonDegenerateXYProjection(points, tolerance: tolerance) {
                    try writeSVGPolygon(points: points, unit: unit, to: sink)
                }
                index += 3
            }
        }
        try sink.writeUTF8("\n</svg>")
    }

    public func `import`(_ source: any ByteSource, unit: LengthUnit = .meter) throws -> ImportedExchangeModel {
        try source.withNoCopyData { data in
            guard String(data: data, encoding: .utf8) != nil else {
                throw ImportError.invalidData("SVG data is not UTF-8.")
            }
            return try importData(data, unit: unit)
        }
    }

    private func importData(_ data: Data, unit: LengthUnit) throws -> ImportedExchangeModel {
        let model = try SVGXMLReader.read(data, fallbackUnit: unit, tolerance: tolerance)
        let importUnit = model.unit
        var positions: [Point3D] = []
        var indices: [UInt32] = []
        for points in model.polygons {
            for localIndex in 1..<(points.count - 1) {
                for point in [points[0], points[localIndex], points[localIndex + 1]] {
                    positions.append(point)
                    indices.append(UInt32(positions.count - 1))
                }
            }
        }
        let mesh = Mesh(positions: positions, normals: [], indices: indices)
        try validateImportedMesh(mesh, formatName: "SVG", tolerance: tolerance)
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
