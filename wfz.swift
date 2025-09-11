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

        // Get window title using Accessibility API
        var title: String?
        let appRef = AXUIElementCreateApplication(pid)
        var windowListRef: CFTypeRef?
        var error = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowListRef)
        
        if error == .success, let axWindows = windowListRef as? [AXUIElement] {
            var bestMatchScore: Double = Double.infinity
            var bestMatchTitle: String?
            
            for axWindow in axWindows {
                // Get window title
                var windowTitle: CFTypeRef?
                error = AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &windowTitle)
                let axTitle = windowTitle as? String
                
                // Get Accessibility window position and size for matching
                var axPositionRef: CFTypeRef?
                var axSizeRef: CFTypeRef?
                AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &axPositionRef)
                AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &axSizeRef)
                
                let axPosition = axPositionRef.flatMap { posRef -> NSPoint? in
                    guard CFGetTypeID(posRef) == AXValueGetTypeID() else { return nil }
                    var point = NSPoint()
                    AXValueGetValue(posRef as! AXValue, .cgPoint, &point)
                    return point
                }
                let axSize = axSizeRef.flatMap { sizeRef -> NSSize? in
                    guard CFGetTypeID(sizeRef) == AXValueGetTypeID() else { return nil }
                    var size = NSSize()
                    AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
                    return size
                }
                
                // Match by position and size proximity
                if let axPos = axPosition, let axSize = axSize {
                    let posDiff = pow(axPos.x - x, 2) + pow(axPos.y - y, 2)
                    let sizeDiff = pow(axSize.width - width, 2) + pow(axSize.height - height, 2)
                    let score = posDiff + sizeDiff
                    if score < bestMatchScore {
                        bestMatchScore = score
                        bestMatchTitle = axTitle?.isEmpty == false ? axTitle : nil
                    }
                }
            }
            title = bestMatchTitle
        }

        let windowInfo = WindowInfo(
            appName: appName,
            windowId: windowId,
            pid: pid,
            position: [x, y],
            size: [width, height],
            title: title
        )
        windowData.append(windowInfo)

        // Print position and title when saving
        print("Saving window position:")
        print("  App: \(appName)")
        print("  Title: \(title ?? "N/A")")
        print("  Position: (\(x), \(y))")
        print("  Title Saved: \(title != nil && !title!.isEmpty ? "Yes" : "No")")
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

        // Get current on-screen windows for ID matching
        guard let currentWindowList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as NSArray? else {
            print("Error: Unable to retrieve current window list")
            return
        }

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

            // Try to find the target window by window ID first
            var targetWindow: AXUIElement?
            var matchType = "None"

            // Look for window with matching windowId in currentWindowList
            var cgWindowFound = false
            var cgPosition: NSPoint?
            var cgSize: NSSize?
            for currentWindow in currentWindowList {
                guard let windowDict = currentWindow as? [String: Any],
                      let currentWindowId = windowDict[kCGWindowNumber as String] as? Int,
                      currentWindowId == windowInfo.windowId,
                      let currentPid = windowDict[kCGWindowOwnerPID as String] as? pid_t,
                      currentPid == windowInfo.pid,
                      let boundsDict = windowDict[kCGWindowBounds as String] as? [String: Any],
                      let x = boundsDict["X"] as? Double,
                      let y = boundsDict["Y"] as? Double,
                      let width = boundsDict["Width"] as? Double,
                      let height = boundsDict["Height"] as? Double else {
                    continue
                }
                cgWindowFound = true
                cgPosition = NSPoint(x: x, y: y)
                cgSize = NSSize(width: width, height: height)
                break
            }

            if cgWindowFound, let cgPos = cgPosition, let cgSize = cgSize {
                // Match CG window to Accessibility window by position/size proximity
                var bestMatchScore: Double = Double.infinity
                for window in windows {
                    var positionRef: CFTypeRef?
                    var sizeRef: CFTypeRef?
                    AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef)
                    AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef)
                    let axPosition = positionRef.flatMap { posRef -> NSPoint? in
                        guard CFGetTypeID(posRef) == AXValueGetTypeID() else { return nil }
                        var point = NSPoint()
                        AXValueGetValue(posRef as! AXValue, .cgPoint, &point)
                        return point
                    }
                    let axSize = sizeRef.flatMap { sizeRef -> NSSize? in
                        guard CFGetTypeID(sizeRef) == AXValueGetTypeID() else { return nil }
                        var size = NSSize()
                        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
                        return size
                    }
                    if let axPos = axPosition, let axSize = axSize {
                        let posDiff = pow(axPos.x - cgPos.x, 2) + pow(axPos.y - cgPos.y, 2)
                        let sizeDiff = pow(axSize.width - cgSize.width, 2) + pow(axSize.height - cgSize.height, 2)
                        let score = posDiff + sizeDiff
                        if score < bestMatchScore {
                            bestMatchScore = score
                            targetWindow = window
                            matchType = "WindowID"
                        }
                    }
                }
            }

            // Fallback to title matching if no window ID match
            var titleMatchAttempted = false
            if targetWindow == nil, let savedTitle = windowInfo.title, !savedTitle.isEmpty {
                titleMatchAttempted = true
                for window in windows {
                    var windowTitle: CFTypeRef?
                    error = AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &windowTitle)
                    let currentTitle = windowTitle as? String
                    if let currentTitle = currentTitle, !currentTitle.isEmpty, savedTitle == currentTitle {
                        targetWindow = window
                        matchType = "Title"
                        break
                    }
                }
            }

            // Fallback to position/size matching if no title match
            if targetWindow == nil {
                var bestMatchScore: Double = Double.infinity
                let targetPos = windowInfo.position
                let targetSize = windowInfo.size
                for window in windows {
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
                    if let currentPos = currentPos, let currentSize = currentSize {
                        let posDiff = pow(currentPos.x - targetPos[0], 2) + pow(currentPos.y - targetPos[1], 2)
                        let sizeDiff = pow(currentSize.width - targetSize[0], 2) + pow(currentSize.height - targetSize[1], 2)
                        let score = posDiff + sizeDiff
                        if score < bestMatchScore {
                            bestMatchScore = score
                            targetWindow = window
                            matchType = "Position/Size"
                        }
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

                // Get current title for logging
                var currentTitleRef: CFTypeRef?
                AXUIElementCopyAttributeValue(targetWindow, kAXTitleAttribute as CFString, &currentTitleRef)
                let currentTitle = currentTitleRef as? String

                // Print debugging information
                print("Restoring window for \(windowInfo.appName) (PID: \(windowInfo.pid)):")
                print("  Title: \(windowInfo.title ?? "N/A")")
                print("  Current Window Title: \(currentTitle ?? "N/A")")
                print("  Match Type: \(matchType)")
                if titleMatchAttempted && matchType != "Title" {
                    print("  Title Match Failed: No window with title '\(windowInfo.title ?? "N/A")' found")
                }
                print("  Current Position: \(currentPosition.map { "(\($0.x), \($0.y))" } ?? "Unknown")")
                print("  Target Position: (\(windowInfo.position[0]), \(windowInfo.position[1]))")

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
                print("  Title: \(windowInfo.title ?? "N/A")")
                if titleMatchAttempted {
                    print("  Title Match Failed: No window with title '\(windowInfo.title ?? "N/A")' found")
                }
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