//
//  ContentView.swift
//  Providers
//
//  Created by marcelodearaujo on 04/12/24.
//

import SwiftUI
import RealityKit

struct ContentView: View {
    @State private var immersivePlaneIsActive = false
    @State private var immersiveImageIsActive = false

    @Environment(\.openImmersiveSpace) var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace

    var body: some View {
        VStack {
            HStack {
                Button("Show Immersive Plane") {
                    immersivePlaneIsActive.toggle()
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)

                Button("Show Immersive Image") {
                    immersiveImageIsActive.toggle()
                }
                .padding()
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(8)
            }

            if immersivePlaneIsActive {
                ImmersivePlaneView()
            }

            if immersiveImageIsActive {
                ImmersiveImageView()
            }
        }
        .padding()
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
}
