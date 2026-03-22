import AppKit
import SwiftUI

struct PersistentHSplitView<Leading: View, Trailing: View>: NSViewControllerRepresentable {
    let autosaveKey: String
    let defaultTrailingFraction: CGFloat
    let minLeadingWidth: CGFloat
    let minTrailingWidth: CGFloat
    private let leading: Leading
    private let trailing: Trailing

    init(
        autosaveKey: String,
        defaultTrailingFraction: CGFloat,
        minLeadingWidth: CGFloat,
        minTrailingWidth: CGFloat,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.autosaveKey = autosaveKey
        self.defaultTrailingFraction = defaultTrailingFraction
        self.minLeadingWidth = minLeadingWidth
        self.minTrailingWidth = minTrailingWidth
        self.leading = leading()
        self.trailing = trailing()
    }

    func makeNSViewController(context: Context) -> PersistentSplitViewController {
        let controller = PersistentSplitViewController(
            autosaveKey: autosaveKey,
            defaultTrailingFraction: defaultTrailingFraction,
            minLeadingWidth: minLeadingWidth,
            minTrailingWidth: minTrailingWidth
        )
        controller.update(leading: AnyView(leading), trailing: AnyView(trailing))
        return controller
    }

    func updateNSViewController(_ controller: PersistentSplitViewController, context: Context) {
        controller.update(leading: AnyView(leading), trailing: AnyView(trailing))
    }
}

final class PersistentSplitViewController: NSViewController, NSSplitViewDelegate {
    private let autosaveKey: String
    private let defaultTrailingFraction: CGFloat
    private let minLeadingWidth: CGFloat
    private let minTrailingWidth: CGFloat
    private let splitView = NSSplitView()
    private let leadingHostingController = NSHostingController(rootView: AnyView(EmptyView()))
    private let trailingHostingController = NSHostingController(rootView: AnyView(EmptyView()))
    private var didApplyInitialPosition = false

    init(
        autosaveKey: String,
        defaultTrailingFraction: CGFloat,
        minLeadingWidth: CGFloat,
        minTrailingWidth: CGFloat
    ) {
        self.autosaveKey = autosaveKey
        self.defaultTrailingFraction = defaultTrailingFraction
        self.minLeadingWidth = minLeadingWidth
        self.minTrailingWidth = minTrailingWidth
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.delegate = self
        splitView.autoresizingMask = [.width, .height]
        splitView.frame = view.bounds
        view.addSubview(splitView)

        addChild(leadingHostingController)
        addChild(trailingHostingController)

        splitView.addArrangedSubview(leadingHostingController.view)
        splitView.addArrangedSubview(trailingHostingController.view)
    }

    override func viewDidLayout() {
        super.viewDidLayout()

        guard didApplyInitialPosition == false, splitView.bounds.width > 0 else {
            return
        }

        applyStoredOrDefaultPosition()
        didApplyInitialPosition = true
    }

    func update(leading: AnyView, trailing: AnyView) {
        leadingHostingController.rootView = leading
        trailingHostingController.rootView = trailing
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard didApplyInitialPosition else {
            return
        }

        saveCurrentFraction()
    }

    func splitView(
        _ splitView: NSSplitView,
        constrainMinCoordinate proposedMinimumPosition: CGFloat,
        ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        effectiveMinLeadingWidth
    }

    func splitView(
        _ splitView: NSSplitView,
        constrainMaxCoordinate proposedMaximumPosition: CGFloat,
        ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        splitView.bounds.width - splitView.dividerThickness - effectiveMinTrailingWidth
    }

    private var availableWidth: CGFloat {
        max(splitView.bounds.width - splitView.dividerThickness, 0)
    }

    private var effectiveMinLeadingWidth: CGFloat {
        min(minLeadingWidth, availableWidth)
    }

    private var effectiveMinTrailingWidth: CGFloat {
        min(minTrailingWidth, max(availableWidth - effectiveMinLeadingWidth, 0))
    }

    private func applyStoredOrDefaultPosition() {
        let fraction = storedTrailingFraction ?? defaultTrailingFraction
        let clampedFraction = max(0.18, min(fraction, 0.45))
        let trailingWidth = resolvedTrailingWidth(for: clampedFraction)
        let leadingWidth = max(availableWidth - trailingWidth, 0)
        splitView.setPosition(leadingWidth, ofDividerAt: 0)
        saveCurrentFraction()
    }

    private func resolvedTrailingWidth(for fraction: CGFloat) -> CGFloat {
        let desiredWidth = availableWidth * fraction
        let minimumWidth = effectiveMinTrailingWidth
        let maximumWidth = max(availableWidth - effectiveMinLeadingWidth, minimumWidth)
        return min(max(desiredWidth, minimumWidth), maximumWidth)
    }

    private var storedTrailingFraction: CGFloat? {
        let value = UserDefaults.standard.double(forKey: autosaveKey)
        guard value > 0 else {
            return nil
        }

        return CGFloat(value)
    }

    private func saveCurrentFraction() {
        guard splitView.subviews.count == 2, availableWidth > 0 else {
            return
        }

        let trailingWidth = splitView.subviews[1].frame.width
        let fraction = max(0.18, min(trailingWidth / availableWidth, 0.45))
        UserDefaults.standard.set(Double(fraction), forKey: autosaveKey)
    }
}
