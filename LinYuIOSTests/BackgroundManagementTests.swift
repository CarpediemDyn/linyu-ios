import CoreImage
import ImageIO
import MetalKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import LinYuIOS

/// Local synthetic images only. These tests never access accounts, BLE or campus services.
@MainActor final class BackgroundManagementTests: XCTestCase {
    private struct Fixture {
        let defaults: UserDefaults
        let directory: URL
        let preferences: OriginalPreferences
    }

    private func fixture(seed: (UserDefaults, URL) throws -> Void = { _, _ in }) throws -> Fixture {
        let name = "BackgroundTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: directory)
        }
        try seed(defaults, directory)
        return Fixture(defaults: defaults, directory: directory,
                       preferences: OriginalPreferences(defaults: defaults, backgroundDirectory: directory))
    }

    private func source(_ color: UIColor, in directory: URL, size: CGSize = CGSize(width: 64, height: 48), jpeg: Bool = false) throws -> URL {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            color.setFill(); context.fill(CGRect(origin: .zero, size: size))
        }
        let url = directory.appendingPathComponent("fixture-\(UUID().uuidString)." + (jpeg ? "jpg" : "png"))
        try XCTUnwrap(jpeg ? image.jpegData(compressionQuality: 1) : image.pngData()).write(to: url)
        return url
    }

    private func install(_ url: URL, scope: BackgroundScope, in prefs: OriginalPreferences) async {
        let handle = prefs.beginBackgroundImport(scope: scope) { url }
        await handle.completion.value
        XCTAssertNil(prefs.backgroundImports[scope])
        XCTAssertTrue(prefs.configuration(for: scope).enabled)
    }

    func testBothScopesImportPersistAndRestoreIndependently() async throws {
        let f = try fixture()
        await install(try source(.red, in: f.directory), scope: .home, in: f.preferences)
        f.preferences.backgroundBinding(\.opacity, scope: .home).wrappedValue = 0.3
        await install(try source(.blue, in: f.directory, jpeg: true), scope: .shower, in: f.preferences)
        f.preferences.backgroundBinding(\.brightness, scope: .shower).wrappedValue = 1.4
        let restored = OriginalPreferences(defaults: f.defaults, backgroundDirectory: f.directory)
        XCTAssertEqual(restored.homeBackgroundConfig, f.preferences.homeBackgroundConfig)
        XCTAssertEqual(restored.showerBackgroundConfig, f.preferences.showerBackgroundConfig)
        XCTAssertNotEqual(restored.homeBackground, restored.showerBackground)
        XCTAssertNotEqual(restored.homeThemeRGB, restored.showerThemeRGB)
    }

    func testRapidScopeSwitchDoesNotWriteEitherConfiguration() throws {
        let f = try fixture()
        f.preferences.opacity = 0.3; f.preferences.blur = 9; f.preferences.brightness = 0.7
        f.preferences.backgroundSelection = .shower
        f.preferences.opacity = 0.9; f.preferences.blur = 2; f.preferences.brightness = 1.4
        let home = f.preferences.homeBackgroundConfig, shower = f.preferences.showerBackgroundConfig
        for _ in 0..<100 { f.preferences.backgroundSelection = .home; f.preferences.backgroundSelection = .shower }
        XCTAssertEqual(f.preferences.homeBackgroundConfig, home)
        XCTAssertEqual(f.preferences.showerBackgroundConfig, shower)
        let restored = OriginalPreferences(defaults: f.defaults, backgroundDirectory: f.directory)
        XCTAssertEqual(restored.backgroundSelection, .shower)
    }

    func testSliderBindingRetainsItsScopeAfterSelectionChanges() throws {
        let f = try fixture()
        let binding = f.preferences.backgroundBinding(\.blur, scope: .home)
        f.preferences.backgroundSelection = .shower
        binding.wrappedValue = 15
        XCTAssertEqual(f.preferences.homeBackgroundConfig.blur, 15)
        XCTAssertEqual(f.preferences.showerBackgroundConfig.blur, 0)
    }

    func testDelayedPhotoLoadKeepsScopeCapturedBeforeSelectionChanges() async throws {
        let f = try fixture(), gate = Gate()
        let url = try source(.red, in: f.directory)
        let handle = f.preferences.beginBackgroundImport(scope: .home) { await gate.load() }
        await fulfillment(of: [gate.entered], timeout: 5)
        f.preferences.backgroundSelection = .shower
        gate.resume(url)
        await handle.completion.value
        XCTAssertTrue(f.preferences.homeBackgroundConfig.enabled)
        XCTAssertFalse(f.preferences.showerBackgroundConfig.enabled)
    }

    func testLateOldImportCannotReplaceNewImage() async throws {
        let f = try fixture(), gate = Gate()
        let oldURL = try source(.red, in: f.directory), newURL = try source(.blue, in: f.directory)
        let old = f.preferences.beginBackgroundImport(scope: .home) { await gate.load() }
        await fulfillment(of: [gate.entered], timeout: 5)
        await install(newURL, scope: .home, in: f.preferences)
        let newConfig = f.preferences.homeBackgroundConfig
        gate.resume(oldURL)
        await old.completion.value
        XCTAssertEqual(f.preferences.homeBackgroundConfig, newConfig)
    }

    func testResetInvalidatesDelayedImportWithoutAffectingOtherScopeOrTheme() async throws {
        let f = try fixture(), gate = Gate()
        await install(try source(.blue, in: f.directory), scope: .shower, in: f.preferences)
        let other = f.preferences.showerBackgroundConfig
        f.preferences.theme = "dark"
        let handle = f.preferences.beginBackgroundImport(scope: .home) { await gate.load() }
        await fulfillment(of: [gate.entered], timeout: 5)
        f.preferences.resetBackground(scope: .home)
        let reset = f.preferences.homeBackgroundConfig
        gate.resume(try source(.red, in: f.directory))
        await handle.completion.value
        XCTAssertEqual(f.preferences.homeBackgroundConfig, reset)
        XCTAssertFalse(reset.enabled); XCTAssertNil(reset.themeColor)
        XCTAssertEqual(reset.opacity, 1); XCTAssertEqual(reset.blur, 0); XCTAssertEqual(reset.brightness, 1)
        XCTAssertEqual(f.preferences.showerBackgroundConfig, other)
        XCTAssertEqual(f.preferences.theme, "dark")
    }

    func testPageCloseCancellationPreservesExistingImageAndStopsLoadingImmediately() async throws {
        let f = try fixture(), gate = Gate()
        let url = try source(.red, in: f.directory)
        await install(url, scope: .home, in: f.preferences)
        let existing = f.preferences.homeBackgroundConfig
        let handle = f.preferences.beginBackgroundImport(scope: .home) { await gate.load() }
        await fulfillment(of: [gate.entered], timeout: 5)
        f.preferences.cancelBackgroundImport(scope: .home, matching: handle.id)
        XCTAssertNil(f.preferences.backgroundImports[.home])
        gate.resume(url)
        await handle.completion.value
        XCTAssertEqual(f.preferences.homeBackgroundConfig, existing)
    }

    func testStalePageHandleCannotCancelNewImport() async throws {
        let f = try fixture(), gate = Gate()
        let old = f.preferences.beginBackgroundImport(scope: .home) { nil }
        await old.completion.value
        let current = f.preferences.beginBackgroundImport(scope: .home) { await gate.load() }
        await fulfillment(of: [gate.entered], timeout: 5)
        f.preferences.cancelBackgroundImport(scope: .home, matching: old.id)
        XCTAssertEqual(f.preferences.backgroundImports[.home], .loading)
        gate.resume(try source(.blue, in: f.directory))
        await current.completion.value
        XCTAssertTrue(f.preferences.homeBackgroundConfig.enabled)
    }

    func testConcurrentScopesDoNotCancelEachOther() async throws {
        let f = try fixture(), home = Gate(), shower = Gate()
        let a = f.preferences.beginBackgroundImport(scope: .home) { await home.load() }
        let b = f.preferences.beginBackgroundImport(scope: .shower) { await shower.load() }
        await fulfillment(of: [home.entered, shower.entered], timeout: 5)
        shower.resume(try source(.blue, in: f.directory)); await b.completion.value
        home.resume(try source(.red, in: f.directory)); await a.completion.value
        XCTAssertTrue(f.preferences.homeBackgroundConfig.enabled)
        XCTAssertTrue(f.preferences.showerBackgroundConfig.enabled)
    }

    func testImportFailureIsVisibleAndPreservesExistingConfiguration() async throws {
        let f = try fixture()
        await install(try source(.blue, in: f.directory), scope: .home, in: f.preferences)
        let existing = f.preferences.homeBackgroundConfig
        let invalid = f.directory.appendingPathComponent("invalid.png")
        try Data("not an image".utf8).write(to: invalid)
        let handle = f.preferences.beginBackgroundImport(scope: .home) { invalid }
        await handle.completion.value
        guard case .failed(let text) = f.preferences.backgroundImports[.home] else { return XCTFail("Missing visible error") }
        XCTAssertTrue(text.contains("无法解码"))
        XCTAssertEqual(f.preferences.homeBackgroundConfig, existing)
    }

    func testUnavailableICloudPhotoEndsLoadingWithGuidance() async throws {
        let f = try fixture()
        let handle = f.preferences.beginBackgroundImport(scope: .home) { nil }
        await handle.completion.value
        guard case .failed(let text) = f.preferences.backgroundImports[.home] else { return XCTFail("Missing photo error") }
        XCTAssertTrue(text.contains("iCloud"))
        XCTAssertFalse(f.preferences.homeBackgroundConfig.enabled)
    }

    func testStorageFailureKeepsPreviousStateAndShowsError() async throws {
        let f = try fixture()
        let blocked = f.directory.appendingPathComponent("not-a-directory")
        try Data([1]).write(to: blocked)
        let prefs = OriginalPreferences(defaults: f.defaults, backgroundDirectory: blocked)
        let url = try source(.red, in: f.directory)
        let handle = prefs.beginBackgroundImport(scope: .home) { url }
        await handle.completion.value
        guard case .failed(let text) = prefs.backgroundImports[.home] else { return XCTFail("Missing storage error") }
        XCTAssertTrue(text.contains("保存失败")); XCTAssertFalse(prefs.homeBackgroundConfig.enabled)
    }

    func testNewImageResetsEffectsAndChangesRevisionAndOwnedFile() async throws {
        let f = try fixture()
        await install(try source(.red, in: f.directory), scope: .home, in: f.preferences)
        let old = f.preferences.homeBackgroundConfig
        let oldURL = try XCTUnwrap(f.preferences.backgroundURL(for: .home))
        f.preferences.opacity = 0.4; f.preferences.blur = 20; f.preferences.brightness = 1.5
        await install(try source(.blue, in: f.directory), scope: .home, in: f.preferences)
        let config = f.preferences.homeBackgroundConfig
        XCTAssertEqual(config.opacity, 1); XCTAssertEqual(config.blur, 0); XCTAssertEqual(config.brightness, 1)
        XCTAssertNotEqual(config.imageVersion, old.imageVersion)
        XCTAssertNotEqual(config.imageFile, old.imageFile)
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldURL.path))
    }

    func testLegacyMigrationAndSandboxPathRebaseRetainBothScopes() throws {
        let f = try fixture { defaults, directory in
            try Data([1]).write(to: directory.appendingPathComponent("home.image"))
            defaults.set("/obsolete/container/Backgrounds/home.image", forKey: "homeBackground")
            defaults.set("/obsolete/container/Backgrounds/shower.image", forKey: "showerBackground")
            defaults.set(0.4, forKey: "backgroundOpacity"); defaults.set(11.0, forKey: "backgroundBlur")
            defaults.set(1.2, forKey: "background.home.brightness")
            defaults.set(0.7, forKey: "background.shower.opacity")
            defaults.set(0x345678, forKey: "background.shower.themeRGB")
            defaults.set("dark", forKey: "themeMode")
        }
        XCTAssertEqual(f.preferences.homeBackground, f.directory.appendingPathComponent("home.image").path)
        XCTAssertEqual(f.preferences.homeBackgroundConfig.opacity, 0.4)
        XCTAssertEqual(f.preferences.homeBackgroundConfig.blur, 11)
        XCTAssertEqual(f.preferences.showerBackgroundConfig.opacity, 0.7)
        XCTAssertEqual(f.preferences.showerBackgroundConfig.blur, 0)
        XCTAssertEqual(f.preferences.showerThemeRGB, 0x345678)
        XCTAssertEqual(f.preferences.theme, "dark")
        f.preferences.resetBackground(scope: .home)
        let restored = OriginalPreferences(defaults: f.defaults, backgroundDirectory: f.directory)
        XCTAssertFalse(restored.homeBackgroundConfig.enabled, "v2 reset must not resurrect legacy path")
        XCTAssertTrue(restored.showerBackgroundConfig.enabled)
    }

    func testRangeValidationAndInvalidNumbersCannotPoisonPersistence() throws {
        let f = try fixture()
        f.preferences.opacity = .nan; f.preferences.blur = .infinity; f.preferences.brightness = -.infinity
        XCTAssertEqual(f.preferences.opacity, 1); XCTAssertEqual(f.preferences.blur, 0); XCTAssertEqual(f.preferences.brightness, 1)
        f.preferences.opacity = 0; f.preferences.blur = 99; f.preferences.brightness = 99
        let restored = OriginalPreferences(defaults: f.defaults, backgroundDirectory: f.directory)
        XCTAssertEqual(restored.opacity, 0.2); XCTAssertEqual(restored.blur, 20); XCTAssertEqual(restored.brightness, 1.5)
    }

    func testLargeImageIsDownsampledTo2560AndJPEGStored() async throws {
        let f = try fixture()
        let url = try source(.red, in: f.directory, size: CGSize(width: 4096, height: 3072))
        await install(url, scope: .home, in: f.preferences)
        let stored = try XCTUnwrap(f.preferences.backgroundURL(for: .home))
        let image = await f.preferences.backgroundImages.image(at: stored)
        let cg = try XCTUnwrap(image?.cgImage)
        XCTAssertEqual(max(cg.width, cg.height), 2560)
        let saved = try XCTUnwrap(CGImageSourceCreateWithURL(stored as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetType(saved) as String?, UTType.jpeg.identifier)
    }

    func testEXIFRotationIsAppliedBeforeSaving() async throws {
        let f = try fixture()
        let plain = try source(.blue, in: f.directory, size: CGSize(width: 80, height: 40))
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(plain as CFURL, nil))
        let cg = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let rotated = f.directory.appendingPathComponent("rotated.jpg")
        let writer = try XCTUnwrap(CGImageDestinationCreateWithURL(rotated as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(writer, cg, [kCGImagePropertyOrientation: 6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(writer))
        await install(rotated, scope: .home, in: f.preferences)
        let image = await f.preferences.backgroundImages.image(at: try XCTUnwrap(f.preferences.backgroundURL(for: .home)))
        XCTAssertEqual(image?.cgImage?.width, 40); XCTAssertEqual(image?.cgImage?.height, 80)
        XCTAssertEqual(image?.imageOrientation, .up)
    }

    func testHEICImportWhenPlatformEncoderIsAvailable() async throws {
        let types = CGImageDestinationCopyTypeIdentifiers() as! [String]
        guard types.contains(UTType.heic.identifier) else { throw XCTSkip("HEIC encoder unavailable on this simulator") }
        let f = try fixture()
        let png = try source(.blue, in: f.directory)
        let original = try XCTUnwrap(CGImageSourceCreateWithURL(png as CFURL, nil))
        let heic = f.directory.appendingPathComponent("fixture.heic")
        let writer = try XCTUnwrap(CGImageDestinationCreateWithURL(heic as CFURL, UTType.heic.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(writer, try XCTUnwrap(CGImageSourceCreateImageAtIndex(original, 0, nil)), nil)
        XCTAssertTrue(CGImageDestinationFinalize(writer))
        await install(heic, scope: .shower, in: f.preferences)
    }

    func testCacheHitsDoNotDecodeAgainDuringEffectChanges() async throws {
        let f = try fixture()
        await install(try source(.blue, in: f.directory), scope: .home, in: f.preferences)
        let url = try XCTUnwrap(f.preferences.backgroundURL(for: .home))
        let before = await f.preferences.backgroundImages.snapshot()
        let first = await f.preferences.backgroundImages.image(at: url)
        for n in 0..<50 {
            f.preferences.brightness = 0.4 + Double(n) / 50
            _ = await f.preferences.backgroundImages.image(at: url)
        }
        let last = await f.preferences.backgroundImages.image(at: url)
        let after = await f.preferences.backgroundImages.snapshot()
        XCTAssertTrue(first === last)
        XCTAssertEqual(after.decodedImages, before.decodedImages)
        XCTAssertEqual(after.cacheHits - before.cacheHits, 52)
    }

    func testColorMatrixUsesRGBGainAndIndependentAlphaAtAllViewportSizes() throws {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = CIContext(options: [.useSoftwareRenderer: true, .workingColorSpace: colorSpace, .outputColorSpace: colorSpace])
        let input = CIImage(color: CIColor(red: 0.6, green: 0.4, blue: 0.2, alpha: 1)).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 48))
        for size in [CGSize(width: 320, height: 200), CGSize(width: 430, height: 932), CGSize(width: 1024, height: 768)] {
            for brightness in [0.4, 1.0, 1.5] {
                var config = BackgroundConfiguration(); config.brightness = brightness; config.opacity = 0.5
                let output = BackgroundRenderPipeline.output(input, size: size, scale: 1, effects: BackgroundEffects(config))
                XCTAssertEqual(output.extent, CGRect(origin: .zero, size: size))
                var pixel = [UInt8](repeating: 0, count: 4)
                pixel.withUnsafeMutableBytes { data in
                    context.render(output, toBitmap: data.baseAddress!, rowBytes: 4,
                        bounds: CGRect(x: size.width / 2, y: size.height / 2, width: 1, height: 1), format: .RGBA8, colorSpace: colorSpace)
                }
                XCTAssertEqual(Double(pixel[0]), 0.6 * brightness * 0.5 * 255, accuracy: 3)
                XCTAssertEqual(Double(pixel[1]), 0.4 * brightness * 0.5 * 255, accuracy: 3)
                XCTAssertEqual(Double(pixel[3]), 0.5 * 255, accuracy: 2)
            }
        }
    }

    func testBlurDoesNotIntroduceTransparentCropEdges() throws {
        let input = CIImage(color: CIColor(red: 0.5, green: 0.3, blue: 0.6)).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 60))
        var config = BackgroundConfiguration(); config.blur = 20
        let output = BackgroundRenderPipeline.output(input, size: CGSize(width: 320, height: 200), scale: 2, effects: BackgroundEffects(config))
        let context = CIContext(options: [.useSoftwareRenderer: true])
        var pixel = [UInt8](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { data in
            context.render(output, toBitmap: data.baseAddress!, rowBytes: 4,
                bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        }
        XCTAssertEqual(pixel[3], 255)
    }

    func testMetalPresentationKeepsTopAndBottomOrientation() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw XCTSkip("Metal unavailable; orientation still requires an iPhone GPU check")
        }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16), format: format).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 16, height: 8))
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 8, width: 16, height: 8))
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 16, height: 16, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        descriptor.storageMode = .shared
        let texture = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        let buffer = try XCTUnwrap(queue.makeCommandBuffer())
        let colorSpace = BackgroundRenderPipeline.colorSpace
        let context = CIContext(mtlDevice: device, options: [.workingColorSpace: colorSpace, .outputColorSpace: colorSpace])
        let output = BackgroundRenderPipeline.output(CIImage(cgImage: try XCTUnwrap(image.cgImage)),
            size: CGSize(width: 16, height: 16), scale: 1, effects: BackgroundEffects(BackgroundConfiguration()))
        try BackgroundRenderPipeline.render(output, to: texture, commandBuffer: buffer, context: context)
        buffer.commit(); buffer.waitUntilCompleted()
        XCTAssertEqual(buffer.status, .completed)
        var bytes = [UInt8](repeating: 0, count: 16 * 16 * 4)
        bytes.withUnsafeMutableBytes { pointer in
            texture.getBytes(pointer.baseAddress!, bytesPerRow: 16 * 4,
                from: MTLRegionMake2D(0, 0, 16, 16), mipmapLevel: 0)
        }
        XCTAssertGreaterThan(bytes[0], 240); XCTAssertLessThan(bytes[2], 15)
        let bottom = 15 * 16 * 4
        XCTAssertGreaterThan(bytes[bottom + 2], 240); XCTAssertLessThan(bytes[bottom], 15)
    }

    @MainActor private final class Gate {
        let entered = XCTestExpectation(description: "Photo provider requested")
        private var continuation: CheckedContinuation<URL?, Never>?
        func load() async -> URL? {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                entered.fulfill()
            }
        }
        func resume(_ value: URL?) { continuation?.resume(returning: value); continuation = nil }
    }
}
