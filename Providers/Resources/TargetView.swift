//
//  TargetPracticeView.swift
//  Providers
//
//  Created by marcelodearaujo on 06/12/24.
//


import SwiftUI
import RealityKit
import ARKit
import HandVector


struct TargetView: View {
    
    @State var jointPositions: [HandSkeleton.JointName: SIMD3<Float>] = [:]
    @State var targets: [Target] = []
    @State var laserBeamEntity: ModelEntity?
    @State var gunEntity: ModelEntity?
    @State private var isShowingGun: Bool = false
    @State private var isReadyToFire: Bool = false
    @State private var didFire: Bool = false
    @State private var lastFingerGunDetectionTime: Date = Date()
    @State var gunshotAudioResource: AudioResource?
    @State private var laserOpacity: Float = defaultLaserOpacity
    @State private var isInCooldown: Bool = false
    
    let defaultRayLength: Float = 10
    let targetScale: Float = 0.25
    let numberOfTargets: Int = 3
    let fingerGunReadyHandInfo = String.gunReadyPosition.toModel(HVHandJsonModel.self)!.convertToHVHandInfo()
    let fingerGunFiredTriggerHandInfo = String.gunTriggerFiredPosition.toModel(HVHandJsonModel.self)!.convertToHVHandInfo()
    let thresholdForFingerGunDetection: Float = 0.95
    let thresholdForTriggerFingerDetection: Float = 0.9
    let fingerGunDebounceInterval: TimeInterval = 0.125
    let onTargetValidityDuration: TimeInterval = 0.1
    let laserFlashDuration: TimeInterval = 0.25
    
    var latestHandTracking: HandVectorManager = .init(left: nil, right: nil)
    
    static let defaultLaserOpacity: Float = 0.25
    
    var body: some View {
        RealityView { content in
            let skybox = createSkybox()
            content.add(skybox)
            
            gunshotAudioResource = try! await loadGunShotAudioResource()
            
            let gunEntity = await createGun()
            content.add(gunEntity)
            self.gunEntity = gunEntity
            
            let laserBeam = createLaserBeam()
            laserBeamEntity = laserBeam
            content.add(laserBeam)
            
            let targets = try! await createTargets()
            targets.forEach({ content.add($0.entity) })
            self.targets = targets
        }
        .task {
            await setupHandTracking()
        }
    }
    
    func setupHandTracking() async {
        let session = ARKitSession()
        let handTracking = HandTrackingProvider()
        
        do {
            try await session.run([handTracking])
            
            for await update in handTracking.anchorUpdates {
                let handAnchor = update.anchor
                if handAnchor.chirality == .right {
                    await updateForHandAnchor(handAnchor)
                }
            }
        } catch {
            print("Error setting up hand tracking: \(error)")
        }
    }
    
    func createGun() async -> ModelEntity {
        let entity = try! await loadGunEntity()
        await removeEntityLighting(entity)
        return entity
    }
    
    func createSkybox() -> ModelEntity {
        let radius: Float = 1E3
        let skyboxMeshResource = MeshResource.generateSphere(radius: radius)
        let entity = ModelEntity(mesh: skyboxMeshResource, materials: [UnlitMaterial(color: .white)])
        entity.scale *= .init(x: -1, y: 1, z: 1)
        entity.transform.translation += SIMD3<Float>(0.0, 200.0, 0.0)
        return entity
    }
    
    func createTargets() async throws -> [Target] {
        let targetEntity = try await loadTargetEntity()
        await removeEntityLighting(targetEntity)

        var targets = [Target]()
        for _ in 0..<numberOfTargets {
            let clonedTarget = targetEntity.clone(recursive: true)
            clonedTarget.scale = [targetScale, targetScale, targetScale]
            clonedTarget.position = randomPosition()
            targets.append(Target(entity: clonedTarget))
        }
        return targets
    }
    
    func removeEntityLighting(_ entity: ModelEntity) async {
        let material = entity.model?.materials.first as! PhysicallyBasedMaterial
        let baseColorTexture = material.baseColor.texture!.resource
        let originalTexture = try! copyTextureResourceToLowLevelTexture(from: baseColorTexture)
        let newMaterial = await UnlitMaterial(texture: try! .init(from: originalTexture))
        entity.model?.materials = [newMaterial]
    }
    
    func copyTextureResourceToLowLevelTexture(from textureResource: TextureResource) throws -> LowLevelTexture {
        var descriptor = LowLevelTexture.Descriptor()
        descriptor.textureType = .type2D
        descriptor.pixelFormat = .rgba16Float
        descriptor.width = textureResource.width
        descriptor.height = textureResource.height
        descriptor.mipmapLevelCount = 1
        descriptor.textureUsage = [.shaderRead, .shaderWrite]
        
        let texture = try LowLevelTexture(descriptor: descriptor)
        try textureResource.copy(to: texture.read())
        
        return texture
    }
    
    func createLaserBeam() -> ModelEntity {
        let cylinderMesh = MeshResource.generateCylinder(height: 1, radius: 0.002)
        let material = UnlitMaterial(color: .red)
        let entity = ModelEntity(mesh: cylinderMesh, materials: [material])
        entity.components.set(OpacityComponent(opacity: 0.0))
        
        return entity
    }
    
    func randomPosition() -> SIMD3<Float> {
        SIMD3<Float>(
            Float.random(in: -1.0...1.0),
            Float.random(in: 0.25...1.75),
            Float.random(in: -5.0...(-2.0))
        )
    }


    func updateForHandAnchor(_ handAnchor: HandAnchor) async {
        updateJointPositions(for: handAnchor)
        updateForHandPosition()
        await checkForHandGestures(for: handAnchor)
    }
    
    func updateJointPositions(for handAnchor: HandAnchor) {
        jointPositions = Dictionary(uniqueKeysWithValues:
            HandSkeleton.JointName.allCases.compactMap { jointName in
                guard let joint = handAnchor.handSkeleton?.joint(jointName) else { return nil }
                let worldPosition = handAnchor.originFromAnchorTransform * joint.anchorFromJointTransform.columns.3
                return (jointName, SIMD3<Float>(worldPosition.x, worldPosition.y, worldPosition.z))
            }
        )
    }
    
    func updateForHandPosition() {
        guard let wristPosition = jointPositions[.wrist],
              let palmPosition = calculatePalmPosition() else {
            return
        }
        var rayDirection = simd_normalize(palmPosition - wristPosition)
        rayDirection.y -= .pi * 0.05
        
        let closestHitTarget = updateTargets(rayStart: wristPosition, rayDirection: rayDirection)
        
        let rayLength: Float
        let rayEnd: SIMD3<Float>
        
        if let hitTarget = closestHitTarget {
            rayLength = simd_distance(wristPosition, hitTarget.entity.position)
            rayEnd = wristPosition + rayDirection * rayLength
        } else {
            rayLength = defaultRayLength
            rayEnd = wristPosition + rayDirection * rayLength
        }
        
        updateLaser(from: wristPosition, to: rayEnd)
        updateGun(from: wristPosition, to: rayEnd)
        didFire = false
    }

    func updateTargets(rayStart: SIMD3<Float>, rayDirection: SIMD3<Float>) -> Target? {
        var closestHit: (target: Target, distance: Float, position: SIMD3<Float>)? = nil

        for index in targets.indices {
            if let intersectionPoint = rayIntersectsSphere(rayStart: rayStart,
                                                           rayDirection: rayDirection,
                                                           sphereCenter: targets[index].entity.position,
                                                           sphereRadius: targetScale) {
                targets[index].lastOnTargetTime = Date()
                
                let distance = simd_distance(rayStart, intersectionPoint)
                if closestHit == nil || distance < closestHit!.distance {
                    closestHit = (targets[index], distance, intersectionPoint)
                }
            } else {
                targets[index].lastOnTargetTime = nil
            }
            
            if didFire {
                let isRecentlyOnTarget = isRecentlyOnTarget(for: targets[index])
                targets[index].lastOnTargetTime = nil
                if isRecentlyOnTarget && !targets[index].isHit {
                    // Hit detected, move the sphere
                    targets[index].entity.position = randomPosition()
                    targets[index].isHit = true
                }
            }
        }
        
        if didFire {
            didFire = false
            for index in targets.indices {
                targets[index].isHit = false
            }
        }

        return closestHit?.target
    }
    
    func rayIntersectsSphere(rayStart: SIMD3<Float>,
                                         rayDirection: SIMD3<Float>,
                                         sphereCenter: SIMD3<Float>,
                                         sphereRadius: Float) -> SIMD3<Float>? {
        let originToCenter = rayStart - sphereCenter
        let a = simd_dot(rayDirection, rayDirection)
        let b = 2.0 * simd_dot(originToCenter, rayDirection)
        let c = simd_dot(originToCenter, originToCenter) - sphereRadius * sphereRadius
        let discriminant = b * b - 4 * a * c
        
        if discriminant < 0 {
            return nil
        }
        
        let t = (-b - sqrt(discriminant)) / (2 * a)
        
        if t < 0 {
            return nil
        }
        
        let intersectionPoint = rayStart + t * rayDirection
        return intersectionPoint
    }
    
    func isRecentlyOnTarget(for target: Target) -> Bool {
        guard let lastOnTargetTime = target.lastOnTargetTime else { return false }
        return Date().timeIntervalSince(lastOnTargetTime) <= onTargetValidityDuration
    }
    
    func updateLaser(from start: SIMD3<Float>, to end: SIMD3<Float>) {
        guard let entity = laserBeamEntity else { return }
        let direction = end - start
        let distance = simd_length(direction)
        let midpoint = (start + end) / 2
        
        entity.position = midpoint
        entity.scale = [1, distance, 1]
        
        let yAxis = simd_normalize(direction)
        let xAxis = simd_normalize(simd_cross([0, 1, 0], yAxis))
        let zAxis = simd_cross(xAxis, yAxis)
        
        let rotationMatrix = simd_float3x3(columns: (xAxis, yAxis, zAxis))
        entity.transform.rotation = simd_quaternion(rotationMatrix)
        
        entity.components.set(OpacityComponent(opacity: laserOpacity))
    }
    
    func flashLaserBeam() {
        laserOpacity = 1.0
        isInCooldown = true
        
        Task {
            try? await Task.sleep(nanoseconds: UInt64(laserFlashDuration * 1_000_000_000))
            laserOpacity = TargetView.defaultLaserOpacity
            isInCooldown = false
        }
    }
    
    func updateGun(from start: SIMD3<Float>, to end: SIMD3<Float>) {
        guard let entity = gunEntity else { return }
        let direction = end - start
        entity.position = start
        entity.scale = [0.1, 0.1, 0.1]
        
        let yAxis = simd_normalize(direction)
        let xAxis = simd_normalize(simd_cross([0, 1, 0], yAxis))
        let zAxis = simd_cross(xAxis, yAxis)
        
        let rotationZ = simd_quatf(angle: .pi*0.5, axis: [0, 0, 1])
        let rotationX = simd_quatf(angle: -.pi*0.5, axis: [1, 0, 0])
        
        let rotationMatrix = simd_float3x3(columns: (xAxis, yAxis, zAxis))
        entity.transform.rotation = simd_quaternion(rotationMatrix) * rotationZ * rotationX
    }
    
    func calculatePalmPosition() -> SIMD3<Float>? {
        guard let middleFingerBase = jointPositions[.middleFingerMetacarpal],
              let ringFingerBase = jointPositions[.ringFingerMetacarpal],
              let indexFingerBase = jointPositions[.indexFingerMetacarpal] else {
            return nil
        }
        
        return (middleFingerBase + ringFingerBase + indexFingerBase) / 3
    }
    
    func checkForHandGestures(for handAnchor: HandAnchor) async {
        let handInfo = latestHandTracking.generateHandInfo(from: handAnchor)
        if let handInfo {
            await latestHandTracking.updateHandSkeletonEntity(from: handInfo)
            
        }
        
        let averageAndEachRightScores = latestHandTracking.rightHandVector?.averageAndEachSimilarities(of: .fiveFingers, to: fingerGunReadyHandInfo!)
        let average = averageAndEachRightScores?.0
        if thresholdForFingerGunDetection < average! {
            lastFingerGunDetectionTime = Date()
            if !isReadyToFire {
                print("got the finger gun with average: \(average!)")
                isReadyToFire = true
            }
            if !isShowingGun {
                guard let debugCylinder = laserBeamEntity else { return }
                debugCylinder.components.set(OpacityComponent(opacity: 1.0))
                isShowingGun = true
            }
        } else {
            Task {
                try await Task.sleep(nanoseconds: UInt64(fingerGunDebounceInterval * 1_000_000_000))
                if Date().timeIntervalSince(lastFingerGunDetectionTime) >= fingerGunDebounceInterval {
                    if isShowingGun {
                        print("got no finger gun with average: \(average!)")
                        guard let debugCylinder = laserBeamEntity else { return }
                        debugCylinder.components.set(OpacityComponent(opacity: 0.0))
                        isShowingGun = false
                        isReadyToFire = false
                    }
                }
            }
        }
        
        let triggerScores = latestHandTracking.rightHandVector?.averageAndEachSimilarities(of: .fiveFingers, to: fingerGunFiredTriggerHandInfo!)
        let triggerAverage = triggerScores?.0
        if thresholdForTriggerFingerDetection < triggerAverage! {
            if isReadyToFire && !isInCooldown {
                print("got trigger with average: \(triggerAverage!)")
                isReadyToFire = false
                didFire = true

                if let gunshotAudioResource {
                    gunEntity?.playAudio(gunshotAudioResource)
                }
                
                flashLaserBeam()
            }
        }
    }
}

// MARK: loading entities
extension TargetView {
    func loadGunEntity(url: URL = URL(string: "https://matt54.github.io/Resources/laser_gun.usdz")!) async throws -> ModelEntity {
        let (downloadedURL, _) = try await URLSession.shared.download(from: url)
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let destinationURL = documentsDirectory.appendingPathComponent("downloadedLaserGunModel.usdz")
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.moveItem(at: downloadedURL, to: destinationURL)
        let entity = try await ModelEntity.init(contentsOf: destinationURL)
        return entity
    }
    
    func loadTargetEntity(url: URL = URL(string: "https://matt54.github.io/Resources/target.usdz")!) async throws -> ModelEntity {
        let (downloadedURL, _) = try await URLSession.shared.download(from: url)
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let destinationURL = documentsDirectory.appendingPathComponent("downloadedTargetModel.usdz")
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.moveItem(at: downloadedURL, to: destinationURL)
        let entity = try await ModelEntity.init(contentsOf: destinationURL)
        
        let rotationX = simd_quatf(angle: .pi, axis: [0, 1, 0])
        entity.transform.rotation = rotationX
        
        return entity
    }
    
    func loadGunShotAudioResource(url: URL = URL(string: "https://matt54.github.io/Resources/laser_gun_shot.wav")!) async throws -> AudioFileResource {
        let (downloadedURL, _) = try await URLSession.shared.download(from: url)
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let destinationURL = documentsDirectory.appendingPathComponent("downloadedSound.wav")
        
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.moveItem(at: downloadedURL, to: destinationURL)
        
        let audioResource = try AudioFileResource.load(contentsOf: destinationURL)
        return audioResource
    }
}

struct Target {
    let entity: ModelEntity
    var isHit: Bool = false
    var lastOnTargetTime: Date?
}


extension String {
    static let gunReadyPosition: String = """
{"transform":[[0.03681829,-0.35651627,0.9335633,0],[0.9981043,-0.03298368,-0.051959727,0],[0.049316857,0.9337067,0.35462606,0],[0.119505,1.058816,-0.3033591,1]],"name":"right","joints":[{"transform":[[1,0,0,0],[0,1,0,0],[0,0,1,0],[0,0,0,1]],"name":"wrist","isTracked":true},{"isTracked":true,"transform":[[0.7483124,0.08903434,-0.6573445,0],[0.6232275,0.24503177,0.7426623,0],[0.22719273,-0.96541846,0.12787166,0],[-0.023037225,-0.011565208,0.019217536,1]],"name":"thumbKnuckle"},{"isTracked":true,"transform":[[0.9145838,0.03962274,-0.40245014,0],[0.3839136,0.22763534,0.8948699,0],[0.1270691,-0.9729398,0.19297989,0],[-0.06262271,-0.016338525,0.053467937,0.9999999]],"name":"thumbIntermediateBase"},{"transform":[[0.55769247,-0.09324432,-0.8247935,0],[0.82048357,0.21233602,0.5307732,0],[0.12564181,-0.97273785,0.19492361,0],[-0.09256029,-0.017590031,0.06606347,0.9999999]],"name":"thumbIntermediateTip","isTracked":true},{"isTracked":true,"transform":[[0.5576926,-0.09324434,-0.8247935,0],[0.8204833,0.21233588,0.5307733,0],[0.12564164,-0.9727376,0.1949236,0],[-0.10933509,-0.014713061,0.09040629,0.9999999]],"name":"thumbTip"},{"isTracked":true,"name":"indexFingerMetacarpal","transform":[[0.9873512,0.0007703505,-0.15854767,0],[-0.00018403005,0.99999326,0.0037125493,0],[0.15854947,-0.003636434,0.9873445,0],[-0.02504237,8.650124e-05,0.016333118,1]]},{"name":"indexFingerKnuckle","isTracked":true,"transform":[[0.9271389,0.1894835,0.3232792,0],[-0.20793396,0.9778683,0.023180438,0],[-0.31173214,-0.08871223,0.94601953,0],[-0.09699588,0.00033357737,0.02648428,1]]},{"isTracked":true,"transform":[[0.9415803,0.10521732,0.3199318,0],[-0.12780455,0.9905191,0.050381172,0],[-0.31159747,-0.08832667,0.94610006,0],[-0.13916928,-0.008303657,0.011948585,0.99999994]],"name":"indexFingerIntermediateBase"},{"transform":[[0.94819283,0.034945816,0.31576785,0],[-0.060861282,0.9955039,0.072583534,0],[-0.31181157,-0.08804125,0.9460563,0],[-0.16357674,-0.010998578,0.0036838902,0.99999994]],"isTracked":true,"name":"indexFingerIntermediateTip"},{"transform":[[0.94819283,0.0349457,0.315768,0],[-0.060861256,0.9955037,0.07258351,0],[-0.3118117,-0.08804125,0.9460561,0],[-0.18628134,-0.011772217,-0.0039144484,0.99999994]],"name":"indexFingerTip","isTracked":true},{"isTracked":true,"transform":[[0.9999436,0.00029446578,0.010613574,0],[-0.00033532665,0.9999925,0.0038510533,0],[-0.0106123155,-0.0038544233,0.99993616,0],[-0.027172834,0.0001347065,0.0036730468,1]],"name":"middleFingerMetacarpal"},{"isTracked":true,"name":"middleFingerKnuckle","transform":[[0.31107935,0.9494624,0.0418443,0],[-0.94966394,0.312256,-0.025200296,0],[-0.036992837,-0.031898756,0.99880624,0],[-0.095856436,0.00042155385,0.0019043083,0.99999994]]},{"transform":[[-0.97067386,0.23868601,-0.028664839,0],[-0.23642187,-0.9694015,-0.06607428,0],[-0.04355868,-0.057359572,0.99740297,0],[-0.10820865,-0.04728632,0.0028083322,0.9999999]],"name":"middleFingerIntermediateBase","isTracked":true},{"isTracked":true,"transform":[[-0.98711973,-0.1526101,-0.048010733,0],[0.1551362,-0.98640466,-0.05421107,0],[-0.039084814,-0.06096107,0.9973746,0],[-0.07775817,-0.05483128,0.004591465,0.9999999]],"name":"middleFingerIntermediateTip"},{"name":"middleFingerTip","isTracked":true,"transform":[[-0.98711985,-0.15260991,-0.04801078,0],[0.15513599,-0.9864048,-0.054211125,0],[-0.039084826,-0.06096117,0.99737483,0],[-0.055462185,-0.051387776,0.005703509,0.9999999]]},{"isTracked":true,"transform":[[0.9876838,0.00039916535,0.15646292,0],[-0.001013631,0.999992,0.0038470975,0],[-0.15646014,-0.00395833,0.98767626,0],[-0.02746223,-0.0013832152,-0.00899744,1]],"name":"ringFingerMetacarpal"},{"transform":[[-0.0012533537,0.9747956,-0.22309683,0],[-0.9960826,-0.020943103,-0.08591284,0],[-0.088419706,0.22211517,0.9710031,0],[-0.094665445,-0.0011133702,-0.020322772,0.99999994]],"isTracked":true,"name":"ringFingerKnuckle"},{"name":"ringFingerIntermediateBase","isTracked":true,"transform":[[-0.9931481,0.042646114,-0.10880357,0],[-0.0667791,-0.97115594,0.22890316,0],[-0.09590343,0.23460054,0.96734947,0],[-0.09184222,-0.04280009,-0.008270023,0.9999999]]},{"isTracked":true,"name":"ringFingerIntermediateTip","transform":[[-0.87231886,-0.48775947,0.033920035,0],[0.47993666,-0.84094685,0.24993832,0],[-0.093384825,0.23430538,0.9676676,0],[-0.06364327,-0.044113144,-0.004825471,0.9999999]]},{"transform":[[-0.8723191,-0.4877596,0.03391996,0],[0.4799366,-0.84094703,0.24993841,0],[-0.093384914,0.23430541,0.96766764,0],[-0.044957124,-0.033260565,-0.00605893,0.9999999]],"isTracked":true,"name":"ringFingerTip"},{"transform":[[0.9754438,0.0007679999,0.22024716,0],[-0.0016250212,0.9999917,0.003710361,0],[-0.22024249,-0.003977161,0.9754369,0],[-0.026689336,-0.0029354095,-0.023558915,1]],"isTracked":true,"name":"littleFingerMetacarpal"},{"name":"littleFingerKnuckle","transform":[[-0.021861674,0.9597742,-0.2799214,0],[-0.9730536,-0.08471092,-0.21445592,0],[-0.2295416,0.26769006,0.9357632,0],[-0.08487275,-0.0027343482,-0.037119243,1]],"isTracked":true},{"name":"littleFingerIntermediateBase","transform":[[-0.95487165,0.1191173,-0.2720872,0],[-0.18119034,-0.9594734,0.21582665,0],[-0.23535168,0.2553863,0.9377566,0],[-0.082020074,-0.035506573,-0.025537848,1]],"isTracked":true},{"name":"littleFingerIntermediateTip","transform":[[-0.8006587,-0.59837437,-0.029901683,0],[0.5545437,-0.75905365,0.34105653,0],[-0.22677635,0.25648803,0.93956715,0],[-0.06307931,-0.037934672,-0.01993567,1]],"isTracked":true},{"name":"littleFingerTip","isTracked":true,"transform":[[-0.8006587,-0.59837437,-0.029901683,0],[0.55454355,-0.7590536,0.3410568,0],[-0.22677657,0.2564883,0.93956715,0],[-0.04816789,-0.026222985,-0.020020342,1]]},{"isTracked":true,"transform":[[-0.83367807,-0.33506683,0.4389886,0],[-0.36958972,0.92916626,0.007321467,0],[-0.41034657,-0.15614182,-0.8984629,0],[-2.9802322e-08,1.4901161e-08,-2.9802322e-08,1]],"name":"forearmWrist"},{"name":"forearmArm","transform":[[-0.833678,-0.3350668,0.4389886,0],[-0.36958975,0.92916626,0.0073214276,0],[-0.41034657,-0.15614179,-0.89846283,0],[0.22288692,0.083471484,-0.107541226,1]],"isTracked":true}],"chirality":"right"}
"""
    
    static var gunTriggerFiredPosition: String = """
{"chirality":"right","joints":[{"transform":[[1,0,0,0],[0,1,0,0],[0,0,1,0],[0,0,0,1]],"name":"wrist","isTracked":true},{"transform":[[0.7483334,0.09519935,-0.65645605,0],[0.6199202,0.2517302,0.7431899,0],[0.23600104,-0.96310407,0.12936214,0],[-0.023353577,-0.011348635,0.018963456,1.0000001]],"name":"thumbKnuckle","isTracked":true},{"isTracked":true,"transform":[[0.9556311,0.05204724,-0.28993207,0],[0.27259618,0.21673742,0.93739885,0],[0.11162812,-0.9748416,0.19293313,0],[-0.06494015,-0.016365109,0.053815972,1.0000001]],"name":"thumbIntermediateBase"},{"transform":[[0.65147614,-0.07337183,-0.7551131,0],[0.7500864,0.21158442,0.6265804,0],[0.11379688,-0.97460204,0.19287737,0],[-0.09750525,-0.017905606,0.06285423,1]],"isTracked":true,"name":"thumbIntermediateTip"},{"transform":[[0.65147597,-0.07337182,-0.755113,0],[0.7500863,0.21158457,0.6265802,0],[0.11379693,-0.97460186,0.19287738,0],[-0.11828706,-0.015484761,0.0855253,1]],"name":"thumbTip","isTracked":true},{"isTracked":true,"name":"indexFingerMetacarpal","transform":[[0.9904148,0.00047922484,-0.1381248,0],[-0.0015663946,0.9999686,-0.0077618966,0],[0.13811672,0.007903845,0.9903845,0],[-0.025574356,0.00016841292,0.016237155,1.0000001]]},{"transform":[[0.33106402,0.9313371,0.15168403,0],[-0.9435455,0.32487956,0.064618684,0],[0.010902685,-0.16451362,0.9863149,0],[-0.10142365,0.00072960556,0.025060492,1.0000001]],"isTracked":true,"name":"indexFingerKnuckle"},{"name":"indexFingerIntermediateBase","isTracked":true,"transform":[[-0.9999372,-0.0050846054,0.010002013,0],[0.003429331,-0.98726726,-0.1590336,0],[0.0106832525,-0.15898922,0.9872226,0],[-0.11412289,-0.04431664,0.019907355,1.0000001]]},{"name":"indexFingerIntermediateTip","isTracked":true,"transform":[[-0.55583847,-0.8214681,-0.12741268,0],[0.8312102,-0.5470858,-0.09893063,0],[0.011562692,-0.16089611,0.98690385,0],[-0.08689164,-0.044329368,0.020021155,1.0000001]]},{"name":"indexFingerTip","isTracked":true,"transform":[[-0.55583835,-0.8214681,-0.1274127,0],[0.8312101,-0.54708576,-0.09893059,0],[0.011562661,-0.16089608,0.9869037,0],[-0.07507946,-0.0250963,0.022131085,1.0000001]]},{"isTracked":true,"name":"middleFingerMetacarpal","transform":[[0.99994224,5.4265183e-05,0.010770501,0],[2.7246339e-05,0.9999715,-0.007565906,0],[-0.010770587,0.0075657517,0.99991375,0],[-0.027691185,0.00021959841,0.0036745965,1.0000001]]},{"transform":[[0.2625057,0.96121,0.08465515,0],[-0.9639889,0.26511344,-0.020991897,0],[-0.042620845,-0.07609611,0.9961894,0],[-0.10007346,0.0007865727,0.0017653409,1.0000001]],"name":"middleFingerKnuckle","isTracked":true},{"isTracked":true,"transform":[[-0.9960801,-0.06880847,-0.055586327,0],[0.07441876,-0.9915644,-0.10612293,0],[-0.047815263,-0.10984362,0.9927982,0],[-0.109669164,-0.0483307,4.4017594e-05,1]],"name":"middleFingerIntermediateBase"},{"name":"middleFingerIntermediateTip","transform":[[-0.34592554,-0.9304006,-0.121205255,0],[0.937399,-0.34825101,-0.0021236737,0],[-0.040233966,-0.114352286,0.9926253,0],[-0.07765334,-0.04632087,0.0020706353,1]],"isTracked":true},{"name":"middleFingerTip","transform":[[-0.3459255,-0.93040043,-0.12120523,0],[0.9373989,-0.34825101,-0.0021236467,0],[-0.04023399,-0.11435226,0.9926252,0],[-0.071053825,-0.024442425,0.0037397146,1]],"isTracked":true},{"transform":[[0.9901111,-0.000524097,0.14028518,0],[0.0015186571,0.9999746,-0.0069826003,0],[-0.14027794,0.007126593,0.99008673,0],[-0.027912617,-0.00127545,-0.008930057,1.0000001]],"isTracked":true,"name":"ringFingerMetacarpal"},{"transform":[[0.11645274,0.99289507,-0.024456479,0],[-0.9910486,0.11454721,-0.0685683,0],[-0.0652797,0.032222517,0.99734664,0],[-0.09785095,-0.0007026344,-0.019427152,1.0000001]],"name":"ringFingerKnuckle","isTracked":true},{"isTracked":true,"name":"ringFingerIntermediateBase","transform":[[-0.997761,-0.016860921,-0.06472351,0],[0.012973086,-0.9981128,0.060025338,0],[-0.06561342,0.059051238,0.9960965,0],[-0.099433765,-0.044465277,-0.015910923,1.0000001]]},{"transform":[[-0.2544789,-0.96663296,0.029352397,0],[0.96455187,-0.2515047,0.079906285,0],[-0.06985777,0.04864639,0.9963702,0],[-0.069589265,-0.044131514,-0.013678611,1.0000001]],"name":"ringFingerIntermediateTip","isTracked":true},{"isTracked":true,"transform":[[-0.2544788,-0.9666329,0.02935244,0],[0.964552,-0.25150472,0.07990631,0],[-0.06985778,0.048646417,0.9963702,0],[-0.0654154,-0.022222081,-0.015528647,1]],"name":"ringFingerTip"},{"transform":[[0.97497225,-0.000826969,0.22232538,0],[0.0023143436,0.9999767,-0.006429921,0],[-0.2223149,0.006783522,0.97495145,0],[-0.027045697,-0.0027898103,-0.023430854,1.0000001]],"name":"littleFingerMetacarpal","isTracked":true},{"transform":[[0.06825185,0.9954417,-0.066615984,0],[-0.9734078,0.05180799,-0.22314477,0],[-0.21867634,0.08007455,0.97250664,0],[-0.08645508,-0.00229989,-0.037184328,1.0000001]],"name":"littleFingerKnuckle","isTracked":true},{"isTracked":true,"transform":[[-0.9729524,0.06563075,-0.22148769,0],[-0.08437353,-0.99351335,0.07624091,0],[-0.21504717,0.09286644,0.9721785,0],[-0.086084165,-0.037450034,-0.032782976,1.0000002]],"name":"littleFingerIntermediateBase"},{"isTracked":true,"name":"littleFingerIntermediateTip","transform":[[-0.31905454,-0.94770515,0.007732848,0],[0.92150366,-0.30830652,0.23617493,0],[-0.22144006,0.08247853,0.97168005,0],[-0.065962076,-0.038880963,-0.028106306,1.0000002]]},{"isTracked":true,"transform":[[-0.31905454,-0.94770527,0.007732892,0],[0.9215038,-0.30830655,0.23617496,0],[-0.22144006,0.08247855,0.97168016,0],[-0.06090485,-0.019953838,-0.02932877,1.0000004]],"name":"littleFingerTip"},{"isTracked":true,"name":"forearmWrist","transform":[[-0.91424805,-0.29512966,0.2775777,0],[-0.30960014,0.9508265,-0.008769782,0],[-0.26133996,-0.09395588,-0.96066326,0],[2.0861626e-07,-1.6391277e-07,2.0861626e-07,1.0000001]]},{"transform":[[-0.91424805,-0.29512966,0.2775777,0],[-0.30960017,0.9508265,-0.008769772,0],[-0.26134,-0.09395589,-0.9606634,0],[0.25306943,0.070762575,-0.0623462,1]],"name":"forearmArm","isTracked":true}],"name":"right","transform":[[-0.09891344,-0.16087997,0.98200476,0],[0.9935917,-0.07020852,0.08857849,0],[0.054694623,0.9844735,0.16679356,0],[0.11687718,1.0611293,-0.43109167,0.99999994]]}
"""
}
