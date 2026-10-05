import CADCore
import CADGeometry
import CADIR
import CADTopology

/// Original geometric section components. Region assembly is a separate publication.
public struct BRepDrawingSection: Sendable {
    public let sourceDocument: CADDocument
    public let configuration: DocumentEvaluationConfiguration
    public let frame: OrthographicProjectionFrame
    /// Retained cutting authority; frame is output projection when this is present.
    public let cuttingSupport: BRepDrawingCuttingSupport?
    public let horizontalRange: ScalarInterval?
    public let verticalRange: ScalarInterval?
    let publicationIdentity: BRepDrawingSectionAuthority
    let originalBRep: BRepModel
    let workingBRep: BRepModel
    public let placement: BRepDrawingPlacement?
    public let consumedPreparationWork: Int
    public let retainedPreparationEntities: Int
    public let retainedPreparationBytes: Int
    let cuttingModel: BRepModel?
    let cuttingFaceID: FaceID?
    let splitGraph: BooleanUVSplitGraph?
    public let components: [BRepDrawingSectionComponent]
    init(sourceDocument: CADDocument, configuration: DocumentEvaluationConfiguration,
         frame: OrthographicProjectionFrame, horizontalRange: ScalarInterval?, verticalRange: ScalarInterval?,
         originalBRep: BRepModel, workingBRep: BRepModel? = nil, placement: BRepDrawingPlacement? = nil,
         consumedPreparationWork: Int = 0, retainedPreparationEntities: Int = 0, cuttingModel: BRepModel?, cuttingFaceID: FaceID?,
         splitGraph: BooleanUVSplitGraph?, components: [BRepDrawingSectionComponent],
         cuttingSupport: BRepDrawingCuttingSupport? = nil, retainedPreparationBytes: Int = 0) {
        publicationIdentity = BRepDrawingSectionAuthority()
        self.cuttingSupport = cuttingSupport
        self.retainedPreparationBytes = retainedPreparationBytes
        self.sourceDocument = sourceDocument; self.configuration = configuration; self.frame = frame
        self.horizontalRange = horizontalRange; self.verticalRange = verticalRange
        self.originalBRep = originalBRep; self.workingBRep = workingBRep ?? originalBRep
        self.placement = placement; self.consumedPreparationWork = consumedPreparationWork
        self.retainedPreparationEntities = retainedPreparationEntities
        self.cuttingModel = cuttingModel; self.cuttingFaceID = cuttingFaceID
        self.splitGraph = splitGraph; self.components = components
    }

    public func validateCurrent(_ evaluated: EvaluatedDocument) throws {
        try CurrentTaskCancellationChecker().checkCancellation()
        guard evaluated.document == sourceDocument, evaluated.configuration == configuration,
              evaluated.brep == originalBRep else {
            throw KernelError(phase: .evaluation, code: .missingReference,
                tolerance: configuration.tolerance,
                message: "The original section belongs to a different evaluated source or B-rep.")
        }
    }
    /// Visits world-law coincident contours under the caller's cumulative admission.
    public func visitCoincidentContours(componentOrdinal: Int, in evaluated: EvaluatedDocument,
                                       consumeUse: (Curve3D) throws -> Void,
                                       visit: (LoopID, Int, OrthographicProjectedEdge) throws -> Void) throws {
        try validateCurrent(evaluated)
        guard let component = components.first(where: { $0.ordinal == componentOrdinal }),
              case .coincident = component.geometry,
              let face = workingBRep.faces[component.faceID] else {
            throw KernelError(phase: .evaluation, code: .missingReference,
                tolerance: configuration.tolerance, message: "Coincident section component is absent or has no world source face.")
        }
        for loopID in face.loops {
            guard let loop = workingBRep.loops[loopID] else {
                throw KernelError(phase: .evaluation, code: .missingReference,
                    tolerance: configuration.tolerance, message: "Coincident section source loop is absent.")
            }
            for (ordinal, coedge) in loop.coedges.enumerated() {
                try CurrentTaskCancellationChecker().checkCancellation()
                guard let edge = workingBRep.edges[coedge.edgeID],
                      let curve = workingBRep.geometry.curves[edge.curveID] else {
                    throw KernelError(phase: .evaluation, code: .missingReference,
                        tolerance: configuration.tolerance, message: "Coincident section original edge law is absent.")
                }
                try consumeUse(curve)
                let projected = try DefaultOrthographicEdgeProjector().project(edgeID: coedge.edgeID,
                    in: workingBRep, orientation: coedge.orientation, onto: frame, tolerance: configuration.tolerance)
                try visit(loopID, ordinal, projected)
            }
        }
    }

}

