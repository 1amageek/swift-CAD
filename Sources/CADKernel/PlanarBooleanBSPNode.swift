import CADCore
import CADTopology
import CADGeometry

final class PlanarBooleanBSPNode {
    private var plane: PlanarBooleanPlane?
    private var polygons: [PlanarBooleanPolygon] = []
    private var front: PlanarBooleanBSPNode?
    private var back: PlanarBooleanBSPNode?
    private let tolerance: ModelingTolerance

    init(
        polygons: [PlanarBooleanPolygon] = [],
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws {
        try execution.visitGeometricCell(depth: 0)
        self.tolerance = tolerance
        if polygons.isEmpty == false {
            try build(polygons, using: &execution)
        }
    }

    func inverted(using execution: inout OriginalQueryExecution) throws {
        try execution.visitGeometricCell(depth: 0)
        polygons = try polygons.map { try $0.inverted(tolerance: tolerance, using: &execution) }
        plane = plane?.inverted
        if let front {
            try execution.withGeometricDepthOffset(1) { execution in
                try front.inverted(using: &execution)
            }
        }
        if let back {
            try execution.withGeometricDepthOffset(1) { execution in
                try back.inverted(using: &execution)
            }
        }
        swap(&front, &back)
    }

    func clip(to other: PlanarBooleanBSPNode, using execution: inout OriginalQueryExecution) throws {
        try execution.visitGeometricCell(depth: 0)
        polygons = try other.clipped(polygons, using: &execution)
        if let front {
            try execution.withGeometricDepthOffset(1) { execution in
                try front.clip(to: other, using: &execution)
            }
        }
        if let back {
            try execution.withGeometricDepthOffset(1) { execution in
                try back.clip(to: other, using: &execution)
            }
        }
    }

    func clipped(_ input: [PlanarBooleanPolygon], using execution: inout OriginalQueryExecution) throws -> [PlanarBooleanPolygon] {
        try execution.visitGeometricCell(depth: 0)
        guard let plane else { return input }
        var frontPolygons: [PlanarBooleanPolygon] = []
        var backPolygons: [PlanarBooleanPolygon] = []
        for polygon in input {
            try execution.visitGeometricCell(depth: 0)
            var coplanarFront: [PlanarBooleanPolygon] = []
            var coplanarBack: [PlanarBooleanPolygon] = []
            var splitFront: [PlanarBooleanPolygon] = []
            var splitBack: [PlanarBooleanPolygon] = []
            try plane.split(
                polygon,
                coplanarFront: &coplanarFront,
                coplanarBack: &coplanarBack,
                front: &splitFront,
                back: &splitBack,
                tolerance: tolerance
            , using: &execution)
            try OriginalParameterQueryStorage.append(contentsOf: coplanarFront, to: &frontPolygons, using: &execution)
            try OriginalParameterQueryStorage.append(contentsOf: splitFront, to: &frontPolygons, using: &execution)
            try OriginalParameterQueryStorage.append(contentsOf: coplanarBack, to: &backPolygons, using: &execution)
            try OriginalParameterQueryStorage.append(contentsOf: splitBack, to: &backPolygons, using: &execution)
        }
        if let front {
            frontPolygons = try execution.withGeometricDepthOffset(1) { execution in
                try front.clipped(frontPolygons, using: &execution)
            }
        }
        if let back {
            backPolygons = try execution.withGeometricDepthOffset(1) { execution in
                try back.clipped(backPolygons, using: &execution)
            }
        } else {
            backPolygons.removeAll(keepingCapacity: false)
        }
        return try OriginalParameterQueryStorage.concatenated(frontPolygons, backPolygons, using: &execution)
    }

    func allPolygons(using execution: inout OriginalQueryExecution) throws -> [PlanarBooleanPolygon] {
        try execution.visitGeometricCell(depth: 0)
        let frontPolygons: [PlanarBooleanPolygon]
        if let front {
            frontPolygons = try execution.withGeometricDepthOffset(1) { execution in
                try front.allPolygons(using: &execution)
            }
        } else {
            frontPolygons = []
        }
        let backPolygons: [PlanarBooleanPolygon]
        if let back {
            backPolygons = try execution.withGeometricDepthOffset(1) { execution in
                try back.allPolygons(using: &execution)
            }
        } else {
            backPolygons = []
        }
        let first = try OriginalParameterQueryStorage.concatenated(polygons, frontPolygons, using: &execution)
        return try OriginalParameterQueryStorage.concatenated(first, backPolygons, using: &execution)
    }

    func build(_ input: [PlanarBooleanPolygon], using execution: inout OriginalQueryExecution) throws {
        try execution.visitGeometricCell(depth: 0)
        guard input.isEmpty == false else { return }
        if plane == nil {
            plane = input[0].plane
        }
        guard let plane else { return }
        var frontPolygons: [PlanarBooleanPolygon] = []
        var backPolygons: [PlanarBooleanPolygon] = []
        for polygon in input {
            try execution.visitGeometricCell(depth: 0)
            var coplanarFront: [PlanarBooleanPolygon] = []
            var coplanarBack: [PlanarBooleanPolygon] = []
            try plane.split(
                polygon,
                coplanarFront: &coplanarFront,
                coplanarBack: &coplanarBack,
                front: &frontPolygons,
                back: &backPolygons,
                tolerance: tolerance
            , using: &execution)
            try OriginalParameterQueryStorage.append(contentsOf: coplanarFront, to: &polygons, using: &execution)
            try OriginalParameterQueryStorage.append(contentsOf: coplanarBack, to: &polygons, using: &execution)
        }
        if frontPolygons.isEmpty == false {
            if front == nil {
                front = try PlanarBooleanBSPNode(tolerance: tolerance, using: &execution)
            }
            try execution.withGeometricDepthOffset(1) { execution in
                try front?.build(frontPolygons, using: &execution)
            }
        }
        if backPolygons.isEmpty == false {
            if back == nil {
                back = try PlanarBooleanBSPNode(tolerance: tolerance, using: &execution)
            }
            try execution.withGeometricDepthOffset(1) { execution in
                try back?.build(backPolygons, using: &execution)
            }
        }
    }
}
