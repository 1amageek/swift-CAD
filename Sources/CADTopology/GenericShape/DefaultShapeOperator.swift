import HashTreeCollections
import CADCore
import CADGeometry

/// Common topology and exact rigid-image operations for every shape dimension.
public struct DefaultShapeOperator: ShapeOperating {
    public init() {}

    public func validate(_ shape: any ShapeRepresenting, tolerance: ModelingTolerance) throws {
        _ = try extract(shape, tolerance: tolerance)
    }

    public func extract(_ shape: any ShapeRepresenting, tolerance: ModelingTolerance) throws -> Shape {
        try tolerance.validate()
        let snapshot = shape.shapeSnapshot()
        let resolver = ShapeClosureResolver()
        let model = try resolver.extract(root: snapshot.root, from: snapshot.model)
        try resolver.validate(root: snapshot.root, in: model, tolerance: tolerance)
        return Shape(root: snapshot.root, model: model)
    }

    public func subshapes(
        of shape: any ShapeRepresenting,
        tolerance: ModelingTolerance
    ) throws -> [ShapeReference] {
        let selected = try extract(shape, tolerance: tolerance)
        let model = selected.model
        var result = model.vertices.keys.sorted().map(ShapeReference.vertex)
        result.append(contentsOf: model.edges.keys.sorted().map(ShapeReference.edge))
        var wires = Set<ShapeWire>()
        var pending = [selected.root]
        while let root = pending.popLast() {
            try CurrentTaskCancellationChecker().checkCancellation()
            switch root {
            case .compound(let roots): pending.append(contentsOf: roots.reversed())
            case .wire(let wire):
                if wires.insert(wire).inserted { result.append(.wire(wire)) }
            default: break
            }
        }
        for id in model.loops.keys.sorted() {
            try CurrentTaskCancellationChecker().checkCancellation()
            guard let loop = model.loops[id] else {
                throw TopologyError.missingReference("Missing selected shape loop \(id).")
            }
            let wire = ShapeWire(edges: loop.coedges.map {
                ShapeEdgeUse(edgeID: $0.edgeID, orientation: $0.orientation)
            })
            if wires.insert(wire).inserted { result.append(.wire(wire)) }
        }
        result.append(contentsOf: model.faces.keys.sorted().map(ShapeReference.face))
        result.append(contentsOf: model.shells.keys.sorted().map(ShapeReference.shell))
        result.append(contentsOf: model.bodies.keys.sorted().map(ShapeReference.solid))
        return result
    }

    public func transformed(
        _ shape: any ShapeRepresenting,
        by transform: RigidTransform3D,
        tolerance: ModelingTolerance
    ) throws -> Shape {
        try transform.validate(tolerance: tolerance)
        let source = try extract(shape, tolerance: tolerance)
        let model = try ShapeRigidImageBuilder().transform(source.model, by: transform, tolerance: tolerance)
        try ShapeClosureResolver().validate(root: source.root, in: model, tolerance: tolerance)
        return Shape(root: source.root, model: model)
    }
    public func transformed(
        validatedModel: ValidatedBRepModel,
        by transforms: [AffineTransform3D],
        maximumSubdivisionDepth: Int,
        remainingSourceDepth: Int,
        using execution: inout OriginalQueryExecution
    ) throws -> BRepModel {
        try ShapeAffineImageBuilder().transform(validatedModel.model,
            by: transforms, tolerance: validatedModel.tolerance,
            maximumSubdivisionDepth: maximumSubdivisionDepth,
            remainingSourceDepth: remainingSourceDepth, using: &execution)
    }

    public func transformed(
        validatedModel: ValidatedBRepModel,
        by operationWord: OriginalAffineOperationWord,
        maximumSubdivisionDepth: Int,
        remainingSourceDepth: Int,
        using execution: inout OriginalQueryExecution
    ) throws -> BRepModel {
        try ShapeAffineWordImageBuilder().transform(validatedModel.model,
            by: operationWord, tolerance: validatedModel.tolerance,
            maximumSubdivisionDepth: maximumSubdivisionDepth,
            remainingSourceDepth: remainingSourceDepth,
            using: &execution)
    }
}
