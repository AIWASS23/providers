//
//  PlaneDetectionModel.swift
//  Providers
//
//  Created by marcelodearaujo on 04/12/24.
//


import ARKit
import SwiftUI
import RealityKit
import Observation

@MainActor
class PlaneDetectionModel: ObservableObject {

    let session = ARKitSession()
    let planeDetectionProvider = PlaneDetectionProvider(alignments: [.horizontal, .vertical])

    var contentEntity = Entity()
    var entityMap: [UUID: Entity] = [:]


    func setupContentEntity() -> Entity {
        return contentEntity
    }

    func runSession() async {
        guard PlaneDetectionProvider.isSupported else {
            print("PlaneDetectionProvider is NOT supported.")
            return
        }

        do {
            try await session.run([planeDetectionProvider])
        } catch {
            print(error)
        }
    }

    func processPlaneDetectionUpdates() async {

        for await update in planeDetectionProvider.anchorUpdates {
            let planeAnchor = update.anchor
            if planeAnchor.classification == .window { continue }

            switch update.event {
            case .added, .updated:
                updatePlane(planeAnchor)
            case .removed:
                removePlane(planeAnchor)
            }
        }
    }

    func monitorSessionEvents() async {
        for await event in session.events {
            switch event {
            case .authorizationChanged(type: _, status: let status):
                print("Authorization changed to: \(status)")
                if status == .denied {
                    print("Authorization status: denied")
                }
            case .dataProviderStateChanged(dataProviders: let providers, newState: let state, error: let error):
                print("Data provider changed: \(providers), \(state)")
                if let error {
                    print("Data provider reached an error state: \(error)")
                }
            @unknown default:
                fatalError("Unhandled new event type \(event)")
            }
        }
    }

    func updatePlane(_ anchor: PlaneAnchor) {

        if let entity = entityMap[anchor.id] {
            let planeEntity = entity.findEntity(named: "plane") as! ModelEntity
            planeEntity.model!.mesh = MeshResource.generatePlane(width: anchor.geometry.extent.width, height: anchor.geometry.extent.height)
            planeEntity.transform = Transform(matrix: anchor.geometry.extent.anchorFromExtentTransform)
        } else {
            let entity = Entity()

            let material = UnlitMaterial(color: anchor.classification.color)
            let planeEntity = ModelEntity(mesh: .generatePlane(width: anchor.geometry.extent.width, height: anchor.geometry.extent.height), materials: [material])
            planeEntity.name = "plane"
            planeEntity.transform = Transform(matrix: anchor.geometry.extent.anchorFromExtentTransform)
            entity.addChild(planeEntity)

            entityMap[anchor.id] = entity
            contentEntity.addChild(entity)
        }
        entityMap[anchor.id]?.transform = Transform(matrix: anchor.originFromAnchorTransform)
    }

    func removePlane(_ anchor: PlaneAnchor) {
        entityMap[anchor.id]?.removeFromParent()
        entityMap.removeValue(forKey: anchor.id)
    }
}

extension PlaneAnchor.Classification {

    var color: UIColor {
        switch self {
        case .wall:
            return UIColor.blue.withAlphaComponent(0.65)
        case .floor:
            return UIColor.red.withAlphaComponent(0.65)
        case .ceiling:
            return UIColor.green.withAlphaComponent(0.65)
        case .table:
            return UIColor.yellow.withAlphaComponent(0.65)
        case .door:
            return UIColor.brown.withAlphaComponent(0.65)
        case .seat:
            return UIColor.systemPink.withAlphaComponent(0.65)
        case .window:
            return UIColor.orange.withAlphaComponent(0.65)
        case .undetermined:
            return UIColor.lightGray.withAlphaComponent(0.65)
        case .notAvailable:
            return UIColor.gray.withAlphaComponent(0.65)
        case .unknown:
            return UIColor.black.withAlphaComponent(0.65)
        @unknown default:
            return UIColor.purple
        }
    }
}
