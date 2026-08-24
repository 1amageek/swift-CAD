import CADCore
import CADIR
import CADModeling
import CADTopology

final class BRepEditBuffer {
    private var storage: BRepModel
    private var exactBodyCertificates: [BodyID: ValidatedBRepModel]

    init() {
        storage = BRepModel()
        exactBodyCertificates = [:]
    }

    init(validatedModel: ValidatedBRepModel) {
        storage = validatedModel.model
        exactBodyCertificates = [:]
        certifyBodies(in: validatedModel)
    }

    func scopedModel(bodyIDs: Set<BodyID>) throws -> BRepModel {
        guard !bodyIDs.isEmpty else {
            return BRepModel()
        }
        return try BRepBodySubmodelExtractor().extract(bodyIDs: bodyIDs, from: storage)
    }

    func validatedScopedModel(
        bodyIDs: Set<BodyID>,
        tolerance: ModelingTolerance
    ) throws -> ValidatedBRepModel {
        let model = try scopedModel(bodyIDs: bodyIDs)
        let certificates = Dictionary(uniqueKeysWithValues: bodyIDs.compactMap { bodyID in
            exactBodyCertificates[bodyID].map { (bodyID, $0) }
        })
        if certificates.count == bodyIDs.count {
            return try ValidatedBRepModel(
                composingValidatedBodies: certificates,
                as: model,
                tolerance: tolerance
            )
        }

        let validated = try ValidatedBRepModel(
            model,
            tolerance: tolerance,
            validationLevel: .exact
        )
        certifyBodies(in: validated)
        return validated
    }

    func fullModel() -> BRepModel {
        storage
    }

    func apply(
        _ delta: BRepModelDelta,
        invalidatingBodyIDs: Set<BodyID>
    ) throws {
        try delta.apply(to: &storage)
        for bodyID in invalidatingBodyIDs {
            exactBodyCertificates.removeValue(forKey: bodyID)
        }
    }

    func apply(
        _ delta: BRepModelDelta,
        replacingBodyIDs: Set<BodyID>,
        with validatedModel: ValidatedBRepModel
    ) throws {
        try delta.apply(to: &storage)
        for bodyID in replacingBodyIDs {
            exactBodyCertificates.removeValue(forKey: bodyID)
        }
        certifyBodies(in: validatedModel)
    }

    func validate(_ delta: BRepModelDelta) throws {
        try delta.validate(against: storage)
    }

    func replace(with validatedModel: ValidatedBRepModel) {
        storage = validatedModel.model
        exactBodyCertificates.removeAll(keepingCapacity: true)
        certifyBodies(in: validatedModel)
    }

    func finalizedValidatedModel(
        tolerance: ModelingTolerance
    ) throws -> ValidatedBRepModel {
        let bodyIDs = Set(storage.bodies.keys)
        let certificates = Dictionary(uniqueKeysWithValues: bodyIDs.compactMap { bodyID in
            exactBodyCertificates[bodyID].map { (bodyID, $0) }
        })
        if certificates.count == bodyIDs.count {
            return try ValidatedBRepModel(
                composingValidatedBodies: certificates,
                as: storage,
                tolerance: tolerance
            )
        }
        let validated = try ValidatedBRepModel(
            storage,
            tolerance: tolerance,
            validationLevel: .exact
        )
        certifyBodies(in: validated)
        return validated
    }

    private func certifyBodies(in validatedModel: ValidatedBRepModel) {
        guard validatedModel.validationLevel != .modeling else {
            return
        }
        for bodyID in validatedModel.model.bodies.keys {
            exactBodyCertificates[bodyID] = validatedModel
        }
    }
}
