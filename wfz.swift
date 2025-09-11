import Foundation
import CoreGraphics
import AppKit

struct WindowInfo: Codable {
    let appName: String
    let windowId: Int
    let pid: pid_t
    let position: [Double]
    let size: [Double]
    let title: String?
}

func getWindowData(filename: String) {
    // Get all on-screen windows
    guard let windowList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as NSArray? else {
        print("Error: Unable to retrieve window list")
        exit(1)
    }

    var windowData: [WindowInfo] = []

    for window in windowList {
        guard let windowDict = window as? [String: Any],
              let windowId = windowDict[kCGWindowNumber as String] as? Int,
              let pid = windowDict[kCGWindowOwnerPID as String] as? pid_t,
              let appName = windowDict[kCGWindowOwnerName as String] as? String,
              let boundsDict = windowDict[kCGWindowBounds as String] as? [String: Any],
              let x = boundsDict["X"] as? Double,
              let y = boundsDict["Y"] as? Double,
              let width = boundsDict["Width"] as? Double,
              let height = boundsDict["Height"] as? Double else {
            continue
        }

        // Skip windows that are not regular application windows (e.g., menu bar, dock)
        if windowDict[kCGWindowLayer as String] as? Int != 0 {
            continue
        }

        // Get window title
        let title = windowDict[kCGWindowName as String] as? String

        let windowInfo = WindowInfo(
            appName: appName,
            windowId: windowId,
            pid: pid,
            position: [x, y],
            size: [width, height],
            title: title
        )
        windowData.append(windowInfo)

        // Print position when saving
        print("Saving window position:")
        print("  App: \(appName)")
        print("  Window ID: \(windowId)")
        print("  Title: \(title ?? "N/A")")
        print("  Position: (\(x), \(y))")
        print("  Size: (\(width), \(height))")
        print("---")
    }

    // Save to JSON file
    do {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let jsonData = try encoder.encode(windowData)
        try jsonData.write(to: URL(fileURLWithPath: filename))
        print("Window data saved to \(filename)")
    } catch {
        print("Error saving to \(filename): \(error)")
        exit(1)
    }
}

func setWindowData(filename: String) {
    // Read JSON file
    do {
        let jsonData = try Data(contentsOf: URL(fileURLWithPath: filename))
        let windowData = try JSONDecoder().decode([WindowInfo].self, from: jsonData)

        for windowInfo in windowData {
            let appRef = AXUIElementCreateApplication(windowInfo.pid)
            var windowList: CFTypeRef?
            var error = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowList)

            if error != .success || windowList == nil {
                print("Error accessing windows for \(windowInfo.appName) (PID: \(windowInfo.pid)): \(error)")
                continue
            }

            guard let windows = windowList as? [AXUIElement] else {
                print("Error: Could not cast window list for \(windowInfo.appName)")
                continue
            }

            // Try to find the target window by title, or fall back to position/size
            var targetWindow: AXUIElement?
            var bestMatchScore: Double = Double.infinity
            let targetPos = windowInfo.position
            let targetSize = windowInfo.size

            for window in windows {
                // Get window title
                var windowTitle: CFTypeRef?
                error = AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &windowTitle)
                let currentTitle = windowTitle as? String

                // Get current window position and size for fallback matching
                var positionRef: CFTypeRef?
                var sizeRef: CFTypeRef?
                AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef)
                AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef)
                let currentPos = positionRef.flatMap { posRef -> NSPoint? in
                    guard CFGetTypeID(posRef) == AXValueGetTypeID() else { return nil }
                    var point = NSPoint()
                    AXValueGetValue(posRef as! AXValue, .cgPoint, &point)
                    return point
                }
                let currentSize = sizeRef.flatMap { sizeRef -> NSSize? in
                    guard CFGetTypeID(sizeRef) == AXValueGetTypeID() else { return nil }
                    var size = NSSize()
                    AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
                    return size
                }

                // Match by title if available
                if let savedTitle = windowInfo.title, let currentTitle = currentTitle, savedTitle == currentTitle {
                    targetWindow = window
                    break
                }

                // Fallback: Match by position and size proximity
                if let currentPos = currentPos, let currentSize = currentSize {
                    let posDiff = pow(currentPos.x - targetPos[0], 2) + pow(currentPos.y - targetPos[1], 2)
                    let sizeDiff = pow(currentSize.width - targetSize[0], 2) + pow(currentSize.height - targetSize[1], 2)
                    let score = posDiff + sizeDiff
                    if score < bestMatchScore {
                        bestMatchScore = score
                        targetWindow = window
                    }
                }
            }

            if let targetWindow = targetWindow {
                // Get current position before moving
                var currentPositionRef: CFTypeRef?
                AXUIElementCopyAttributeValue(targetWindow, kAXPositionAttribute as CFString, &currentPositionRef)
                let currentPosition = currentPositionRef.flatMap { posRef -> NSPoint? in
                    guard CFGetTypeID(posRef) == AXValueGetTypeID() else { return nil }
                    var point = NSPoint()
                    AXValueGetValue(posRef as! AXValue, .cgPoint, &point)
                    return point
                }

                // Print debugging information
                print("Restoring window for \(windowInfo.appName) (PID: \(windowInfo.pid)):")
                print("  Title: \(windowInfo.title ?? "N/A")")
                print("  Current Position: \(currentPosition.map { "(\($0.x), \($0.y))" } ?? "Unknown")")
                print("  Target Position: (\(windowInfo.position[0]), \(windowInfo.position[1]))")
                print("  Target Size: (\(windowInfo.size[0]), \(windowInfo.size[1]))")

                // Set position
                var position = NSPoint(x: windowInfo.position[0], y: windowInfo.position[1])
                let positionValue = AXValueCreate(.cgPoint, &position)
                if positionValue == nil {
                    print("Error creating position value for window in \(windowInfo.appName) (PID: \(windowInfo.pid))")
                    continue
                }
                error = AXUIElementSetAttributeValue(targetWindow, kAXPositionAttribute as CFString, positionValue!)
                if error != .success {
                    print("Error setting position for window in \(windowInfo.appName) (PID: \(windowInfo.pid)): \(error)")
                }

                // Set size
                var size = NSSize(width: windowInfo.size[0], height: windowInfo.size[1])
                let sizeValue = AXValueCreate(.cgSize, &size)
                if sizeValue == nil {
                    print("Error creating size value for window in \(windowInfo.appName) (PID: \(windowInfo.pid))")
                    continue
                }
                error = AXUIElementSetAttributeValue(targetWindow, kAXSizeAttribute as CFString, sizeValue!)
                if error != .success {
                    print("Error setting size for window in \(windowInfo.appName) (PID: \(windowInfo.pid)): \(error)")
                }

                // Get and print position after moving
                var newPositionRef: CFTypeRef?
                AXUIElementCopyAttributeValue(targetWindow, kAXPositionAttribute as CFString, &newPositionRef)
                let newPosition = newPositionRef.flatMap { posRef -> NSPoint? in
                    guard CFGetTypeID(posRef) == AXValueGetTypeID() else { return nil }
                    var point = NSPoint()
                    AXValueGetValue(posRef as! AXValue, .cgPoint, &point)
                    return point
                }
                print("  New Position: \(newPosition.map { "(\($0.x), \($0.y))" } ?? "Unknown")")
                print("---")
            } else {
                print("No matching window found for \(windowInfo.appName) (PID: \(windowInfo.pid))")
                print("---")
            }
        }
        print("Window positions restored from \(filename)")
    } catch {
        print("Error reading or processing \(filename): \(error)")
        exit(1)
    }
}

func main() {
    guard CommandLine.arguments.count == 3 else {
        print("Usage: ./windowfreezer [get|set] <filename>")
        exit(1)
    }

    let command = CommandLine.arguments[1]
    let filename = CommandLine.arguments[2]

    switch command {
    case "get":
        getWindowData(filename: filename)
    case "set":
        setWindowData(filename: filename)
    default:
        print("Invalid command. Use 'get' or 'set'.")
        exit(1)
    }
}

main()