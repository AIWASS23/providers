//
//  OuterSpaceCeilingPortalView.swift
//  Providers
//
//  Created by marcelodearaujo on 11/12/24.
//


import SwiftUI
import RealityKit

struct ImmersivePortalView: View {
    @EnvironmentObject var portal: PortalModel
    
    var body: some View {
        RealityView { content in
            portal.portalWorld.components.set(WorldComponent())
            content.add(portal.portalWorld)
            
            Task {
                do {
                    let cgImage = try await portal.loadImageFromAssets(named: "skybox")
                    let texture = try await TextureResource(image: cgImage, options: .init(semantic: nil))
                    let entity = Entity()
                    let meshResource = MeshResource.generateSphere(radius: portal.skyboxRadius)
                    var material = PhysicallyBasedMaterial()
                    material.baseColor.texture = .init(texture)
                    let modelComponent = ModelComponent(mesh: meshResource, materials: [material])
                    entity.components.set(modelComponent)
                    entity.scale *= .init(x: -1, y: 1, z: 1)
                    entity.transform.translation += SIMD3<Float>(0.0, 2.0, 0.0)
                    portal.portalWorld.addChild(entity)
                    
                } catch {
                    print(error)
                }
            }
        } update: { content in
            if let portalEntity = portal.portalEntity {
                if !content.entities.contains(portalEntity) {
                    content.add(portalEntity)
                }
                portalEntity.scale = .one * portal.portalScale
            }
        }
        .task {
            do {
                try await portal.startARSession()
            } catch {
                print("Error running AR session: \(error)")
            }
        }
        .onDisappear {
            portal.stopARSession()
        }
    }
}

#Preview {
    ImmersivePortalView()
}
