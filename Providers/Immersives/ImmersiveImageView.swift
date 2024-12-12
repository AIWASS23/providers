//
//  ImmersiveView.swift
//  Providers
//
//  Created by marcelodearaujo on 04/12/24.
//

import Foundation
import SwiftUI
import RealityKit

struct ImmersiveImageView: View {
    
    @EnvironmentObject var model: ImageTrackingModel
    
    var body: some View {
        RealityView { content in
            content.add(model.setupContentEntity())
        }
        .task { await model.runSession() }
        .task { await model.processImageTrackingUpdates() }
        .task { await model.monitorSessionEvents() }
    }
}

// Fazer pequenos Notions das classes 

// CameraFrameProvider
// BarcodeDetectionProvider
// EnvironmentLightEstimationProvider
// HandTrackingProvider
// ImageTrackingProvider
// ObjectTrackingProvider
// PlaneDetectionProvider
// RoomTrackingProvider
// SceneReconstructionProvider
// WorldTrackingProvider

