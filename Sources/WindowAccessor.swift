import AppKit
import SwiftUI

@MainActor
struct WindowAccessor: NSViewRepresentable {
    enum Delivery {
        case immediate
        case deferred
    }

    let onWindow: @MainActor (NSWindow) -> Void
    let dedupeByWindow: Bool
    let refreshID: AnyHashable?
    let delivery: Delivery

    init(
        dedupeByWindow: Bool = true,
        refreshID: AnyHashable? = nil,
        delivery: Delivery = .immediate,
        onWindow: @escaping @MainActor (NSWindow) -> Void
    ) {
        self.onWindow = onWindow
        self.dedupeByWindow = dedupeByWindow
        self.refreshID = refreshID
        self.delivery = delivery
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WindowObservingView {
        let view = WindowObservingView()
        installWindowHandler(
            on: view,
            coordinator: context.coordinator
        )
        return view
    }

    func updateNSView(_ nsView: WindowObservingView, context: Context) {
        installWindowHandler(
            on: nsView,
            coordinator: context.coordinator
        )
        if let window = nsView.window {
            nsView.onWindow?(window)
        }
    }

    private func installWindowHandler(
        on view: WindowObservingView,
        coordinator: Coordinator
    ) {
        let handler = onWindow
        let shouldDedupeByWindow = dedupeByWindow
        let refreshID = refreshID
        let delivery = delivery
        view.onWindow = { window in
            coordinator.invoke(
                window: window,
                dedupeByWindow: shouldDedupeByWindow,
                refreshID: refreshID,
                delivery: delivery,
                handler: handler
            )
        }
    }
}

extension WindowAccessor {
    @MainActor
    final class Coordinator {
        private weak var lastWindow: NSWindow?
        private var lastRefreshID: AnyHashable?
        private var pendingGeneration: UInt64 = 0

        func invoke(
            window: NSWindow,
            dedupeByWindow: Bool,
            refreshID: AnyHashable?,
            delivery: Delivery,
            handler: @escaping @MainActor (NSWindow) -> Void
        ) {
            if dedupeByWindow, lastWindow === window, lastRefreshID == refreshID {
                return
            }

            lastWindow = window
            lastRefreshID = refreshID

            switch delivery {
            case .immediate:
                handler(window)
            case .deferred:
                pendingGeneration &+= 1
                let generation = pendingGeneration
                Task { @MainActor [weak self, weak window] in
                    guard let self,
                          self.pendingGeneration == generation,
                          let window else {
                        return
                    }
                    handler(window)
                }
            }
        }
    }
}

@MainActor
final class WindowObservingView: NSView {
    var onWindow: (@MainActor (NSWindow) -> Void)?

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if let newWindow {
            onWindow?(newWindow)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            onWindow?(window)
        }
    }
}
