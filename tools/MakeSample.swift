// Generates a short, license-free sample clip (animated gradient) so the
// sandboxed / App Store build has readable bundled content and we can
// test the wallpaper window under App Sandbox.
// Run: swift tools/MakeSample.swift <output.mp4>
import AVFoundation
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1
              ? CommandLine.arguments[1] : "Sample.mp4")
try? FileManager.default.removeItem(at: out)

let W = 960, H = 540, FPS: Int32 = 30, SECS = 4
let writer = try! AVAssetWriter(outputURL: out, fileType: .mp4)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: W, AVVideoHeightKey: H,
])
input.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(
    assetWriterInput: input,
    sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
        kCVPixelBufferWidthKey as String: W,
        kCVPixelBufferHeightKey as String: H,
    ])
writer.add(input)
writer.startWriting()
writer.startSession(atSourceTime: .zero)

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let total = Int(FPS) * SECS
for i in 0 ..< total {
    while !input.isReadyForMoreMediaData { usleep(5_000) }
    var pb: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb)
    guard let buf = pb else { continue }
    CVPixelBufferLockBaseAddress(buf, [])
    let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buf),
                        width: W, height: H, bitsPerComponent: 8,
                        bytesPerRow: CVPixelBufferGetBytesPerRow(buf),
                        space: cs,
                        bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)!
    let t = Double(i) / Double(total)
    let g = CGGradient(colorsSpace: cs, colors: [
        NSColor(calibratedHue: CGFloat(t),       saturation: 0.55, brightness: 0.35, alpha: 1).cgColor,
        NSColor(calibratedHue: CGFloat(1 - t),   saturation: 0.65, brightness: 0.70, alpha: 1).cgColor,
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: W, y: H), options: [])
    CVPixelBufferUnlockBaseAddress(buf, [])
    adaptor.append(buf, withPresentationTime:
        CMTime(value: CMTimeValue(i), timescale: FPS))
}

input.markAsFinished()
let sem = DispatchSemaphore(value: 0)
writer.finishWriting { sem.signal() }
sem.wait()
print(writer.status == .completed ? "wrote \(out.path)" : "FAILED: \(String(describing: writer.error))")
