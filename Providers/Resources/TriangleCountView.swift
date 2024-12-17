//
//  TriangleCountView.swift
//  Providers
//
//  Created by marcelodearaujo on 06/12/24.
//


import RealityKit
import SwiftUI

struct TriangleCountView: View {
    let generateSphereEntity = createEntity(resource: .generateSphere(radius: 0.5), material: getMaterial())
    let generateSpecificSphereEntity = try! createEntity(resource: .generateSpecificSphere(radius: 0.5, latitudeBands: 15, longitudeBands: 15), material: getMaterial())
    @State var numberOfLatitudeBands: Int = 15
    @State var numberOfLongitudeBands: Int = 15
    @State var sphereRadius: Float = 0.5
    
    var body: some View {
        VStack {
            HStack {
                
                VStack {
                    Text("MeshResource.generateSphere")
                    Text("Triangle Count: \(generateSphereEntity.triangleCount)")
                        .padding(.bottom, 125)
                    
                    Text("Custom LowLevelMesh Sphere")
                    Text("Triangle Count: \(generateSpecificSphereEntity.triangleCount)")
                }
                
                RealityView { content in
                    generateSphereEntity.transform.translation.y = 0.06
                    generateSpecificSphereEntity.transform.translation.y = -0.06
                    
                    content.add(generateSphereEntity)
                    content.add(generateSpecificSphereEntity)
                } update: { content in
                    let modelComponent = try! ModelComponent(mesh: .generateSpecificSphere(radius: sphereRadius, latitudeBands: numberOfLatitudeBands, longitudeBands: numberOfLongitudeBands), materials: [TriangleCountView.getMaterial()])
                    generateSpecificSphereEntity.components.set(modelComponent)
                    
                    let modelComponent2 = ModelComponent(mesh: .generateSphere(radius: sphereRadius), materials: [TriangleCountView.getMaterial()])
                    generateSphereEntity.components.set(modelComponent2)
                }
                .frame(width: 200)
            }
            
            HStack {
                Text("Latitude Band Count: \(numberOfLatitudeBands)")
                    .frame(width: 225)
                Slider(value: Binding(
                    get: {
                        Double(self.numberOfLatitudeBands)
                    },
                    set: { newValue in
                        self.numberOfLatitudeBands = Int(newValue)
                    }
                ), in: 2...160, step: 1)
                
            }
            
            HStack {
                Text("Longitude Band Count: \(numberOfLongitudeBands)")
                    .frame(width: 225)
                Slider(value: Binding(
                    get: {
                        Double(self.numberOfLongitudeBands)
                    },
                    set: { newValue in
                        self.numberOfLongitudeBands = Int(newValue)
                    }
                ), in: 5...40, step: 1)
                
            }
            
            HStack {
                Text(String(format: "Sphere Radius: %.2f", sphereRadius))
                    .frame(width: 225)
                Slider(value: Binding(
                    get: {
                        Double(self.sphereRadius)
                    },
                    set: { newValue in
                        self.sphereRadius = Float(newValue)
                    }
                ), in: 0.05...0.5)
                
            }
        }
        .padding()
        .frame(width: 600, height: 500, alignment: .center)
        .background(Color.purple.opacity(0.5))
    }
    
    static func createEntity(resource: MeshResource, material: RealityFoundation.Material) -> Entity {
        let modelComponent = ModelComponent(mesh: resource, materials: [material])
        let entity = Entity()
        entity.components.set(modelComponent)
        entity.scale *= 0.1
        entity.transform.translation.z = -0.2
        return entity
    }
    
    static func getMaterial() -> RealityFoundation.Material {
        var material = UnlitMaterial()
        material.color.tint = .init(red: 1.0, green: 1.0, blue: 0.5, alpha: 1.0)
        material.faceCulling = .none
        return material
    }
}

#Preview {
    TriangleCountView()
}

extension Entity {
    var triangleCount: Int {
        meshResource?.triangleCount ?? 0
    }
    
    var meshResource: MeshResource? {
        components[ModelComponent.self]?.mesh ?? nil
    }
}

extension MeshResource {
    var triangleCount: Int {
        for model in contents.models {
            for part in model.parts {
                if let triangleIndices = part.triangleIndices {
                    let indices = triangleIndices.elements
                    let indexCount = indices.count
                    let polygonCount = indexCount / 3
                    return polygonCount
                }
            }
        }
        return 0
    }
}

struct MyVertex {
    var position: SIMD3<Float> = .zero
    var color: UInt32 = .zero
    
    static var vertexAttributes: [LowLevelMesh.Attribute] = [
        .init(semantic: .position, format: .float3, offset: MemoryLayout<Self>.offset(of: \.position)!),
        .init(semantic: .color, format: .uchar4Normalized_bgra, offset: MemoryLayout<Self>.offset(of: \.color)!)
    ]


    static var vertexLayouts: [LowLevelMesh.Layout] = [
        .init(bufferIndex: 0, bufferStride: MemoryLayout<Self>.stride)
    ]


    static var descriptor: LowLevelMesh.Descriptor {
        var desc = LowLevelMesh.Descriptor()
        desc.vertexAttributes = MyVertex.vertexAttributes
        desc.vertexLayouts = MyVertex.vertexLayouts
        desc.indexType = .uint32
        return desc
    }
}

extension MeshResource {
    static func generateSpecificSphere(radius: Float, latitudeBands: Int = 10, longitudeBands: Int = 10) throws -> MeshResource {
        let vertexCount = (latitudeBands + 1) * (longitudeBands + 1)
        let indexCount = latitudeBands * longitudeBands * 6
        
        var desc = MyVertex.descriptor
        desc.vertexCapacity = vertexCount
        desc.indexCapacity = indexCount
        
        let mesh = try LowLevelMesh(descriptor: desc)
        
        mesh.withUnsafeMutableBytes(bufferIndex: 0) { rawBytes in
            let vertices = rawBytes.bindMemory(to: MyVertex.self)
            var vertexIndex = 0
            
            for latNumber in 0...latitudeBands {
                let theta = Float(latNumber) * Float.pi / Float(latitudeBands)
                let sinTheta = sin(theta)
                let cosTheta = cos(theta)
                
                for longNumber in 0...longitudeBands {
                    let phi = Float(longNumber) * 2 * Float.pi / Float(longitudeBands)
                    let sinPhi = sin(phi)
                    let cosPhi = cos(phi)
                    
                    let x = cosPhi * sinTheta
                    let y = cosTheta
                    let z = sinPhi * sinTheta
                    let position = SIMD3<Float>(x, y, z) * radius
                    let color = 0xFFFFFFFF
                    vertices[vertexIndex] = MyVertex(position: position, color: UInt32(color))
                    vertexIndex += 1
                }
            }
        }
        
        mesh.withUnsafeMutableIndices { rawIndices in
            let indices = rawIndices.bindMemory(to: UInt32.self)
            var index = 0
            
            for latNumber in 0..<latitudeBands {
                for longNumber in 0..<longitudeBands {
                    let first = (latNumber * (longitudeBands + 1)) + longNumber
                    let second = first + longitudeBands + 1
                    
                    indices[index] = UInt32(first)
                    indices[index + 1] = UInt32(second)
                    indices[index + 2] = UInt32(first + 1)
                    
                    indices[index + 3] = UInt32(second)
                    indices[index + 4] = UInt32(second + 1)
                    indices[index + 5] = UInt32(first + 1)
                    
                    index += 6
                }
            }
        }
        
        let meshBounds = BoundingBox(min: [-radius, -radius, -radius], max: [radius, radius, radius])
        mesh.parts.replaceAll([
            LowLevelMesh.Part(
                indexCount: indexCount,
                topology: .triangle,
                bounds: meshBounds
            )
        ])
        
        // Print the number of triangles
        let triangleCount = indexCount / 3
        print("Number of triangles: \(triangleCount)")
        
        return try MeshResource(from: mesh)
    }
}