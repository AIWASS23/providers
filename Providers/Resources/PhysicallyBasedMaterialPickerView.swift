//
//  PhysicallyBasedMaterialPickerView.swift
//  Providers
//
//  Created by marcelodearaujo on 06/12/24.
//


import RealityKit
import SwiftUI

struct PhysicallyBasedMaterialPickerView: View {
    @State var entity: ModelEntity?
    @State var baseColorTextureResource: TextureResource?
    @State var materialParameters: PhysicallyBasedMaterialParameters = PhysicallyBasedMaterialParameters()
    
    var body: some View {
        RealityView { content in
            let entity = generateEntity()
            content.add(entity)
            entity.position.z = -0.4
            self.entity = entity
        }
        .ornament(attachmentAnchor: .scene(.bottomFront)) {
            SettingsView(materialParameters: $materialParameters)
        }
        .onChange(of: materialParameters) { oldValue, newValue in
            entity?.model?.materials = [getMaterial()]
        }
    }
    
    func generateEntity() -> ModelEntity {
        let meshResource = MeshResource.generateSphere(radius: 0.2)
        return ModelEntity(mesh: meshResource, materials: [getMaterial()])
    }

    func getMaterial() -> RealityKit.Material {
        var material = PhysicallyBasedMaterial()
        material.metallic = .init(floatLiteral: materialParameters.metallic)
        material.roughness = .init(floatLiteral: materialParameters.roughness)
        material.baseColor.tint = materialParameters.baseColor
        material.faceCulling = .none
        material.blending = .transparent(opacity: 1.0)
        material.clearcoat = .init(floatLiteral: materialParameters.clearcoat)
        material.clearcoatRoughness = .init(floatLiteral: materialParameters.clearcoatRoughness)
        material.anisotropyLevel = .init(floatLiteral: materialParameters.anisotropyLevel)
        material.anisotropyAngle = .init(floatLiteral: materialParameters.anisotropyAngle)
        material.emissiveColor = .init(color: materialParameters.emissiveColor)
        material.emissiveIntensity = materialParameters.emissiveIntensity
        if materialParameters.applyTexture {
            material.baseColor.texture = .init(baseColorTextureResource!)
        }
        return material
    }
    
    struct PhysicallyBasedMaterialParameters: Equatable {
        var baseColor: UIColor = .magenta
        var metallic: Float = 0.0
        var roughness: Float = 0.0
        var clearcoat: Float = 0.0
        var clearcoatRoughness: Float = 0.5
        var anisotropyLevel: Float = 0.0
        var anisotropyAngle: Float = 0.25
        var emissiveColor: UIColor = .black
        var emissiveIntensity: Float = 0.0
        var applyTexture: Bool = false
    }
    
    struct SettingsView: View {
        @Binding var materialParameters: PhysicallyBasedMaterialParameters
        
        var backgroundColor: Color {
            return Color(materialParameters.baseColor)
        }
        
        var body: some View {
            VStack(alignment: .leading) {
                HStack {
                    Text("Metallic: \(materialParameters.metallic, specifier: "%.3f")")
                    Spacer(minLength: 0)
                    Slider(value: $materialParameters.metallic)
                        .frame(width: 225)
                }
                
                HStack {
                    Text("Roughness: \(materialParameters.roughness, specifier: "%.3f")")
                    Spacer(minLength: 0)
                    Slider(value: $materialParameters.roughness)
                        .frame(width: 225)
                }
                
                HStack {
                    Text("Clear coat: \(materialParameters.clearcoat, specifier: "%.3f")")
                    Spacer(minLength: 0)
                    Slider(value: $materialParameters.clearcoat)
                        .frame(width: 225)
                }
                
                HStack {
                    Text("Clear Coat Roughness: \(materialParameters.clearcoatRoughness, specifier: "%.3f")")
                    Spacer(minLength: 0)
                    Slider(value: $materialParameters.clearcoatRoughness)
                        .frame(width: 225)
                }
                
                ColorPicker("Emmissive Color", selection: Binding(
                    get: { Color(materialParameters.emissiveColor) },
                    set: { materialParameters.emissiveColor = UIColor($0) }
                ))
                
                HStack {
                    Text("Emmissive Intensity: \(materialParameters.emissiveIntensity, specifier: "%.3f")")
                    Spacer(minLength: 0)
                    Slider(value: $materialParameters.emissiveIntensity, in: 0...3)
                        .frame(width: 225)
                }
                
                HStack {
                    Text("Anisotropy Level: \(materialParameters.anisotropyLevel, specifier: "%.3f")")
                    Spacer(minLength: 0)
                    Slider(value: $materialParameters.anisotropyLevel)
                        .frame(width: 225)
                }
                
                HStack {
                    Text("Anisotropy Angle: \(materialParameters.anisotropyAngle, specifier: "%.3f")")
                    Spacer(minLength: 0)
                    Slider(value: $materialParameters.anisotropyAngle)
                        .frame(width: 225)
                }
                
                ColorPicker("Base Color", selection: Binding(
                    get: { Color(materialParameters.baseColor) },
                    set: { materialParameters.baseColor = UIColor($0) }
                ))
                
                HStack {
                    Text("Apply Texture: \(materialParameters.applyTexture)")
                    Spacer(minLength: 0)
                    Toggle(isOn: $materialParameters.applyTexture, label: {Text("")})
                        .frame(width: 225)
                }
            }
            .frame(width: 400)
            .padding()
            .background(backgroundColor.opacity(0.5))
            .cornerRadius(20)
        }
    }
}

#Preview {
    PhysicallyBasedMaterialPickerView()
}
