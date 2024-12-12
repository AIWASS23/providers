//
//  BreathingLeavesView.swift
//  Providers
//
//  Created by marcelodearaujo on 06/12/24.
//


import RealityKit
import SwiftUI

struct BreathingLeavesView: View {
    let rootEntity = Entity()
    @State var children = [EntityPositionPair]()
    @State private var rotationAngles: SIMD3<Float> = [0, 0, 0]
    @State private var modulationTimer: Timer?
    @State private var time: Double = 0.0
    @State private var lastRotationUpdateTime = CACurrentMediaTime()
    
    var body: some View {
        GeometryReader3D { proxy in
            RealityView { content in
                let size = content.convert(proxy.frame(in: .local), from: .local, to: .scene).extents
                children = try! EntityPositionPair.getFibonacciLattice(boundingBox: size).shuffled()
                content.add(rootEntity)
                for child in children {
                    child.entity.look(at: .zero, from: child.entity.position, relativeTo: nil)
                    rootEntity.addChild(child.entity)
                }
                startModulationTimer()
            }
        }
        .onDisappear {
            stopTimer()
        }
    }
    
    private func startModulationTimer() {
        modulationTimer = Timer.scheduledTimer(withTimeInterval: 1/120.0, repeats: true) { _ in
            let currentTime = CACurrentMediaTime()
            let frameDuration = currentTime - lastRotationUpdateTime
            self.time += frameDuration
            let scale = 1.0 + 0.45 * -cos(Float(self.time * 2 * .pi / 7.0))
            
            var rotationSpeed: Float = 0.4
            for child in self.children {
                // Scale position for breathing effect
                child.entity.position = child.initialPosition * scale
                
                // Rotate normal to the center for individual spin
                rotationSpeed = 0.1
                let rotationSpeed: Float = rotationSpeed * scale * 0.5
                let rotationAngle = Float(self.time) * rotationSpeed
                let rotationAxis = normalize(cross(child.initialPosition, [1, 0, 0]))
                let rotationQuat = simd_quatf(angle: rotationAngle, axis: rotationAxis)
                
                child.entity.transform.rotation = rotationQuat
            }
            
            rotationAngles.x += Float(frameDuration * 0.25)
            rotationAngles.y += Float(frameDuration * 0.15)
            rotationAngles.z += Float(frameDuration * 0.1)
            
            let rotationX = simd_quatf(angle: rotationAngles.x, axis: [1, 0, 0])
            let rotationY = simd_quatf(angle: rotationAngles.y, axis: [0, 1, 0])
            let rotationZ = simd_quatf(angle: rotationAngles.z, axis: [0, 0, 1])
            rootEntity.transform.rotation = rotationX * rotationY * rotationZ
            
            lastRotationUpdateTime = currentTime
        }
    }
    
    private func stopTimer() {
        modulationTimer?.invalidate()
        modulationTimer = nil
    }
}

#Preview {
    BreathingLeavesView()
}

struct EntityPositionPair {
    let entity: Entity
    let initialPosition: SIMD3<Float>
}

extension EntityPositionPair {
    static func getFibonacciLattice(entityCount: Int = 60, boundingBox: SIMD3<Float>) throws -> [EntityPositionPair] {
        
        let radius = boundingBox.z*0.45
        
        var entities = [EntityPositionPair]()
        for i in 0..<entityCount {
            let theta = acos(1 - 2 * Float(i + 1) / Float(entityCount + 1))
            let phi = Float(i) * .pi * (1 + sqrt(5))
            
            let x = radius * sin(theta) * cos(phi)
            let y = radius * sin(theta) * sin(phi)
            let z = radius * cos(theta)
            let position = SIMD3<Float>(x, y, z)
            
            let entity = try Entity.pedalEntity(boundingBox: boundingBox)
            entity.position = position
            
            let sphereInfo = EntityPositionPair(entity: entity, initialPosition: position)
            entities.append(sphereInfo)
        }
        return entities
    }
}

extension Entity {
    static func pedalEntity(boundingBox: SIMD3<Float>) throws -> Entity {
        let leafHeight = boundingBox.y * 0.1
        
        let lowLevelMesh = try leafMesh(height: leafHeight)
        let resource = try MeshResource(from: lowLevelMesh)
        
        var material = PhysicallyBasedMaterial()
        material.baseColor.tint = .red
        material.blending = .transparent(opacity: 0.75)
        material.emissiveIntensity = 2.0
        material.opacityThreshold = 0.1
        material.metallic = 0.0
        material.roughness = 0.375
        material.faceCulling = .none
        material.clearcoat = .init(floatLiteral: 0.5)
        material.clearcoatRoughness = .init(floatLiteral: 1.0)
        
        if let cgImage = createRandomRedShadeNoiseImage(width: 50, height: 10),
           let texture = try? TextureResource(image: cgImage, options: .init(semantic: nil)) {
            material.emissiveColor = .init(texture: .init(texture))
        }

        let modelComponent = ModelComponent(mesh: resource, materials: [material])

        let entity = Entity()
        entity.name = "Leaf"
        entity.components.set(modelComponent)
        entity.scale.z = boundingBox.y * 0.1
        return entity
    }
    
    static func leafMesh(height: Float = 1.0) throws -> LowLevelMesh {
        let widthSegments = 3
        let heightSegments = 12
        let width = height * 0.5
        let depth: Float = 0.05
        
        let vertexCount = (widthSegments + 1) * (heightSegments + 1) * 2 + (heightSegments + 1) * 4
        let indexCount = widthSegments * heightSegments * 12 + heightSegments * 12
        
        var desc = Vertex.descriptor
        desc.vertexCapacity = vertexCount
        desc.indexCapacity = indexCount
        
        let mesh = try LowLevelMesh(descriptor: desc)
        
        mesh.withUnsafeMutableBytes(bufferIndex: 0) { rawBytes in
                let vertices = rawBytes.bindMemory(to: Vertex.self)
                var vertexIndex = 0
                
                // Function to calculate leaf shape
                func leafShape(_ v: Float, _ u: Float) -> SIMD3<Float> {
                    let y = v * height - height / 2
                    
                    // Adjust curve for rounded ends and asymmetry
                    let baseCurve = sin(v * .pi)
                    let topAdjust = pow(1 - v, 2) * 0.3 // Makes top end larger
                    let bottomAdjust = pow(v, 2) * 0.9 // Makes bottom end smaller
                    let curve = baseCurve * (1 - topAdjust - bottomAdjust)
                    
                    let leafWidth = curve * width
                    let x = (u - 0.5) * leafWidth
                    
                    // Adjust z-curve for more pronounced curvature
                    let zCurve = sin(v * .pi) * 0.15
                    
                    return SIMD3<Float>(x, y, zCurve)
                }
                
                // Create top and bottom surfaces
                for surface in 0...1 {
                    for i in 0...heightSegments {
                        let v = Float(i) / Float(heightSegments)
                        for j in 0...widthSegments {
                            let u = Float(j) / Float(widthSegments)
                            var position = leafShape(v, u)
                            position.z += surface == 0 ? depth / 2 : -depth / 2
                            vertices[vertexIndex] = Vertex(position: position)
                            vertexIndex += 1
                        }
                    }
                }
                
                // Create side vertices
                for i in 0...heightSegments {
                    let v = Float(i) / Float(heightSegments)
                    let leftPosition = leafShape(v, 0)
                    let rightPosition = leafShape(v, 1)
                    
                    // Left side
                    vertices[vertexIndex] = Vertex(position: leftPosition + SIMD3<Float>(0, 0, depth / 2))
                    vertexIndex += 1
                    vertices[vertexIndex] = Vertex(position: leftPosition + SIMD3<Float>(0, 0, -depth / 2))
                    vertexIndex += 1
                    
                    // Right side
                    vertices[vertexIndex] = Vertex(position: rightPosition + SIMD3<Float>(0, 0, depth / 2))
                    vertexIndex += 1
                    vertices[vertexIndex] = Vertex(position: rightPosition + SIMD3<Float>(0, 0, -depth / 2))
                    vertexIndex += 1
                }
            }
        
        mesh.withUnsafeMutableIndices { rawIndices in
            let indices = rawIndices.bindMemory(to: UInt32.self)
            var index = 0
            
            let vertsPerSurface = (widthSegments + 1) * (heightSegments + 1)
            
            // Top and bottom surfaces
            for surface in 0...1 {
                let surfaceOffset = surface * vertsPerSurface
                for i in 0..<heightSegments {
                    for j in 0..<widthSegments {
                        let a = surfaceOffset + i * (widthSegments + 1) + j
                        let b = a + 1
                        let c = surfaceOffset + (i + 1) * (widthSegments + 1) + j
                        let d = c + 1
                        
                        if surface == 0 {
                            indices[index] = UInt32(a)
                            indices[index + 1] = UInt32(c)
                            indices[index + 2] = UInt32(b)
                            indices[index + 3] = UInt32(c)
                            indices[index + 4] = UInt32(d)
                            indices[index + 5] = UInt32(b)
                        } else {
                            indices[index] = UInt32(a)
                            indices[index + 1] = UInt32(b)
                            indices[index + 2] = UInt32(c)
                            indices[index + 3] = UInt32(c)
                            indices[index + 4] = UInt32(b)
                            indices[index + 5] = UInt32(d)
                        }
                        index += 6
                    }
                }
            }
            
            // Side faces
            let sideVertexStart = vertsPerSurface * 2
            for i in 0..<heightSegments {
                let a = sideVertexStart + i * 4
                let b = a + 1
                let c = a + 4
                let d = c + 1
                
                // Left side
                indices[index] = UInt32(a)
                indices[index + 1] = UInt32(c)
                indices[index + 2] = UInt32(b)
                indices[index + 3] = UInt32(b)
                indices[index + 4] = UInt32(c)
                indices[index + 5] = UInt32(d)
                
                // Right side
                indices[index + 6] = UInt32(a + 2)
                indices[index + 7] = UInt32(b + 2)
                indices[index + 8] = UInt32(c + 2)
                indices[index + 9] = UInt32(b + 2)
                indices[index + 10] = UInt32(d + 2)
                indices[index + 11] = UInt32(c + 2)
                
                index += 12
            }
        }
        
        let meshBounds = BoundingBox(min: [-width/2, -height/2, -depth/2], max: [width/2, height/2, depth/2])
        mesh.parts.replaceAll([
            LowLevelMesh.Part(
                indexCount: indexCount,
                topology: .triangle,
                bounds: meshBounds
            )
        ])

        return mesh
    }
    
   static func createRandomRedShadeNoiseImage(width: Int, height: Int) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 4 * width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        guard let data = context.data else { return nil }
        let pixelBuffer = data.bindMemory(to: UInt32.self, capacity: width * height)
        
        for y in 0..<height {
            for x in 0..<width {
                let red = UInt32(CGFloat.random(in: 0.5...1) * 255)
                let green = UInt32(CGFloat.random(in: 0...0.5) * 255)
                let blue = UInt32(CGFloat.random(in: 0...0.375) * 255)
                let alpha: UInt32 = 255
                let color = (alpha << 24) | (blue << 16) | (green << 8) | red
                pixelBuffer[y * width + x] = color
            }
        }

        return context.makeImage()
    }
}

fileprivate struct Vertex {
    var position: SIMD3<Float> = .zero
    
    static var vertexAttributes: [LowLevelMesh.Attribute] = [
        .init(semantic: .position, format: .float3, offset: MemoryLayout<Self>.offset(of: \.position)!),
    ]


    static var vertexLayouts: [LowLevelMesh.Layout] = [
        .init(bufferIndex: 0, bufferStride: MemoryLayout<Self>.stride)
    ]


    static var descriptor: LowLevelMesh.Descriptor {
        var desc = LowLevelMesh.Descriptor()
        desc.vertexAttributes = Vertex.vertexAttributes
        desc.vertexLayouts = Vertex.vertexLayouts
        desc.indexType = .uint32
        return desc
    }
}
