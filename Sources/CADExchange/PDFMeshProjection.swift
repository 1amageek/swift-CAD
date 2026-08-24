import Foundation
import CADCore
import CADIR

struct PDFMeshProjection: Sendable {
    struct Point: Sendable {
        let x: Double
        let y: Double
    }

    enum Plane: String, Sendable {
        case xy = "XY"
        case xz = "XZ"
        case yz = "YZ"
    }

    let plane: Plane
    let triangles: [[Point]]

    init(
        meshes: [(key: BodyID, value: Mesh)],
        budget: ExchangeProcessingBudget
    ) throws {
        let selectedPlane = Self.bestPlane(for: meshes)
        plane = selectedPlane
        let rawPoints = meshes.flatMap { pair in
            pair.value.positions.map { Self.project($0, onto: selectedPlane) }
        }
        guard let maximumMagnitude = rawPoints.lazy
            .flatMap({ [abs($0.x), abs($0.y)] })
            .max() else {
            throw ExportError.emptyMesh
        }
        let normalization = maximumMagnitude > 0.0 ? maximumMagnitude : 1.0
        let normalizedPoints = rawPoints.map { Point(x: $0.x / normalization, y: $0.y / normalization) }
        guard let minX = normalizedPoints.lazy.map(\.x).min(),
              let maxX = normalizedPoints.lazy.map(\.x).max(),
              let minY = normalizedPoints.lazy.map(\.y).min(),
              let maxY = normalizedPoints.lazy.map(\.y).max() else {
            throw ExportError.emptyMesh
        }

        let pageBounds = PDFProjectionPageBounds()
        let width = max(maxX - minX, Double.leastNormalMagnitude)
        let height = max(maxY - minY, Double.leastNormalMagnitude)
        let scale = min(pageBounds.width / width, pageBounds.height / height)
        let xOffset = pageBounds.minX + (pageBounds.width - width * scale) * 0.5
        let yOffset = pageBounds.minY + (pageBounds.height - height * scale) * 0.5

        var result: [[Point]] = []
        result.reserveCapacity(meshes.reduce(0) { $0 + $1.value.indices.count / 3 })
        var iteration = 0
        for (_, mesh) in meshes {
            var index = 0
            while index < mesh.indices.count {
                if iteration.isMultiple(of: 1_024) {
                    try budget.check(format: .pdf)
                }
                result.append([
                    Self.pagePoint(
                        Self.project(mesh.positions[Int(mesh.indices[index])], onto: selectedPlane),
                        normalization: normalization,
                        minX: minX,
                        minY: minY,
                        scale: scale,
                        xOffset: xOffset,
                        yOffset: yOffset
                    ),
                    Self.pagePoint(
                        Self.project(mesh.positions[Int(mesh.indices[index + 1])], onto: selectedPlane),
                        normalization: normalization,
                        minX: minX,
                        minY: minY,
                        scale: scale,
                        xOffset: xOffset,
                        yOffset: yOffset
                    ),
                    Self.pagePoint(
                        Self.project(mesh.positions[Int(mesh.indices[index + 2])], onto: selectedPlane),
                        normalization: normalization,
                        minX: minX,
                        minY: minY,
                        scale: scale,
                        xOffset: xOffset,
                        yOffset: yOffset
                    ),
                ])
                iteration += 1
                index += 3
            }
        }
        triangles = result
    }

    private static func bestPlane(for meshes: [(key: BodyID, value: Mesh)]) -> Plane {
        var xyScore = 0.0
        var xzScore = 0.0
        var yzScore = 0.0
        for (_, mesh) in meshes {
            var index = 0
            while index < mesh.indices.count {
                let first = mesh.positions[Int(mesh.indices[index])]
                let second = mesh.positions[Int(mesh.indices[index + 1])]
                let third = mesh.positions[Int(mesh.indices[index + 2])]
                let area = (second - first).cross(third - first)
                xyScore = max(xyScore, abs(area.z))
                xzScore = max(xzScore, abs(area.y))
                yzScore = max(yzScore, abs(area.x))
                index += 3
            }
        }
        if xyScore >= xzScore, xyScore >= yzScore {
            return .xy
        }
        if xzScore >= yzScore {
            return .xz
        }
        return .yz
    }

    private static func project(_ point: Point3D, onto plane: Plane) -> Point {
        switch plane {
        case .xy:
            Point(x: point.x, y: point.y)
        case .xz:
            Point(x: point.x, y: point.z)
        case .yz:
            Point(x: point.y, y: point.z)
        }
    }

    private static func pagePoint(
        _ point: Point,
        normalization: Double,
        minX: Double,
        minY: Double,
        scale: Double,
        xOffset: Double,
        yOffset: Double
    ) -> Point {
        Point(
            x: xOffset + (point.x / normalization - minX) * scale,
            y: yOffset + (point.y / normalization - minY) * scale
        )
    }
}

private struct PDFProjectionPageBounds {
    let minX = 48.0
    let minY = 48.0
    let width = 516.0
    let height = 570.0
}
