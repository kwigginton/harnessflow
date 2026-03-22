import Foundation
#if canImport(DeveloperToolsSupport)
import DeveloperToolsSupport
#endif

#if SWIFT_PACKAGE
private let resourceBundle = Foundation.Bundle.module
#else
private class ResourceBundleClass {}
private let resourceBundle = Foundation.Bundle(for: ResourceBundleClass.self)
#endif

// MARK: - Color Symbols -

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension DeveloperToolsSupport.ColorResource {

}

// MARK: - Image Symbols -

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension DeveloperToolsSupport.ImageResource {

    /// The "ImplementPhase" asset catalog image resource.
    static let implementPhase = DeveloperToolsSupport.ImageResource(name: "ImplementPhase", bundle: resourceBundle)

    /// The "PlanPhase" asset catalog image resource.
    static let planPhase = DeveloperToolsSupport.ImageResource(name: "PlanPhase", bundle: resourceBundle)

    /// The "ResearchPhase" asset catalog image resource.
    static let researchPhase = DeveloperToolsSupport.ImageResource(name: "ResearchPhase", bundle: resourceBundle)

    /// The "ReviewPhase" asset catalog image resource.
    static let reviewPhase = DeveloperToolsSupport.ImageResource(name: "ReviewPhase", bundle: resourceBundle)

}

