//
//  Extension.swift
//  Providers
//
//  Created by marcelodearaujo on 09/12/24.
//

import Foundation
import SwiftUI
import RealityKit
import Accelerate
import ARKit

extension Encodable {
    func toJson(encoding: String.Encoding = .utf8) -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: encoding)
    }
}


extension simd_float4x4: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        let cols = try container.decode([SIMD4<Float>].self)
        self.init(columns: (cols[0], cols[1], cols[2], cols[3]))
    }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode([columns.0, columns.1, columns.2, columns.3])
    }
}


extension Entity {
    
    var modelComponent: ModelComponent? {
        get { components[ModelComponent.self] }
        set { components[ModelComponent.self] = newValue }
    }
    var descendentsWithModelComponent: [Entity] {
        var descendents = [Entity]()
        
        for child in children {
            if child.components[ModelComponent.self] != nil {
                descendents.append(child)
            }
            descendents.append(contentsOf: child.descendentsWithModelComponent)
        }
        return descendents
    }
    
    var forward: SIMD3<Float> {
        forward(relativeTo: nil)
    }
    
    
    var visualExtents: SIMD3<Float> {
        get {
            let boundingBox = self.visualBounds(relativeTo: self)
            return boundingBox.extents
        }
    }
    
    subscript(parentMatching targetName: String) -> Entity? {
        if name.contains(targetName) {
            return self
        }
        
        guard let nextParent = parent else {
            return nil
        }
        
        return nextParent[parentMatching: targetName]
    }
    
    subscript(descendentMatching targetName: String) -> Entity? {
        if name.contains(targetName) {
            return self
        }
        
        var match: Entity? = nil
        for child in children {
            match = child[descendentMatching: targetName]
            if let match = match {
                return match
            }
        }
        
        return match
    }
    
    
    func getParentHasPrefix(nameBeginsWith name: String) -> Entity? {
        if self.name.hasPrefix(name) {
            return self
        }
        guard let nextParent = parent else {
            return nil
        }
        
        return nextParent.getParentHasPrefix(nameBeginsWith: name)
    }
    
    func getParentName(withName name: String) -> Entity? {
        if self.name == name {
            return self
        }
        guard let nextParent = parent else {
            return nil
        }
        
        return nextParent.getParentName(withName: name)
    }
    
    func getSelfOrDescendent(withName name: String) -> Entity? {
        if self.name == name {
            return self
        }
        var match: Entity? = nil
        for child in children {
            match = child.getSelfOrDescendent(withName: name)
            if match != nil {
                return match
            }
        }
        
        return match
    }
    
    func forward(relativeTo referenceEntity: Entity?) -> SIMD3<Float> {
        normalize(convert(direction: SIMD3<Float>(0, 0, +1), to: referenceEntity))
    }
    
    func scaleToFit(maxLength: Float = 1.0) {
        let size = self.visualExtents
        let longestEdge = max(max(size.x, size.y), size.z)
        guard longestEdge != 0 else { return }
        let scaleFactor = (maxLength / longestEdge) * 0.7
        self.setScale([scaleFactor, scaleFactor, scaleFactor], relativeTo: nil)
    }
    
    func centerWithinParent() {
        let boundingBox = self.visualBounds(relativeTo: nil)
        let modelCenter = (boundingBox.min + boundingBox.max) / 2
        self.position = -modelCenter
    }
    
    func scaleIn() {
        var transformWithZeroScale = transform
        transformWithZeroScale.scale = .zero
        
        if let animation = try? AnimationResource.generate(with: FromToByAnimation<Transform>(
            from: transformWithZeroScale,
            to: transform,
            duration: 1.0,
            bindTarget: .transform
        )) {
            playAnimation(animation)
        }
    }
}



extension SIMD4 {
    var xyz: SIMD3<Scalar> {
        self[SIMD3(0, 1, 2)]
    }
}

extension String {
    func toModel<T>(_ type: T.Type, using encoding: String.Encoding = .utf8) -> T? where T : Decodable {
        guard let data = self.data(using: encoding) else { return nil }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            print(error)
        }
        return nil
    }
}

extension GeometrySource {
    
    @MainActor
    func asArray<T>(ofType: T.Type) -> [T] {
        assert(MemoryLayout<T>.stride == stride, "Invalid stride \(MemoryLayout<T>.stride); expected \(stride)")
        return (0..<self.count).map {
            buffer.contents().advanced(by: offset + stride * Int($0)).assumingMemoryBound(to: T.self).pointee
        }
    }
    
    @MainActor
    func asSIMD3<T>(ofType: T.Type) -> [SIMD3<T>] {
        return asArray(ofType: (T, T, T).self).map { .init($0.0, $0.1, $0.2) }
    }
}

extension MeshAnchor.Geometry {
    
    func classificationOf(faceWithIndex index: Int) -> MeshAnchor.MeshClassification {
        guard let classification = self.classifications else { return .none }
        assert(classification.format == MTLVertexFormat.uchar, "Expected one unsigned char (one byte) per classification")
        let classificationPointer = classification.buffer.contents().advanced(by: classification.offset + (classification.stride * index))
        let classificationValue = Int(classificationPointer.assumingMemoryBound(to: CUnsignedChar.self).pointee)
        return MeshAnchor.MeshClassification(rawValue: classificationValue) ?? .none
    }
}


extension MeshAnchor {
    var boundingBox: BoundingBox {
        get async {
            await self.geometry.vertices.asSIMD3(ofType: Float.self).reduce(BoundingBox(), { return $0.union($1) })
        }
    }
    
//    var boundingBox: BoundingBox {
//        self.geometry.vertices.asSIMD3(ofType: Float.self).reduce(BoundingBox(), { return $0.union($1) })
//    }
}
