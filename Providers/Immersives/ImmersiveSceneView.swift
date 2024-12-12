//
//  ImmersiveSceneView.swift
//  Providers
//
//  Created by marcelodearaujo on 11/12/24.
//

import SwiftUI
import RealityKit


struct ImmersiveSceneView: View {
    
    @EnvironmentObject var scene: SceneReconstructionModel
    
    var body: some View {
        RealityView { content in
            content.add(scene.rootEntity)
        }
        .task {await scene.run()}
    }
}
