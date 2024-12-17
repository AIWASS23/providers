//
//  TileFloorRealityView.swift
//  Providers
//
//  Created by marcelodearaujo on 06/12/24.
//


import SwiftUI
import RealityKit

// Volume example
struct TileFloorRealityView: View {
    let gridSize = 8
    
    var body: some View {
        GeometryReader3D { proxy in
            RealityView { content in
                let size = content.convert(proxy.frame(in: .local), from: .local, to: .scene).extents
                let tileSize = Float(min(size.x, size.y)) / Float(gridSize)
                let mesh = MeshResource.generatePlane(width: tileSize, height: tileSize)
                let textureResource = try! await loadTileTextureResource()
                let material = UnlitMaterial(texture: textureResource)
                for row in 0..<gridSize {
                    for column in 0..<gridSize {
                        let modelEntity = ModelEntity(mesh: mesh, materials: [material])
                        let x = Float(column) * tileSize - Float(gridSize - 1) * tileSize / 2
                        let y = Float(row) * tileSize - Float(gridSize - 1) * tileSize / 2
                        modelEntity.transform.translation = .init(x: x, y: y, z: 0)
                        content.add(modelEntity)
                    }
                }
            }
        }
    }
}

// Immersive space example
struct TileFloorImmersiveRealityView: View {
    let gridSize: Int = 16
    let tileSize: Float  = 1.0
    
    var body: some View {
        RealityView { content in
            let mesh = MeshResource.generatePlane(width: tileSize, height: tileSize)
            let textureResource = try! await loadTileTextureResource()
            let material = UnlitMaterial(texture: textureResource)
            for row in 0..<gridSize {
                for column in 0..<gridSize {
                    let modelEntity = ModelEntity(mesh: mesh, materials: [material])
                    let x = Float(column) * tileSize - Float(gridSize - 1) * tileSize / 2
                    let z = Float(row) * tileSize - Float(gridSize - 1) * tileSize / 2
                    modelEntity.transform.translation = .init(x: x, y: 0, z: z)
                    modelEntity.transform.rotation = .init(angle: -.pi*0.5, axis: [1,0,0])
                    content.add(modelEntity)
                }
            }
        }
    }
}

fileprivate func loadTileTextureResource(url: URL = URL(string: "https://matt54.github.io/Resources/floor_tile_1.png")!) async throws -> TextureResource {
    let (data, _) = try await URLSession.shared.data(from: url)
    let image = UIImage(data: data)!
    let cgImage = image.cgImage!
    return try await TextureResource(image: cgImage, options: .init(semantic: nil))
}

#Preview {
    TileFloorRealityView()
}