//
//  ProvidersApp.swift
//  Providers
//
//  Created by marcelodearaujo on 04/12/24.
//

import SwiftUI

@main
@MainActor
struct ProvidersApp: App {
    
    @StateObject private var planeDetectionModel = PlaneDetectionModel()
    @StateObject private var imageTrackingModel = ImageTrackingModel()
    @StateObject private var portalModel = PortalModel()
    @StateObject private var sceneModel = SceneReconstructionModel()
    
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(planeDetectionModel)
                .environmentObject(imageTrackingModel)
                .environmentObject(portalModel)
                .environmentObject(sceneModel)
        }
        
        ImmersiveSpace(id: "PlaneDetectionSpace") {
            ImmersivePlaneView()
                .environmentObject(planeDetectionModel)
        }
        
        ImmersiveSpace(id: "ImageTrackingSpace") {
            ImmersiveImageView()
                .environmentObject(imageTrackingModel)
        }
        
        ImmersiveSpace(id: "PortalSpace") {
            ImmersivePortalView()
                .environmentObject(portalModel)
        }
        
        ImmersiveSpace(id: "SceneSpace") {
            ImmersiveSceneView()
                .environmentObject(sceneModel)
        }
    }
}
