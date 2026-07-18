import CADCore

final class PlanarBooleanBSPNode {
    private var plane: PlanarBooleanPlane?
    private var polygons: [PlanarBooleanPolygon] = []
    private var front: PlanarBooleanBSPNode?
    private var back: PlanarBooleanBSPNode?
    private let tolerance: ModelingTolerance

    init(
        polygons: [PlanarBooleanPolygon] = [],
        tolerance: ModelingTolerance
    ) throws {
        self.tolerance = tolerance
        if polygons.isEmpty == false {
            try build(polygons)
        }
    }

    func inverted() throws {
        polygons = try polygons.map { try $0.inverted(tolerance: tolerance) }
        plane = plane?.inverted
        try front?.inverted()
        try back?.inverted()
        swap(&front, &back)
    }

    func clip(to other: PlanarBooleanBSPNode) throws {
        polygons = try other.clipped(polygons)
        try front?.clip(to: other)
        try back?.clip(to: other)
    }

    func clipped(_ input: [PlanarBooleanPolygon]) throws -> [PlanarBooleanPolygon] {
        guard let plane else { return input }
        var frontPolygons: [PlanarBooleanPolygon] = []
        var backPolygons: [PlanarBooleanPolygon] = []
        for polygon in input {
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
            )
            frontPolygons.append(contentsOf: coplanarFront)
            frontPolygons.append(contentsOf: splitFront)
            backPolygons.append(contentsOf: coplanarBack)
            backPolygons.append(contentsOf: splitBack)
        }
        if let front {
            frontPolygons = try front.clipped(frontPolygons)
        }
        if let back {
            backPolygons = try back.clipped(backPolygons)
        } else {
            backPolygons.removeAll(keepingCapacity: false)
        }
        return frontPolygons + backPolygons
    }

    func allPolygons() -> [PlanarBooleanPolygon] {
        polygons + (front?.allPolygons() ?? []) + (back?.allPolygons() ?? [])
    }

    func build(_ input: [PlanarBooleanPolygon]) throws {
        guard input.isEmpty == false else { return }
        if plane == nil {
            plane = input[0].plane
        }
        guard let plane else { return }
        var frontPolygons: [PlanarBooleanPolygon] = []
        var backPolygons: [PlanarBooleanPolygon] = []
        for polygon in input {
            var coplanarFront: [PlanarBooleanPolygon] = []
            var coplanarBack: [PlanarBooleanPolygon] = []
            try plane.split(
                polygon,
                coplanarFront: &coplanarFront,
                coplanarBack: &coplanarBack,
                front: &frontPolygons,
                back: &backPolygons,
                tolerance: tolerance
            )
            polygons.append(contentsOf: coplanarFront)
            polygons.append(contentsOf: coplanarBack)
        }
        if frontPolygons.isEmpty == false {
            if front == nil {
                front = try PlanarBooleanBSPNode(tolerance: tolerance)
            }
            try front?.build(frontPolygons)
        }
        if backPolygons.isEmpty == false {
            if back == nil {
                back = try PlanarBooleanBSPNode(tolerance: tolerance)
            }
            try back?.build(backPolygons)
        }
    }
}
