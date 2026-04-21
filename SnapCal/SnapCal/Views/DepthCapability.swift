import Foundation
import ARKit

enum DepthCapability {
    static var isLiDAREnabled: Bool {
        guard ARWorldTrackingConfiguration.isSupported else { return false }
        if #available(iOS 13.4, *) {
            let hasSceneDepth = ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
            let hasMesh = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
            return hasSceneDepth && hasMesh
        }
        return false
    }
}
