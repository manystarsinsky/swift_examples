import Cocoa
import PDFKit
import os
import UniformTypeIdentifiers

class DrawingView: NSView {
    struct DrawingPath {
        let path: NSBezierPath
        let color: NSColor
    }
    
    var paths: [DrawingPath] = []
    var currentPath: NSBezierPath?
    var currentColor: NSColor = .red
    var isUserInteractionEnabled: Bool = false

    override func hitTest(_ point: NSPoint) -> NSView? {
        return isUserInteractionEnabled ? super.hitTest(point) : nil
    }

    override func mouseDown(with event: NSEvent) {
        guard isUserInteractionEnabled else { return }
        currentPath = NSBezierPath()
        currentPath?.move(to: convert(event.locationInWindow, from: nil))
    }

    override func mouseDragged(with event: NSEvent) {
        guard isUserInteractionEnabled else { return }
        currentPath?.line(to: convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isUserInteractionEnabled else { return }
        guard let finishedPath = currentPath else { return }
        finishedPath.line(to: convert(event.locationInWindow, from: nil))
        paths.append(DrawingPath(path: finishedPath, color: currentColor))
        currentPath = nil
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        for drawingPath in paths {
            drawingPath.color.setStroke()
            drawingPath.path.stroke()
        }
        
        if let currentPath = currentPath {
            currentColor.setStroke()
            currentPath.stroke()
        }
    }

    func clear() {
        paths.removeAll()
        currentPath = nil
        needsDisplay = true
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var pdfView: PDFView!
    var drawingView: DrawingView?
    var isDrawingModeEnabled = false
    var defaultCursor: NSCursor?

    let zoomStep: CGFloat = 1.2

    let logger = Logger()

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        logger.info("Application did finish launching")

        // Calculate the center position for the window
        let screenSize = NSScreen.main?.visibleFrame ?? NSRect.zero
        let windowSize = NSSize(width: 1200, height: 800)
        let windowOrigin = NSPoint(
            x: screenSize.midX - windowSize.width / 2,
            y: screenSize.midY - windowSize.height / 2
        )

        // Create the window
        let windowRect = NSRect(origin: windowOrigin, size: windowSize)
        window = NSWindow(contentRect: windowRect, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        
        // Create a PDFView
        pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.translatesAutoresizingMaskIntoConstraints = false
        
        // Create a toolbar
        let toolbar = NSToolbar(identifier: "MainToolbar")
        toolbar.allowsUserCustomization = false
        toolbar.displayMode = .iconAndLabel
        toolbar.delegate = self
        window.toolbar = toolbar

        // Create a container view
        let containerView = NSView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        
        // Add only the PDFView to the container view
        containerView.addSubview(pdfView)
        
        // Set the container view as the window's content view
        window.contentView = containerView
        
        // Set up constraints for PDFView only
        NSLayoutConstraint.activate([
            pdfView.topAnchor.constraint(equalTo: containerView.topAnchor),
            pdfView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            pdfView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        // Show the window
        window.makeKeyAndOrderFront(nil)
        
        // Set the window's delegate to self
        window.delegate = self

        // Set up the responder chain
        window.makeFirstResponder(pdfView)
    }

    @objc func selectDocument() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false
        openPanel.allowedContentTypes = [UTType.pdf]
        
        openPanel.beginSheetModal(for: window) { response in
            if response == .OK, let url = openPanel.url {
                self.logger.info("Selected document: \(url.path)")
                self.openPDFDocument(url: url)
            }
        }
    }
    
    @objc func exit_() {
        NSApplication.shared.terminate(self)
    }

    @objc func toggleDrawingMode() {
        isDrawingModeEnabled.toggle()
        
        if drawingView == nil {
            drawingView = DrawingView(frame: pdfView.bounds)
            drawingView?.autoresizingMask = [.width, .height]
            pdfView.addSubview(drawingView!)
        }
        
        // Update drawing view's interaction mode
        drawingView?.isUserInteractionEnabled = isDrawingModeEnabled
        
        if isDrawingModeEnabled {
            // Change cursor to crosshair
            defaultCursor = NSCursor.current
            NSCursor.crosshair.set()
        } else {
            // Restore default cursor
            defaultCursor?.set()
        }
        
        // Update the cursor for the entire window
        window.invalidateCursorRects(for: window.contentView!)
    }

    @objc func changeDrawingColor(_ sender: NSColorWell) {
        drawingView?.currentColor = sender.color
    }

    @objc func clearDrawing() {
        drawingView?.clear()
    }

    func openPDFDocument(url: URL) {
        if let document = PDFDocument(url: url) {
            pdfView.document = document
            pdfView.autoScales = true
            pdfView.displayMode = .singlePageContinuous
        } else {
            let alert = NSAlert()
            alert.messageText = "Error"
            alert.informativeText = "Unable to open the PDF file."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        NSApplication.shared.terminate(self)
    }

    func windowDidUpdate(_ notification: Notification) {
        if isDrawingModeEnabled {
            NSCursor.crosshair.set()
        } else {
            defaultCursor?.set()
        }
    }
}

extension AppDelegate: NSToolbarDelegate {
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier {
        case .openDocument:
            let toolbarItem = NSToolbarItem(itemIdentifier: itemIdentifier)
            toolbarItem.label = "Open PDF"
            toolbarItem.paletteLabel = "Open PDF"
            toolbarItem.toolTip = "Open a PDF document"
            toolbarItem.image = NSImage(systemSymbolName: "doc", accessibilityDescription: "Open")
            toolbarItem.target = self
            toolbarItem.action = #selector(selectDocument)
            return toolbarItem
        case .toggleDrawing:
            let toolbarItem = NSToolbarItem(itemIdentifier: itemIdentifier)
            toolbarItem.label = "Toggle Drawing"
            toolbarItem.paletteLabel = "Toggle Drawing"
            toolbarItem.toolTip = "Toggle drawing mode"
            toolbarItem.image = NSImage(systemSymbolName: "pencil", accessibilityDescription: "Toggle Drawing")
            toolbarItem.target = self
            toolbarItem.action = #selector(toggleDrawingMode)
            return toolbarItem
        case .drawingColor:
            let toolbarItem = NSToolbarItem(itemIdentifier: itemIdentifier)
            toolbarItem.label = "Drawing Color"
            toolbarItem.paletteLabel = "Drawing Color"
            toolbarItem.toolTip = "Change drawing color"
            
            let colorWell = NSColorWell(frame: NSRect(x: 0, y: 0, width: 44, height: 24))
            colorWell.target = self
            colorWell.action = #selector(changeDrawingColor(_:))
            
            toolbarItem.view = colorWell
            return toolbarItem
        case .clearDrawing:
            let toolbarItem = NSToolbarItem(itemIdentifier: itemIdentifier)
            toolbarItem.label = "Clear Drawing"
            toolbarItem.paletteLabel = "Clear Drawing"
            toolbarItem.toolTip = "Clear all drawings"
            toolbarItem.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Clear Drawing")
            toolbarItem.target = self
            toolbarItem.action = #selector(clearDrawing)
            return toolbarItem
        default:
            return nil
        }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.openDocument, .toggleDrawing, .drawingColor, .clearDrawing]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.openDocument, .toggleDrawing, .drawingColor, .clearDrawing]
    }
}

extension NSToolbarItem.Identifier {
    static let openDocument = NSToolbarItem.Identifier("openDocument")
    static let toggleDrawing = NSToolbarItem.Identifier("toggleDrawing")
    static let drawingColor = NSToolbarItem.Identifier("drawingColor")
    static let clearDrawing = NSToolbarItem.Identifier("clearDrawing")
}

// Create and run the application
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
