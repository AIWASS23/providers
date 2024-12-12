//
//  ARKitModel.swift
//  Providers
//
//  Created by marcelodearaujo on 11/12/24.
//


import ARKit
import SwiftUI
import RealityKit
import Observation

class SceneReconstructionModel: ObservableObject {
    
    let session = ARKitSession()
    let sceneReconstruction = SceneReconstructionProvider(modes: [.classification])
    let rootEntity = Entity()
    var meshEntities = [UUID: ModelEntity]()

    func run() async {
        guard SceneReconstructionProvider.isSupported else {
            print("SceneReconstructionProvider is NOT supported.")
            return
        }

        do {
            try await session.run([sceneReconstruction])
            print("ARKit session is running...")
            for await update in sceneReconstruction.anchorUpdates {
                print("update: \(update)")
                print("Updated a portion of the scene: ", update.anchor)
                await processMeshAnchorUpdate(update)
            }
        } catch {
            print("ARKit session error \(error)")
        }
    }

    @MainActor
    func processMeshAnchorUpdate(_ update: AnchorUpdate<MeshAnchor>) async {
        let meshAnchor = update.anchor

        guard let shape = try? await ShapeResource.generateStaticMesh(from: meshAnchor) else { return }
        switch update.event {
        case .added:
            let entity = try! await generateModelEntity(geometry: meshAnchor.geometry)

            entity.transform = Transform(matrix: meshAnchor.originFromAnchorTransform)
            entity.collision = CollisionComponent(shapes: [shape], isStatic: true)
            entity.components.set(InputTargetComponent())

            entity.physicsBody = PhysicsBodyComponent(mode: .static)

            meshEntities[meshAnchor.id] = entity
            rootEntity.addChild(entity)
            
        case .updated:
            guard let entity = meshEntities[meshAnchor.id] else { return }
            entity.transform = Transform(matrix: meshAnchor.originFromAnchorTransform)
            entity.collision?.shapes = [shape]
            
        case .removed:
            meshEntities[meshAnchor.id]?.removeFromParent()
            meshEntities.removeValue(forKey: meshAnchor.id)
        }
    }


    @MainActor
    func generateModelEntity(geometry: MeshAnchor.Geometry) async throws -> ModelEntity {
        var desc = MeshDescriptor()
        let posValues = geometry.vertices.asSIMD3(ofType: Float.self)
        desc.positions = .init(posValues)
        let normalValues = geometry.normals.asSIMD3(ofType: Float.self)
        desc.normals = .init(normalValues)
        do {
            desc.primitives = .polygons(
                (0..<geometry.faces.count).map { _ in UInt8(3) },
                (0..<geometry.faces.count * 3).map {
                    geometry.faces.buffer.contents()
                        .advanced(by: $0 * geometry.faces.bytesPerIndex)
                        .assumingMemoryBound(to: UInt32.self).pointee
                }
            )
        }
        let meshResource = try MeshResource.generate(from: [desc])
        let material = SimpleMaterial(color: .blue.withAlphaComponent(0.7), isMetallic: false)
        let modelEntity = ModelEntity(mesh: meshResource, materials: [material])
        return modelEntity
    }
}
