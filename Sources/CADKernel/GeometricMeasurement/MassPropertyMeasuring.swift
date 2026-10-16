import CADCore
import CADGeometry
import CADIR
import CADTopology

public protocol MassPropertyMeasuring: Sendable {
    func measure(_ components: [MassPropertyComponent], in document: EvaluatedDocument,
        options: BRepVolumeMomentOptions, reference: Point3D) throws -> MassPropertyMeasurement
    func measure(_ components: [MassPropertyComponent], in document: EvaluatedDocument,
        options: BRepVolumeMomentOptions, modelLengthUnit: LengthUnit,
        reference: Point3D) throws -> MassPropertyMeasurement
    func measure(_ components: [MassPropertyComponent], in document: EvaluatedDocument,
        options: BRepVolumeMomentOptions, reference: Point3D,
        using execution: inout OriginalQueryExecution) throws -> MassPropertyMeasurement
    func measure(_ components: [MassPropertyComponent], in document: EvaluatedDocument,
        options: BRepVolumeMomentOptions, modelLengthUnit: LengthUnit,
        reference: Point3D, using execution: inout OriginalQueryExecution) throws -> MassPropertyMeasurement
}

public extension MassPropertyMeasuring {
    func measure(_ components: [MassPropertyComponent], in document: EvaluatedDocument,
        options: BRepVolumeMomentOptions, reference: Point3D) throws -> MassPropertyMeasurement {
        try measure(components, in: document, options: options,
            modelLengthUnit: document.document.units.length, reference: reference)
    }
}
