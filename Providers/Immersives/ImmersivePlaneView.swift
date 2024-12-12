//
//  ImmersivePlaneView.swift
//  Providers
//
//  Created by marcelodearaujo on 06/12/24.
//

import SwiftUI
import RealityKit

struct ImmersivePlaneView: View {
    
    @EnvironmentObject var model: PlaneDetectionModel
    
    var body: some View {
        RealityView { content in
            content.add(model.setupContentEntity())
        }
        
        .task { await model.runSession()}
        .task { await model.processPlaneDetectionUpdates()}
        .task { await model.monitorSessionEvents()}
    }
}
