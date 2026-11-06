# LinYu iOS 公开前检查记录

检查日期为 2026 年 11 月 6 日，目标仓库为 `CarpediemDyn/linyu-ios`。在已检查范围内，未发现需要撤销用户凭据或重写提交历史的材料。原有分支和提交历史保留。

## 审计范围与结果

- 获取并核对远端全部 5 个分支及 3 个标签，检查其可达的 60 个既有提交；额外检查本地全部 350 个 blob 对象，包含 4 个不可达的暂存 blob。333 个对象可按 UTF-8 文本检查，其余为图片。后续资料提交另行复扫。
- 使用校验官方发布校验和的 Gitleaks v8.30.1，执行所有引用的完整历史差异扫描。自动命中 2 项，均完成下述人工核实；没有新增个人秘密命中。
- 对全部文件对象补充检查私钥、GitHub 令牌、JWT、云密钥及手机号/邮箱候选。号码来自可控 Mock 测试，文档中的另几项是 Actions 制品编号。保留的原作者邮箱与上游公开联系方式一致。没有用户导出的 Keychain、交易 journal、真实验证码或运行日志文件进入 Git。
- 下载并扫描全部 48 次现有 Actions 的日志，约 13.89 MB，Gitleaks 未发现秘密。检查构建脚本、测试数据、产物上传路径和近期已验收的 IPA；工作流使用 Mock 网络/BLE 测试及 ad-hoc 签名，未从用户手机导出运行数据。检查构建制品元数据，未对所有历史 xcresult 二进制逐字节做内容或图像识别。
- 检查仓库设置。仓库级 Actions Secrets、Variables、Environments、Deploy Keys 和 Webhooks 均为 0。没有 Issue、PR 或代码评论需要脱敏。

扫描器的两项命中如下。

| 位置 | 分类与依据 | 处理 |
| --- | --- | --- |
| `LinYuIOS/Security/KailuSigner.swift` 的协议签名常量 | 与公开 Android v3.1.0 的 `utils/KlcxkjSigner.kt` 一致，属于互操作协议常量；AES 常量也已与公开 `KlcxkjCrypto.kt` 核对 | 保留协议实现，未把它描述为用户令牌或个人 API Key |
| `LinYuIOS/Transactions/TransactionManager.swift` 的 `water-journal-v1` | Keychain 条目的本地键名，未包含其存储的数据 | 保留存储键名 |

未修改签名协议、账户存储、网络、蓝牙或交易状态机。仓库内的 `.gitignore` 已排除构建目录、IPA、私钥证书和 provisioning 文件。

## 许可证与资源

上游 `v3.1.0` 的 MIT 条款和 `Copyright (c) 2026 LinYu Contributors` 原文保留，增加 Cra3y 的 iOS 贡献版权行。原作者仍明确署名为 yehu-imei。 [上游 LICENSE](https://github.com/yehu-imei/linyu/blob/v3.1.0/LICENSE)

三个原版参考 PNG 和 Logo 与上游资源逐字节一致。AppIcon 是 Logo 的尺寸派生图。45 个 SVG 与清单哈希一致，其中 19 个原版 XML 来源哈希在统一 LF/CRLF 后与 v3.1.0 一致。Google Material Icons 的 Apache-2.0 全文已保留。参考图按上游仓库声明的 MIT 来源追溯；未取得独立于上游的插画创作权属证明。本次没有增加外部图片、字体或二进制依赖。 [资源来源](ui-parity/RESOURCE_LICENSES.md) · [署名说明](../NOTICE.md)

## 默认分支与版本

公开默认分支使用 `main`，从已验收的 `ui/android-parity` 基线 `afde230` 建立，只加入 README、署名、许可证及检查记录。两个独立功能修复分支均保持原状。

- 默认源码配置为 v0.4.4（Build 8）。本次 App 关于页面的新署名尚未构建为 IPA。
- 最近成功 IPA 为 v0.4.5（Build 9），产品源码为 `c6d6c3302aa92161cd6ff48656a671cbbcf47de5`，来自独立蓝牙修复分支。 [成功构建](https://github.com/CarpediemDyn/linyu-ios/actions/runs/42154843612)
- `fix/theme-safe-area-transition-20261106` 包含未构建验证的主题修复。
- 当前没有正式 GitHub Release。源码配置、Actions 成功制品及正式发布分别说明。

## 本次验证

- 修改后的 About 视图通过 Swift 语法树解析；当前 Windows 环境未执行 Xcode 编译或 UI 测试。
- `git diff --check` 通过。App 显示名称、图标、Bundle Identifier、部署版本、构建配置和工作流均保留。
- README 为中文项目首页，加入当前能力边界、构建安装说明、维护者和原作者归属。
- 仓库 Description 和 Topics 按用户要求更新。公开操作与匿名访问结果在操作后补充记录。
- 本轮没有触发 GitHub Actions、生成新 IPA 或合并独立蓝牙结算修复分支。
