# 背景装扮专项修复（2026-11-06）

状态：源代码修复与静态检查完成；Xcode 类型检查、XCTest、模拟器画面与真机性能尚未验证。没有运行 GitHub Actions，没有构建 IPA，也没有发布 Release。

工作分支：`fix/background-management-20261106`。集成基线 `e5cad0e` 合入既有附近设备名称修复和主题/安全区域修复；下述背景修改均相对此基线审查。未合并到稳定分支。

## Android 依据与模块对应

固定参考 [v3.1.0 / 761ae9b51bb0168b5a4de63a91f5168328107234](https://github.com/yehu-imei/linyu/tree/761ae9b51bb0168b5a4de63a91f5168328107234)。核对上游 `ff5f8befb2416a21955927c54677e26740a4002a`：本次要求的六个背景源文件与 v3.1.0 无差异。没有根据 README 推测行为。

以下 Android 路径均位于 `app/src/main/java/com/hualala/linyu/`。

| Android | iOS | 对齐方式 / 必要差异 |
| --- | --- | --- |
| `ui/CustomBackgroundScreen.kt` | `Views/Profile/ProfileBackgroundPage.swift` | 保留两作用域选项、200pt 预览、示例玻璃卡、主题色、三滑块和确认恢复默认。窄屏滚动，宽屏内容最大 680pt。PhotosPicker 替代 URI 选择器。 |
| `utils/BackgroundState.kt` / `BgConfig` | `Models/BackgroundConfiguration.swift`、`OriginalPreferences.swift` | HOME/SHOWER 各自保存 enabled、图片、opacity、blur、brightness、themeColor、imageVersion。选择页面只改变选择偏好，不搬运三个共享滑块字段。 |
| `utils/PrefsHelper.kt` 背景键 | `OriginalPreferences` 的 v2 配置 JSON / UserDefaults | 一个作用域一次保存完整配置再发布；旧的路径、参数和主题色迁移，原键不删。不是更改账户或交易持久化。 |
| `utils/BackgroundManager.kt` 存图与读图 | `Models/BackgroundPhoto.swift`、`BackgroundImageStore.swift` | 文件形式获取照片，actor 串行完成 ImageIO 缩略、EXIF 归一、JPEG95 保存、取色与缓存。最大边 2560px。每张新图使用不可变文件名和新 revision，避免复用路径的旧图问题。 |
| `utils/BackgroundManager.kt` `extractThemeColor()` | `Models/OriginalBackgroundPalette.swift` | 已保存 JPEG 的 48×48 sRGB 取样，RGB 每通道 32 档统计，HSV s>0.15、0.20<v<0.95，输出 s 限制 0.35–0.75、v 限制 0.45–0.85。 |
| `ui/AppBackgroundLayer.kt` | `Views/DesignSystem/BackgroundImageRenderer.swift` / `BackgroundCanvas`，`LinYuDesignSystem.swift` / `OriginalBackground` | 同一绘制路径供预览和实际页面使用；居中 Crop、RGB 乘法亮度、Alpha 和模糊。效果调整不重新解码或生成按亮度缓存的 UIImage。Metal 不可用时保留 Core Image 绘制回退。 |
| `ui/theme/Theme.kt` | 既有 `LinYuThemeHost.swift`，使用页 `OriginalShowerView.swift` 的 palette 注入 | HOME 色仍通过现有 host 使用；背景不写 themeMode，不触发圆形切换。按本任务要求，SHOWER 使用自己的强调色。 |

### 有意保留的平台 / 用户要求差异

- Android 的 `inSampleSize` 按 2 的幂下采样，可能小于 2560；ImageIO 按 2560 最大边创建缩略图，并应用 EXIF 方向。两者遵守相同上限，不承诺逐像素相同。
- Android 使用固定文件名及 mtime/cache + imageVersion；iOS 使用每次成功导入的新文件名、新 revision、有界解码缓存，提交成功后清理上一张自有文件。迁移的外部路径允许读取，不能随意删除。
- Android `Theme.kt` 实际只用 HOME 主题色作为全局强调色。SHOWER 独立强调色是本任务明确要求的扩展，不宣称为原版已有行为。
- Android v3.1.0 恢复默认清图片、enabled、主题色和缓存，没有重置三项调节参数。本次按用户明确要求恢复 1.0 / 0 / 1.0。
- Android blur 仅 Android 12+ 有效；iOS 使用 Core Image 高斯模糊，半径按显示比例换算。内核与跨平台缩放、颜色管理可能产生细小差异，未做 Android/iOS 像素验收。
- 相册选择按系统授权，仅访问用户选择的照片，不申请整个照片库的额外权限。iCloud、HEIF/HEIC 实际可用性仍依赖系统解码器、下载和 LiveContainer 文件提供能力。

## 已证实问题与修复

1. **旧全局参数迁移不稳定**：原 initializer 支持旧 `backgroundOpacity/backgroundBlur`，切换回来时 `load()` 却不含此回退。改为启动时迁移到两套完整配置，后续只读取该配置；旧全局值仅属于 HOME，不套给 SHOWER。
2. **共享编辑字段与两个选择状态源**：旧 `backgroundScope` 会依次改写 opacity/blur/brightness，并逐项持久化；页面还有独立 AppStorage scope。改为唯一 typed selection 和捕获作用域的 Binding。源码可证实存在中间状态和重复写入；没有把“所有切换都必然串值”当作已证实事实。
3. **导入目标与操作竞态**：旧页面在 PhotosPicker 返回后才捕获 scope；恢复默认不取消未完成的相册读取。新实现打开选择器即捕获目标；每个作用域一个任务和操作 ID。更换、取消、恢复默认使旧任务失效。提交前再次验证 ID，旧任务不能覆盖新图，也不能取消别的页面发起的新任务。
4. **导入阻塞风险**：旧 `@MainActor setBackground` 同步缩略、JPEG、写文件和取色。现在照片先以文件表示接收，复制与大图处理在主线程之外；完整文件及主题色准备好后，主线程一次提交配置。失败保留原配置和图片，并显示解码、存储或照片/iCloud 的可操作错误。
5. **缓存命中之前读磁盘**：旧 `background()` 先 `UIImage(contentsOfFile:)` 再查缓存。新 actor 先查 NSCache，最多 2 张 / 64MiB 成本上限（NSCache 允许系统提前逐出）；颜色和特效变化不改变解码任务的 identity。
6. **滑动亮度生成中间图片**：旧缓存键包含 brightness，并通过 CIContext 为不同值创建 UIImage。新实现保留源 UIImage，创建轻量滤镜图，按需绘制到 Metal drawable；没有每个亮度一份的图片缓存。未测量真实 FPS，不宣称已经达到某个性能提升比例。
7. **预览 / 实际层实现重复**：旧预览和实际背景分别实现裁切、效果顺序。统一为 BackgroundCanvas 与 BackgroundRenderPipeline，共用底色、sRGB RGB gain、Alpha、裁切、模糊及 OriginalGlassCard。尚未证实旧顺序差异必然造成肉眼可见偏差。
8. **换图失效与重启一致性**：成功保存的 JPEG 才是取色和显示来源，避免旧版取色用压缩前图片、显示用压缩后图片。每次换图有新 revision，保存相对文件名；迁移时可将旧绝对路径重定位到当前 Backgrounds 中同名文件。
9. **取消与失败没有可靠的可见出口**：现在每作用域独立 loading/failed，提供取消按钮；结束、失败或取消均清理 loading。无效文件在预览显示重新选择指引。取消未完成处理也会清理新建的暂存/未提交文件。

这轮未删除任何用户交易记录、未修改 API、BLE、认证、通知、结算逻辑。`OriginalShowerView` 只增加作用域配色，连确认弹窗的取消强调色也使用该配色。

## 状态与调用顺序

`打开相册并捕获 scope → 系统读取 / iCloud 下载 → 后台暂存文件 → ImageIO 方向归一 + 最大边 2560 → JPEG95 原子写入新文件 → 从保存图片提取主题色并预热缓存 → 检查取消和当前操作 ID → 主线程保存该 scope 完整配置并发布 → 清理该 scope 上一张自有图片`。

另一作用域可以拥有独立导入任务；两者的图片处理由同一 actor 串行执行，避免同时解码多张大图。三滑块仅更新当前作用域参数。重启从 v2 配置恢复；恢复默认先取消本作用域任务、提交默认配置、新 revision，再清理旧文件，不写深浅模式。

不凭空补回已经丢失的旧图片。若 LiveContainer 移动后文件不在新目录，且旧路径不可读，预览会要求重新选择；保留相关配置供诊断，不伪称恢复成功。进程被强杀前尚未提交的导入不能保证继续；旧配置仍有效，可能留下未引用的临时/新图片文件，后续存储清扫尚未实现。

## 验证结果（实际执行与未执行分开）

实际执行：

- 对应用和 iOS 单元测试目录共 60 个 Swift 文件做 tree-sitter Swift 语法解析：无 ERROR / missing 节点。**不等于 Swift 类型检查、链接或 XCTest 通过。**
- `git diff --check`：通过。
- 检查六个 Android 指定文件：v3.1.0 与上述最新上游提交无差异。
- 修改范围核对：相对集成基线，既有 OriginalRootView、LinYuThemeHost、LinYuRevealDrawing 完全未改；蓝牙、认证、网络、通知、交易目录无本轮差异。
- 检查 workflow 触发条件：本独立分支不匹配自动 push；没有调用 dispatch、rerun、构建或发布接口。任务中 Actions run 总数仍为 48（最终推送后再次核实）。

新增 `LinYuIOSTests/BackgroundManagementTests.swift` 的 **22 个 XCTest，目前全部未执行**，原因是此 Windows 环境没有 Swift 编译器、Xcode 或 iOS 模拟器。测试只用本地临时目录、隔离 UserDefaults、生成的纯色图片和可控照片加载器；不触达真实账号、网络或水表。

| 用户要求场景 | 自动化覆盖 / 仍需验证 |
| --- | --- |
| HOME 导入、SHOWER 另一张图 | `testBothScopesImportPersistAndRestoreIndependently`，包含 PNG/JPEG、色值与路径独立 |
| 快速切换、滑块目标不串 | `testRapidScopeSwitchDoesNotWriteEitherConfiguration`、`testSliderBindingRetainsItsScopeAfterSelectionChanges` |
| 选择后切换页面 / 目标固定 | `testDelayedPhotoLoadKeepsScopeCapturedBeforeSelectionChanges` |
| 连续更换、缓存失效 | `testLateOldImportCannotReplaceNewImage`、`testNewImageResetsEffectsAndChangesRevisionAndOwnedFile` |
| 双作用域同时导入 | `testConcurrentScopesDoNotCancelEachOther` |
| 失败 / iCloud 不可用 / 存储失败 | 对应 ImportFailure、UnavailableICloudPhoto、StorageFailure 测试 |
| 取消 / 页面关闭 / 旧页面取消新任务 | PageCloseCancellation、StalePageHandle 测试；系统照片选择器取消仍需 UI 验证 |
| 恢复默认与旧导入竞争 | `testResetInvalidatesDelayedImportWithoutAffectingOtherScopeOrTheme` |
| 重启、旧偏好迁移、容器路径 | BothScopes…、LegacyMigrationAndSandboxPathRebase… 测试 |
| 范围 / 非有限值 | `testRangeValidationAndInvalidNumbersCannotPoisonPersistence` |
| 大图 / EXIF / HEIC | LargeImage…、EXIFRotation…、HEICImport…；HEIC 编码器缺失明确 skip，不当作通过 |
| 缓存不随滑块重新解码 | `testCacheHitsDoNotDecodeAgainDuringEffectChanges`，检查生产 store 的计数与对象复用 |
| 透明度 / 乘法亮度 / 裁切尺寸 | ColorMatrix…；预览和实际页面共用此生产管线。覆盖 320×200、430×932、1024×768 的输出范围 |
| 模糊边缘、GPU 方向 | BlurDoesNotIntroduceTransparentCropEdges、MetalPresentationKeepsTopAndBottomOrientation；Metal 不可用明确 skip |
| 深浅模式与背景独立 | Reset… 保持 theme，不调用主题切换；实际动画与画面仍需验证 |
| 不同设备 / 窗口 / 大字体 / 弹窗 | 现有滚动、最大宽度、48pt 滑块操作区保留；尚无模拟器截图和 UI 验收结果 |

已有 OriginalIntegrationTests 中三个背景测试未删除，需与新增测试一起在 Mac 执行。应先在 Xcode 本地执行测试和类型检查；本任务不为此启动 Actions。

### 待 Mac / 真机检查

- 首先完成新增测试的 Swift 类型检查、XCTest 运行，特别是 Metal 输出方向 / alpha / 色域测试；再对照 Android 截图，不能以语法解析代替。
- iPhone 320/375/430pt、小屏横屏、iPad 744/820/1024/1366pt 及窄窗口：背景裁切、滑块、恢复默认弹窗、键盘/安全区域、动态字体和底部导航。
- 真正的 HEIF/HEIC、带 EXIF 的非纯色照片、48MP、超宽/长图、iCloud 未下载照片、用户取消及权限/存储失败。
- 预览与实际 HOME / SHOWER，浅/深主题与圆形扩散、透明玻璃卡，返回页面时新图即时更新。Metal 内容不能仅用 UIView.drawHierarchy 的截图判断，须核对实际屏幕截图。
- LiveContainer 导入、容器搬移、重启恢复，旧路径丢失时的错误指引。
- Instruments：拖动滑块 FPS、峰值内存、照片加载和导入耗时、缓存命中与解码次数；未取得这些测量前，不宣称“掉帧已消失”或量化性能改善。

诊断日志只含 scope、`processing` 和 `total` 毫秒、导入失败标记或 GPU 回退标记。actor 的 Metrics 另可读取 decodedImages/cacheHits/completedImports。没有记录照片文件名、照片内容、账号、令牌或服务请求。当前无可用真机测量值。

## Apple 平台接口依据

- [PhotosPicker：选择与编码选项](https://developer.apple.com/documentation/swiftui/view/photospicker%28ispresented%3Aselection%3Amatching%3Apreferreditemencoding%3Aphotolibrary%3A%29)
- [FileRepresentation](https://developer.apple.com/documentation/CoreTransferable/FileRepresentation)
- [MTKView 按需绘制](https://developer.apple.com/documentation/MetalKit/MTKView)
- [CIRenderDestination](https://developer.apple.com/documentation/coreimage/cirenderdestination)

实现与 22 个测试提交：[7a9ce38713b0791f43430ab4a54c7888baa89004](https://github.com/CarpediemDyn/linyu-ios/commit/7a9ce38713b0791f43430ab4a54c7888baa89004)。此报告不宣称已完成真机验收，也不提供未生成的 IPA。
