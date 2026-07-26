import CADCore
import CADIR
import CADKernel

public struct DocumentEditor: DocumentEditing {
    private let capabilityCatalog: KernelCapabilityCatalog

    public init(capabilityCatalog: KernelCapabilityCatalog = KernelCapabilities.current) {
        self.capabilityCatalog = capabilityCatalog
    }

    public func apply(
        _ command: CADCommand,
        to document: CADDocument,
        tolerance: ModelingTolerance
    ) throws -> CADDocument {
        try capabilityCatalog.validate()
        try validate(document, tolerance: tolerance)
        var updatedDocument = document

        switch command {
        case let .appendFeature(request):
            try request.validate()
            do {
                _ = try capabilityCatalog.requireExecutable(
                    operation: request.operation.capabilityOperation
                )
            } catch {
                throw KernelError.wrapping(
                    error,
                    phase: .validation,
                    featureID: request.id,
                    tolerance: tolerance
                )
            }
            let featureNode: FeatureNode
            do {
                featureNode = try FeatureNodeFactory.make(
                    operation: request.operation,
                    id: request.id,
                    name: request.name,
                    in: updatedDocument,
                    tolerance: tolerance
                )
            } catch {
                throw KernelError.wrapping(
                    error,
                    phase: .validation,
                    featureID: request.id,
                    tolerance: tolerance
                )
            }
            guard updatedDocument.designGraph.nodes[featureNode.id] == nil else {
                throw KernelError(
                    phase: .validation,
                    code: .invalidInput,
                    featureID: featureNode.id,
                    tolerance: tolerance,
                    message: "A feature with the requested ID already exists."
                )
            }
            append(featureNode, to: &updatedDocument)
        case let .replaceFeature(request):
            try request.validate()
            guard let existingFeature = updatedDocument.designGraph.nodes[request.id] else {
                throw KernelError(
                    phase: .validation,
                    code: .missingReference,
                    featureID: request.id,
                    tolerance: tolerance,
                    message: "The feature to replace was not found."
                )
            }
            do {
                _ = try capabilityCatalog.requireExecutable(
                    operation: request.operation.capabilityOperation
                )
            } catch {
                throw KernelError.wrapping(
                    error,
                    phase: .validation,
                    featureID: request.id,
                    tolerance: tolerance
                )
            }
            var replacement: FeatureNode
            do {
                replacement = try FeatureNodeFactory.make(
                    operation: request.operation,
                    id: request.id,
                    name: request.name,
                    in: updatedDocument,
                    tolerance: tolerance
                )
            } catch {
                throw KernelError.wrapping(
                    error,
                    phase: .validation,
                    featureID: request.id,
                    tolerance: tolerance
                )
            }
            replacement.isSuppressed = existingFeature.isSuppressed
            do {
                _ = try updatedDocument.replaceFeature(replacement, tolerance: tolerance)
            } catch {
                throw KernelError.wrapping(
                    error,
                    phase: .validation,
                    featureID: request.id,
                    tolerance: tolerance
                )
            }
        case let .upsertParameter(parameter):
            updatedDocument.parameters.parameters[parameter.id] = parameter
            updatedDocument.parameters.revision = updatedDocument.parameters.revision.advanced()
        case let .addSelectionDimension(dimension):
            _ = try updatedDocument.addSelectionDimension(dimension, tolerance: tolerance)
        case let .suppressFeature(featureID, suppressed):
            guard var feature = updatedDocument.designGraph.nodes[featureID] else {
                throw KernelError(
                    phase: .validation,
                    code: .missingReference,
                    featureID: featureID,
                    tolerance: tolerance,
                    message: "The feature to suppress was not found."
                )
            }
            feature.isSuppressed = suppressed
            updatedDocument.designGraph.nodes[featureID] = feature
            updatedDocument.designGraph.revision = updatedDocument.designGraph.revision.advanced()
        case let .removeFeature(featureID):
            try remove(featureID, from: &updatedDocument, tolerance: tolerance)
        }

        try validate(updatedDocument, tolerance: tolerance)
        return updatedDocument
    }

    private func validate(_ document: CADDocument, tolerance: ModelingTolerance) throws {
        do {
            try document.validate(tolerance: tolerance)
        } catch {
            throw KernelError.wrapping(error, phase: .validation, tolerance: tolerance)
        }
    }

    private func append(_ feature: FeatureNode, to document: inout CADDocument) {
        document.designGraph.nodes[feature.id] = feature
        document.designGraph.order.append(feature.id)
        let sourceIDs = Set(feature.inputs.map(\.featureID))
        document.designGraph.dependencies.append(contentsOf: sourceIDs
            .sorted(by: { $0.description < $1.description })
            .map { DependencyEdge(source: $0, target: feature.id) })
        document.designGraph.revision = document.designGraph.revision.advanced()
    }

    private func remove(
        _ featureID: FeatureID,
        from document: inout CADDocument,
        tolerance: ModelingTolerance
    ) throws {
        guard document.designGraph.nodes[featureID] != nil else {
            throw KernelError(
                phase: .validation,
                code: .missingReference,
                featureID: featureID,
                tolerance: tolerance,
                message: "The feature to remove was not found."
            )
        }
        guard document.designGraph.dependencies.contains(where: { $0.source == featureID }) == false else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                featureID: featureID,
                tolerance: tolerance,
                message: "A feature with downstream dependents cannot be removed."
            )
        }
        document.designGraph.nodes.removeValue(forKey: featureID)
        document.designGraph.order.removeAll { $0 == featureID }
        document.designGraph.dependencies.removeAll {
            $0.source == featureID || $0.target == featureID
        }
        document.designGraph.revision = document.designGraph.revision.advanced()
    }
}
