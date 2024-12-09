//
//  ImageTrackingModel.swift
//  Providers
//
//  Created by marcelodearaujo on 04/12/24.
//


import ARKit
import SwiftUI
import RealityKit
import Observation

@MainActor
class ImageTrackingModel: ObservableObject {

    let session = ARKitSession()
    var contentEntity = Entity()
    var entityMap: [UUID: Entity] = [:]

    let imageTrackingProvider = ImageTrackingProvider(
        referenceImages: ReferenceImage.loadReferenceImages(inGroupNamed: "img")
    )


    func setupContentEntity() -> Entity {
        return contentEntity
    }

    func runSession() async {
        do {
            if ImageTrackingProvider.isSupported {
                try await session.run([imageTrackingProvider])
                
            }
        } catch {
            print(error)
        }
    }

    func processImageTrackingUpdates() async {
        for await update in imageTrackingProvider.anchorUpdates {
            updateImage(update.anchor)

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

    func updateImage(_ anchor: ImageAnchor) {
        if entityMap[anchor.id] == nil {
            let entity = ModelEntity(mesh: .generateSphere(radius: 0.05))
            let material = UnlitMaterial(color: UIColor.blue.withAlphaComponent(0.65))
            entity.model?.materials = [material]
            entityMap[anchor.id] = entity
            contentEntity.addChild(entity)
        }

        if anchor.isTracked {
            entityMap[anchor.id]?.transform = Transform(matrix: anchor.originFromAnchorTransform)
        }
    }
}
