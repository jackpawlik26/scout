// Mouse events for screenshots. Usage: mouse drag x1 y1 x2 y2 | click x y | rightclick x y | move x y   (screen points)
import CoreGraphics
import Foundation

let a = CommandLine.arguments
func post(_ type: CGEventType, _ x: Double, _ y: Double) {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left)?.post(tap: .cghidEventTap)
}
let n = a.dropFirst(2).compactMap(Double.init)
switch a[1] {
case "drag":
    post(.mouseMoved, n[0], n[1]); usleep(150_000)
    post(.leftMouseDown, n[0], n[1]); usleep(150_000)
    for i in 1...20 {
        let t = Double(i) / 20
        post(.leftMouseDragged, n[0] + (n[2] - n[0]) * t, n[1] + (n[3] - n[1]) * t); usleep(20_000)
    }
    usleep(100_000); post(.leftMouseUp, n[2], n[3])
case "click":
    post(.mouseMoved, n[0], n[1]); usleep(100_000)
    post(.leftMouseDown, n[0], n[1]); usleep(60_000); post(.leftMouseUp, n[0], n[1])
case "rightclick":
    post(.mouseMoved, n[0], n[1]); usleep(100_000)
    CGEvent(mouseEventSource: nil, mouseType: .rightMouseDown, mouseCursorPosition: CGPoint(x: n[0], y: n[1]), mouseButton: .right)?.post(tap: .cghidEventTap)
    usleep(60_000)
    CGEvent(mouseEventSource: nil, mouseType: .rightMouseUp, mouseCursorPosition: CGPoint(x: n[0], y: n[1]), mouseButton: .right)?.post(tap: .cghidEventTap)
default:
    post(.mouseMoved, n[0], n[1])
}
