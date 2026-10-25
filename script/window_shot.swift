// Captures the frontmost window of a process by name: swift window_shot.swift DysonBar out.png
import CoreGraphics
import Foundation

let args = CommandLine.arguments
let owner = args[1]
let output = args[2]
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as! [[String: Any]]
guard let window = list.first(where: { ($0[kCGWindowOwnerName as String] as? String) == owner && ($0[kCGWindowLayer as String] as? Int) == 0 }),
  let id = window[kCGWindowNumber as String] as? Int
else { print("no window"); exit(1) }
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
task.arguments = ["-x", "-o", "-l", "\(id)", output]
try task.run()
task.waitUntilExit()
