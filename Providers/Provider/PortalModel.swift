//
//  OuterSpaceCeilingPortalProvider.swift
//  Providers
//
//  Created by marcelodearaujo on 11/12/24.
//


import ARKit
import SwiftUI
import RealityKit
import Observation

@MainActor
class PortalModel: ObservableObject {
    
    @Published var portalEntity: Entity?
    @Published var maxRadius: Float = 0
    @Published var portalTransform: simd_float4x4?
    @Published var portalScale: Float = 0

    let session = ARKitSession()
    let planeData = PlaneDetectionProvider(alignments: [.horizontal])
    var detectionTimer: Timer?
    var animationTimer: Timer?

    let portalWorld = Entity()
    let skyboxRadius: Float = 1E3
    let detectionDuration: TimeInterval = 2.0
    let animationDuration: TimeInterval = 5.0
    let updateInterval: TimeInterval = 1/60.0

    func startARSession() async throws {
        try await session.run([planeData])
        startDetectionTimer()

        for await update in planeData.anchorUpdates {
            let anchor = update.anchor
            if anchor.classification == .ceiling {
                updateMaxRadius(anchor: anchor)
            }
        }
    }

    func stopARSession() {
        session.stop()
        stopDetectionTimer()
        stopAnimationTimer()
    }

    func startDetectionTimer() {
        detectionTimer = Timer.scheduledTimer(withTimeInterval: detectionDuration, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            
            self.session.stop()
            
            Task { @MainActor in
                self.createPortal()
                self.startAnimationTimer()
            }
        }
    }

    func stopDetectionTimer() {
        detectionTimer?.invalidate()
        detectionTimer = nil
    }

    private func updateMaxRadius(anchor: PlaneAnchor) {
        let width = anchor.geometry.extent.width
        let height = anchor.geometry.extent.height
        let radius = min(width, height) * 0.8
        if radius > maxRadius {
            maxRadius = radius
            portalTransform = anchor.originFromAnchorTransform
        }
    }

    private func createPortal() {
        guard let transform = portalTransform else { return }

        let entity = Entity()
        entity.setTransformMatrix(transform, relativeTo: nil)

        let meshResource = MeshResource.generatePlane(width: maxRadius, depth: maxRadius, cornerRadius: maxRadius * 0.5)
        entity.components.set(
            ModelComponent(
                mesh: meshResource,
                materials: [PortalMaterial()]
            )
        )
        entity.components.set(PortalComponent(target: portalWorld))

        portalEntity = entity
        portalWorld.addChild(entity)
    }

    private func startAnimationTimer() {
        animationTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            Task {@MainActor in
                self.portalScale += Float(self.updateInterval / self.animationDuration)
                if self.portalScale >= 1 {
                    self.portalScale = 1
                    self.stopAnimationTimer()
                }
            }
        }
    }

    private func stopAnimationTimer() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    func loadImageFromAssets(named imageName: String) throws -> CGImage {
        guard let uiImage = UIImage(named: imageName) else {
            throw NSError(domain: "ImageError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Image '\(imageName)' not found in assets."])
        }
        guard let cgImage = uiImage.cgImage else {
            throw NSError(domain: "ImageError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert UIImage to CGImage."])
        }
        return cgImage
    }
}
