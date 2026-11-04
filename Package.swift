// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LinYuCore",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [.library(name: "LinYuCore", targets: ["LinYuCore"])],
    targets: [
        .target(name: "LinYuCore", path: "LinYuIOS",
                exclude: ["Info.plist", "LinYuIOS.entitlements", "Assets.xcassets", "Views", "Network", "Security", "Models", "BLE/BleCentral.swift", "Transactions/TransactionManager.swift", "Transactions/CloudShowerController.swift"],
                sources: ["BLE/BleFrame.swift", "BLE/BleDeviceState.swift", "Transactions/WaterContracts.swift", "Transactions/WaterTransactionEngine.swift"]),
        .testTarget(name: "LinYuCoreTests", dependencies: ["LinYuCore"], path: "CoreTests")
    ]
)
