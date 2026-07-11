import CADCore
import CADIR

struct BRepModelDelta: Sendable {
    var curves: DictionaryDelta<CurveID, Curve3D>
    var surfaces: DictionaryDelta<SurfaceID, Surface3D>
    var bodies: DictionaryDelta<BodyID, Body>
    var shells: DictionaryDelta<ShellID, Shell>
    var faces: DictionaryDelta<FaceID, Face>
    var loops: DictionaryDelta<LoopID, Loop>
    var edges: DictionaryDelta<EdgeID, Edge>
    var vertices: DictionaryDelta<VertexID, Vertex>

    init() {
        curves = DictionaryDelta()
        surfaces = DictionaryDelta()
        bodies = DictionaryDelta()
        shells = DictionaryDelta()
        faces = DictionaryDelta()
        loops = DictionaryDelta()
        edges = DictionaryDelta()
        vertices = DictionaryDelta()
    }

    init(before: BRepModel, after: BRepModel) {
        curves = DictionaryDelta(before: before.geometry.curves, after: after.geometry.curves)
        surfaces = DictionaryDelta(before: before.geometry.surfaces, after: after.geometry.surfaces)
        bodies = DictionaryDelta(before: before.bodies, after: after.bodies)
        shells = DictionaryDelta(before: before.shells, after: after.shells)
        faces = DictionaryDelta(before: before.faces, after: after.faces)
        loops = DictionaryDelta(before: before.loops, after: after.loops)
        edges = DictionaryDelta(before: before.edges, after: after.edges)
        vertices = DictionaryDelta(before: before.vertices, after: after.vertices)
    }

    var changeCount: Int {
        curves.changeCount
            + surfaces.changeCount
            + bodies.changeCount
            + shells.changeCount
            + faces.changeCount
            + loops.changeCount
            + edges.changeCount
            + vertices.changeCount
    }

    var changedBodyIDs: Set<BodyID> {
        Set(bodies.removed.keys)
            .union(bodies.inserted.keys)
            .union(bodies.updated.keys)
    }

    var inverted: BRepModelDelta {
        BRepModelDelta(
            curves: curves.inverted,
            surfaces: surfaces.inverted,
            bodies: bodies.inverted,
            shells: shells.inverted,
            faces: faces.inverted,
            loops: loops.inverted,
            edges: edges.inverted,
            vertices: vertices.inverted
        )
    }

    func validate(against model: BRepModel) throws {
        try curves.validate(in: model.geometry.curves, tableName: "curves")
        try surfaces.validate(in: model.geometry.surfaces, tableName: "surfaces")
        try bodies.validate(in: model.bodies, tableName: "bodies")
        try shells.validate(in: model.shells, tableName: "shells")
        try faces.validate(in: model.faces, tableName: "faces")
        try loops.validate(in: model.loops, tableName: "loops")
        try edges.validate(in: model.edges, tableName: "edges")
        try vertices.validate(in: model.vertices, tableName: "vertices")
    }

    func apply(to model: inout BRepModel) throws {
        try validate(against: model)

        curves.applyValidated(to: &model.geometry.curves)
        surfaces.applyValidated(to: &model.geometry.surfaces)
        bodies.applyValidated(to: &model.bodies)
        shells.applyValidated(to: &model.shells)
        faces.applyValidated(to: &model.faces)
        loops.applyValidated(to: &model.loops)
        edges.applyValidated(to: &model.edges)
        vertices.applyValidated(to: &model.vertices)
    }

    func applying(to model: BRepModel) throws -> BRepModel {
        var result = model
        try apply(to: &result)
        return result
    }
}

private extension BRepModelDelta {
    init(
        curves: DictionaryDelta<CurveID, Curve3D>,
        surfaces: DictionaryDelta<SurfaceID, Surface3D>,
        bodies: DictionaryDelta<BodyID, Body>,
        shells: DictionaryDelta<ShellID, Shell>,
        faces: DictionaryDelta<FaceID, Face>,
        loops: DictionaryDelta<LoopID, Loop>,
        edges: DictionaryDelta<EdgeID, Edge>,
        vertices: DictionaryDelta<VertexID, Vertex>
    ) {
        self.curves = curves
        self.surfaces = surfaces
        self.bodies = bodies
        self.shells = shells
        self.faces = faces
        self.loops = loops
        self.edges = edges
        self.vertices = vertices
    }
}
