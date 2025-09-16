import Foundation
import CoreGraphics
import AppKit

func log(_ message: String) {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    let timestamp = formatter.string(from: Date())
    let logMessage = "[\(timestamp)] \(message)\n"
    
    // Print to stdout
    print("[\(timestamp)] \(message)")
    
    // Log to file with rotation
    var logDir: URL
    let systemLogDir = URL(fileURLWithPath: "/Library/Logs")
    let systemLogFile = systemLogDir.appendingPathComponent("rememberwindows.log")
    
    do {
        try FileManager.default.createDirectory(at: systemLogDir, withIntermediateDirectories: true, attributes: nil)
        
        // Check write access to the specific log file
        if FileManager.default.fileExists(atPath: systemLogFile.path) {
            if FileManager.default.isWritableFile(atPath: systemLogFile.path) {
                logDir = systemLogDir
            } else {
                throw NSError(domain: "WriteAccess", code: 1, userInfo: nil)
            }
        } else {
            // Try to create the file to test write access
            try "".write(to: systemLogFile, atomically: true, encoding: .utf8)
            // Clean up the empty file
            try FileManager.default.removeItem(at: systemLogFile)
            logDir = systemLogDir
        }
    } catch {
        logDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs")
    }
    let logFile = logDir.appendingPathComponent("rememberwindows.log")
    
    do {
        // Ensure log directory exists
        try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true, attributes: nil)
        
        // Check file size and rotate if necessary
        if let attributes = try? FileManager.default.attributesOfItem(atPath: logFile.path),
           let fileSize = attributes[.size] as? UInt64,
           fileSize > 1024 * 1024 { // 1MB
            rotateLogFile(at: logFile)
        }
        
        // Append to log file
        if FileManager.default.fileExists(atPath: logFile.path) {
            let fileHandle = try FileHandle(forWritingTo: logFile)
            fileHandle.seekToEndOfFile()
            if let data = logMessage.data(using: .utf8) {
                fileHandle.write(data)
            }
            fileHandle.closeFile()
        } else {
            try logMessage.write(to: logFile, atomically: true, encoding: .utf8)
        }
    } catch {
        // If logging to file fails, just print to stderr
        fputs("Error writing to log file: \(error)\n", stderr)
    }
}

func rotateLogFile(at logFile: URL) {
    let fileManager = FileManager.default
    let maxBackups = 3
    
    // Remove oldest backup if it exists
    let oldestBackup = logFile.appendingPathExtension("\(maxBackups)")
    if fileManager.fileExists(atPath: oldestBackup.path) {
        try? fileManager.removeItem(at: oldestBackup)
    }
    
    // Shift existing backups
    for i in (1..<maxBackups).reversed() {
        let currentBackup = logFile.appendingPathExtension("\(i)")
        let nextBackup = logFile.appendingPathExtension("\(i + 1)")
        if fileManager.fileExists(atPath: currentBackup.path) {
            try? fileManager.moveItem(at: currentBackup, to: nextBackup)
        }
    }
    
    // Move current log to .1
    let firstBackup = logFile.appendingPathExtension("1")
    try? fileManager.moveItem(at: logFile, to: firstBackup)
}

struct WindowInfo: Codable {
    let appName: String
    let windowId: Int
    let pid: pid_t
    let position: [Double]
    let size: [Double]
    let title: String?
}

func captureWindowData(filename: String) {
    // Get all on-screen windows
    guard let windowList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as NSArray? else {
        log("Error: Unable to retrieve window list")
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
        log("Saving window position for \(appName): (\(x), \(y))")
    }

    // Save to JSON file
    do {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let jsonData = try encoder.encode(windowData)
        try jsonData.write(to: URL(fileURLWithPath: filename))
        log("Window data saved to \(filename)")
    } catch {
        log("Error saving to \(filename): \(error)")
        exit(1)
    }
}

func repositionWindows(filename: String) {
    // Read JSON file
    do {
        let jsonData = try Data(contentsOf: URL(fileURLWithPath: filename))
        let windowData = try JSONDecoder().decode([WindowInfo].self, from: jsonData)

        // Get current on-screen windows for ID matching
        guard let currentWindowList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as NSArray? else {
            log("Error: Unable to retrieve current window list")
            return
        }

        // Structure to track windows that need repositioning
        struct WindowToReposition {
            let windowInfo: WindowInfo
            let axWindow: AXUIElement
            let targetPosition: NSPoint
            let targetSize: NSSize
        }
        
        var windowsToReposition: [WindowToReposition] = []
        
        // First pass: collect all windows that need repositioning
        for windowInfo in windowData {
            let appRef = AXUIElementCreateApplication(windowInfo.pid)
            var windowList: CFTypeRef?
            var error = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowList)

            if error != .success || windowList == nil {
                log("Error accessing windows for \(windowInfo.appName) (PID: \(windowInfo.pid)): \(error)")
                continue
            }

            guard let windows = windowList as? [AXUIElement] else {
                log("Error: Could not cast window list for \(windowInfo.appName)")
                continue
            }

            // Try to find the target window by window ID first
            var targetWindow: AXUIElement?

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
                        }
                    }
                }
            }

            if let targetWindow = targetWindow {
                let targetPosition = NSPoint(x: windowInfo.position[0], y: windowInfo.position[1])
                let targetSize = NSSize(width: windowInfo.size[0], height: windowInfo.size[1])
                windowsToReposition.append(WindowToReposition(
                    windowInfo: windowInfo,
                    axWindow: targetWindow,
                    targetPosition: targetPosition,
                    targetSize: targetSize
                ))
            } else {
                log("No matching window found for \(windowInfo.appName) (PID: \(windowInfo.pid))")
                log("  Title: \(windowInfo.title ?? "N/A")")
                if titleMatchAttempted {
                    log("  Title Match Failed: No window with title '\(windowInfo.title ?? "N/A")' found")
                }
            }
        }
        
        // Batch repositioning logic
        let maxTotalTime: TimeInterval = 10.0 // 10 seconds
        let delayBetweenAttempts: TimeInterval = 0.25 // 250ms
        let startTime = Date()
        var attempt = 0
        
        log("Starting batch repositioning of \(windowsToReposition.count) windows")
        
        while !windowsToReposition.isEmpty && Date().timeIntervalSince(startTime) < maxTotalTime {
            attempt += 1
            var remainingWindows: [WindowToReposition] = []
            
            log("Attempt \(attempt): repositioning \(windowsToReposition.count) windows")
            
            // Move all windows in this batch
            for windowToReposition in windowsToReposition {
                let windowInfo = windowToReposition.windowInfo
                let targetWindow = windowToReposition.axWindow
                
                // Set position
                var position = windowToReposition.targetPosition
                let positionValue = AXValueCreate(.cgPoint, &position)
                if positionValue == nil {
                    log("Error creating position value for window in \(windowInfo.appName) (PID: \(windowInfo.pid))")
                    continue
                }
                let error = AXUIElementSetAttributeValue(targetWindow, kAXPositionAttribute as CFString, positionValue!)
                if error != .success {
                    log("Error setting position for window in \(windowInfo.appName) (PID: \(windowInfo.pid)): \(error)")
                    continue
                }

                // Set size
                var size = windowToReposition.targetSize
                let sizeValue = AXValueCreate(.cgSize, &size)
                if sizeValue == nil {
                    log("Error creating size value for window in \(windowInfo.appName) (PID: \(windowInfo.pid))")
                    continue
                }
                let sizeError = AXUIElementSetAttributeValue(targetWindow, kAXSizeAttribute as CFString, sizeValue!)
                if sizeError != .success {
                    log("Error setting size for window in \(windowInfo.appName) (PID: \(windowInfo.pid)): \(sizeError)")
                    continue
                }
            }
            
            // Wait for changes to take effect
            if !windowsToReposition.isEmpty {
                Thread.sleep(forTimeInterval: delayBetweenAttempts)
            }
            
            // Check which windows still need repositioning
            for windowToReposition in windowsToReposition {
                let windowInfo = windowToReposition.windowInfo
                let targetWindow = windowToReposition.axWindow
                
                // Check current position
                var currentPositionRef: CFTypeRef?
                AXUIElementCopyAttributeValue(targetWindow, kAXPositionAttribute as CFString, &currentPositionRef)
                let currentPosition = currentPositionRef.flatMap { posRef -> NSPoint? in
                    guard CFGetTypeID(posRef) == AXValueGetTypeID() else { return nil }
                    var point = NSPoint()
                    AXValueGetValue(posRef as! AXValue, .cgPoint, &point)
                    return point
                }
                
                if let currentPos = currentPosition {
                    let targetPos = windowToReposition.targetPosition
                    let tolerance: CGFloat = 5.0 // Allow small differences
                    if abs(currentPos.x - targetPos.x) <= tolerance && abs(currentPos.y - targetPos.y) <= tolerance {
                        // Window is correctly positioned
                        log("Window for \(windowInfo.appName) successfully positioned")
                    } else {
                        // Window still needs repositioning
                        remainingWindows.append(windowToReposition)
                        log("Window for \(windowInfo.appName) still at (\(currentPos.x), \(currentPos.y)), target (\(targetPos.x), \(targetPos.y))")
                    }
                } else {
                    // Could not get current position, keep trying
                    remainingWindows.append(windowToReposition)
                }
            }
            
            windowsToReposition = remainingWindows
        }
        
        if windowsToReposition.isEmpty {
            log("All windows successfully repositioned after \(attempt) attempts")
        } else {
            log("Failed to reposition \(windowsToReposition.count) windows after \(attempt) attempts within \(maxTotalTime) seconds")
        }
        
        log("Window positions restored from \(filename)")
    } catch {
        log("Error reading or processing \(filename): \(error)")
        exit(1)
    }
}

func monitorLockUnlock(filename: String) {
    // Set up notification center for distributed notifications
    let notificationCenter = DistributedNotificationCenter.default()

    // // Observe screensaver will start (just before potential lock)
    // notificationCenter.addObserver(
    //     forName: NSNotification.Name("com.apple.screensaver.willstart"),
    //     object: nil,
    //     queue: .main
    // ) { _ in
    //     print("Screensaver will start")
    //     captureWindowData(filename: filename)
    // }

    // // Observe system wake notification
    // notificationCenter.addObserver(
    //     forName: NSWorkspace.didWakeNotification,
    //     object: nil,
    //     queue: .main
    // ) { _ in
    //     print("System woke up")
    //     repositionWindows(filename: filename)
    // }

    // Observe screensaver start (lock) notification
    notificationCenter.addObserver(
        forName: NSNotification.Name("com.apple.screenIsLocked"),
        object: nil,
        queue: .main
    ) { _ in
        log("Screen locked")
        captureWindowData(filename: filename)
    }

    // Observe screensaver stop (unlock) notification
    notificationCenter.addObserver(
        forName: NSNotification.Name("com.apple.screenIsUnlocked"),
        object: nil,
        queue: .main
    ) { _ in
        log("Screen unlocked")
        repositionWindows(filename: filename)
    }

    // // Observe system sleep notification
    // notificationCenter.addObserver(
    //     forName: NSWorkspace.willSleepNotification,
    //     object: nil,
    //     queue: .main
    // ) { _ in
    //     print("System will sleep")
    // }

    // // Observe system wake notification
    // notificationCenter.addObserver(
    //     forName: NSWorkspace.didWakeNotification,
    //     object: nil,
    //     queue: .main
    // ) { _ in
    //     print("System woke up")
    // }

    RunLoop.main.run()
}

func getFilePath(filename: String?) -> String {
    if let filename = filename, !filename.isEmpty {
        return filename
    } else {
        let tempDir = NSTemporaryDirectory()
        let tempFileName = "window_positions_\(UUID().uuidString).json"
        let tempFilePath = (tempDir as NSString).appendingPathComponent(tempFileName)
        return tempFilePath
    }
}

func main() {
    guard CommandLine.arguments.count >= 2 else {
        log("Usage: ./windowfreezer [capture|reposition|monitor] [<filename>]")
        exit(1)
    }

    let command = CommandLine.arguments[1]
    let filename = getFilePath(filename: CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : nil)
    log("Using file: \(filename)")

    switch command {
    case "capture":
        captureWindowData(filename: filename)
    case "reposition":
        repositionWindows(filename: filename)
    case "monitor":
        log("Monitoring screen lock/unlock and sleep/wake events...")
        monitorLockUnlock(filename: filename)
    default:
        log("Invalid command. Use 'capture', 'reposition' or 'monitor'.")
        exit(1)
    }
}

main()