import SwiftUI
import UIKit

@objc class SwiftViewFactory: NSObject {
    @objc static func createMainView(onSelectVideo: @escaping () -> Void) -> UIViewController {
        let mainView = MainView(onSelectVideo: onSelectVideo)
        let hostingController = UIHostingController(rootView: mainView)
        hostingController.view.backgroundColor = UIColor.black
        return hostingController
    }
}
