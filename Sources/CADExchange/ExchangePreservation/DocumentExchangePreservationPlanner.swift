import CADCore
import CADIR
import CADKernel

/// Computes source-domain losses before invoking an actual format producer.
struct DocumentExchangePreservationPlanner {
    func usesIndependentIGESProducer(for document: CADDocument) -> Bool {
        document.independentShapes != nil && document.designGraph.nodes.isEmpty && document.assembly == nil
    }
    func report(for document: CADDocument, as format: ExchangeFileFormat) -> ExchangePreservationReport {
        guard format != .swiftCAD else { return .init() }
        var domains = Set<ExchangeInformationDomain>()
        let exact = format == .step || format == .iges
        if !exact, !document.designGraph.nodes.isEmpty { domains.formUnion([.geometry, .topology]) }
        if document.assembly != nil, format != .step { domains.insert(.placement) }
        if !document.designGraph.nodes.isEmpty || !document.documentFoundation.attributes.isEmpty { domains.insert(.sourceHistory) }
        if format != .step {
            let attributes = document.productAttributes
            if !attributes.layers.isEmpty { domains.insert(.appearance) }
            for assignment in attributes.assignments {
                switch assignment.value {
                case .name, .color, .opacity: domains.insert(.appearance)
                case .material, .density, .descriptorDensity: domains.insert(.physicalProperties)
                }
            }
            if !attributes.materials.isEmpty || !attributes.itemCharacterizations.isEmpty || !attributes.shapeElementDescriptions.isEmpty { domains.insert(.physicalProperties) }
            if !attributes.manufacturingInformation.isEmpty { domains.insert(.manufacturingInformation) }
            if !attributes.viewMetadata.views.isEmpty { domains.insert(.savedViews) }
            if !attributes.viewMetadata.validationProperties.isEmpty { domains.insert(.validationProperties) }
        }
        // Producer selection determines whether the independent graph itself is retained.
        if document.independentShapes != nil, format != .step,
            !(format == .iges && usesIndependentIGESProducer(for: document)) { domains.insert(.independentShapes) }
        if [.glb, .gltf, .vrml].contains(format), document.units.length != .meter { domains.insert(.units) }
        var losses = domains.sorted { $0.rawValue < $1.rawValue }.map {
            ExchangeInformationLoss(domain: $0, reason: .unrepresentableSource,
                description: "The selected \(format.rawValue) producer cannot retain this authored source domain.")
        }
        if format == .step, let independent = document.independentShapes {
            for group in independent.groups where group.family != .unordered || !group.backPointerMembers.isEmpty {
                losses.append(ExchangeInformationLoss(domain: .independentShapes, reason: .unrepresentableSource,
                    entityName: group.name,
                    description: "STEP set projection of original group \(group.id) loses family \(group.family.rawValue), authored membership order/multiplicity (\(group.members.count) entries), and inverse membership (\(group.backPointerMembers.count) entries)."))
            }
        }
        if format == .iges, usesIndependentIGESProducer(for: document), let independent = document.independentShapes {
            for owner in independent.originalSTEPGroups {
                losses.append(.init(domain: .independentShapes, reason: .unrepresentableSource,
                    entityName: owner.name,
                    description: "IGES cannot retain separate original STEP GROUP declaration \(owner.id), its nullable description or zero-assignment existence."))
            }
            for group in independent.groups {
                if group.description != nil {
                    losses.append(.init(domain: .independentShapes, reason: .unrepresentableSource,
                        entityName: group.name,
                        description: "IGES402 projection of assignment \(group.id) discards its original nullable description."))
                }
                if let owner = group.originalSTEPGroupID {
                    losses.append(.init(domain: .independentShapes, reason: .unrepresentableSource,
                        entityName: group.name,
                        description: "IGES 402 projection of assignment \(group.id) loses its separate original STEP GROUP owner \(owner) and sharing with other assignments."))
                }
            }
            func placementLoss(_ entity: String, _ scope: String, _ count: Int) -> ExchangeInformationLoss {
                .init(domain: .placement, reason: .unrepresentableSource, entityName: entity,
                    description: "IGES exact finite-decimal projection of original \(scope) loses \(count) ordered placement operations and may change shared-frame relationships; it preserves geometric action only when the concrete producer proves finite-decimal representability.")
            }
            for frame in independent.frames {
                if let original = frame.originalIGES, !original.adjustments.isEmpty {
                    losses.append(placementLoss(frame.name, "matrix \(frame.id)", original.adjustments.count))
                }
            }
            for definition in independent.definitions {
                if let original = definition.originalIGES, !original.adjustments.isEmpty {
                    losses.append(placementLoss(original.directoryLabel, "definition \(definition.id)", original.adjustments.count))
                }
            }
            for instance in independent.instances {
                if let original = instance.originalIGES, !original.adjustments.isEmpty {
                    losses.append(placementLoss(instance.name, "instance \(instance.id)", original.adjustments.count))
                }
            }
            for (id, association) in independent.curvePositionFrames where !association.originalIGESAdjustments.isEmpty {
                losses.append(placementLoss("", "curve pose \(id)", association.originalIGESAdjustments.count))
            }
            for (id, association) in independent.surfacePositionFrames where !association.originalIGESAdjustments.isEmpty {
                losses.append(placementLoss("", "surface pose \(id)", association.originalIGESAdjustments.count))
            }
        }
        return ExchangePreservationReport(losses: losses)
    }
    func admit(_ report: ExchangePreservationReport, policy: ExchangeExportPolicy) throws {
        switch policy {
        case .preserveAll: guard report.isComplete else { throw ExchangePreservationError.unacceptedLoss(report) }
        case let .allowLoss(accepting): guard report.lostDomains.isSubset(of: accepting) else { throw ExchangePreservationError.unacceptedLoss(report) }
        }
    }
}
