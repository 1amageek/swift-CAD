import CADCore
import CADIR
import CADModeling
import CADTopology

final class BRepEditBuffer {
    private var storage: BRepModel

    init(model: BRepModel = BRepModel()) {
        self.storage = model
    }

    func scopedModel(bodyIDs: Set<BodyID>) throws -> BRepModel {
        guard !bodyIDs.isEmpty else {
            return BRepModel()
        }
        return try BRepBodySubmodelExtractor().extract(bodyIDs: bodyIDs, from: storage)
    }

    func fullModel() -> BRepModel {
        storage
    }

    func apply(_ delta: BRepModelDelta) throws {
        try delta.apply(to: &storage)
    }

    func validate(_ delta: BRepModelDelta) throws {
        try delta.validate(against: storage)
    }

    func replace(with model: BRepModel) {
        storage = model
    }

    func finalizedModel() -> BRepModel {
        storage
    }
}
