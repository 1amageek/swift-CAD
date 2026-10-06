import CADCore

/// Immutable preparation shared by full-domain and material-trim consumers.
package protocol OriginalSurfaceEmbeddingSession: Sendable {
    func certify() throws
    func visitCrossContacts(
        excluding: (SurfaceParameterBox, Int) throws -> Bool,
        admit: (SurfaceSurfaceIntersection, SurfaceParameterBox, SurfaceParameterBox, Int) throws -> Void
    ) throws
}
