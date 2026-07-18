import CADCore
import CADIR

func validateImportedMesh(
    _ mesh: Mesh,
    formatName: String,
    tolerance: ModelingTolerance
) throws {
    do {
        try mesh.validate(tolerance: tolerance)
    } catch let error as ExportError {
        throw ImportError.invalidData("\(formatName) mesh is invalid: \(error).")
    }
}
