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
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(planeDetectionModel)
                .environmentObject(imageTrackingModel)
        }
        
        ImmersiveSpace(id: "PlaneDetectionSpace") {
            ImmersivePlaneView()
                .environmentObject(planeDetectionModel)
        }
        
        ImmersiveSpace(id: "ImageTrackingSpace") {
            ImmersiveImageView()
                .environmentObject(imageTrackingModel)
        }
    }
}
