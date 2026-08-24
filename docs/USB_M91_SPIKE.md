# M9.1 USB 独占音频可行性 Spike（D5 决策）

> 调研日期：2026-08-24。执行者：ZCode agent。结论消费者：`PORTING_EXECUTION_PLAN.md` §5 D5、§6 M9.1，`FEATURE_MATRIX.md`「USB 独占」行。
>
> 方法：本机 API 24 SDK d.ts 逐条核对（命令行工具链 SDK 下的 `sdk/default/openharmony/ets/api/@ohos.usbManager.d.ts`，比网页更权威）+ 华为官方文档交叉 + sysroot native 头检查 + 模拟器探针。**未做**：真机 + 物理 USB DAC 枚举试探（本机无真机/UAC 设备），如实记录。

## 1. 结论（D5 定案）

**UAC 独占直连在 API 24 的 API 面上是「可行」的——这与计划书 D5「大概率不可行」的预期相反；但综合实时性、工程量、系统竞争三重风险，维持「不移植独占模式」的决策，USB DAC 走系统音频路径（系统 USB Audio HAL 自动接管，AVPlayer 常规播放）。**

理由分解见 §4。C++ 5.7 万行（UAC1/UAC2 协议栈+反馈时钟+libusb）**不预移植**（原决策维持，理由更新）。

## 2. API 面证据（d.ts 核对，API 24 = SDK 6.1.1.125 Release）

| 能力 | API | 状态 |
| --- | --- | --- |
| 设备枚举 | `usbManager.getDevices(): Array<Readonly<USBDevice>>` | ✅ @since 8 |
| 运行时授权 | `requestRight(deviceName): Promise<boolean>` / `hasRight` / `removeRight` | ✅ @since 8；**用户弹窗授权模型，无静态 `ohos.permission.*` 要求**（module.json5 无需新增权限；调用未授权时报 14400001 提示先 requestRight） |
| 打开设备 | `connectDevice(device): USBDevicePipe` | ✅ @since 8 |
| **接口独占** | `claimInterface(pipe, iface, force?: boolean): number` | ✅ @since 8；`force=true` 强制剥夺（kick out 当前占有者，含内核驱动） |
| 控制传输 | `controlTransfer(pipe, USBControlParams)` / `usbControlTransfer`（@since 12） | ✅ @since 8；SET_INTERFACE/采样率协商可走 |
| **等时传输** | `usbSubmitTransfer(transfer: UsbDataTransferParams)` / `usbCancelTransfer` | ✅ **@since 18，公开 ArkTS API**（无 @systemapi、无 @permission 标记） |
| 等时类型与分包 | `UsbEndpointTransferType.TRANSFER_TYPE_ISOCHRONOUS = 0x1`；`UsbIsoPacketDescriptor { length, actualLength, status }`；`UsbDataTransferParams.isoPacketCount`；回调 `SubmitTransferCallback.isoPacketDescs` | ✅ @since 18 |
| 中断传输（UAC 反馈端点可选路径） | `UsbEndpointTransferType.TRANSFER_TYPE_INTERRUPT = 0x3`（同一 submit API） | ✅ @since 18 |
| 设备复位 | `resetUsbDevice(pipe): boolean` | ✅ @since 20 |
| 传输状态 | `UsbTransferStatus`（COMPLETED/ERROR/TIMED_OUT/CANCELED/STALL/NO_DEVICE/OVERFLOW） | ✅ @since 18 |

关键位置（本机 `@ohos.usbManager.d.ts`）：`claimInterface` :173；`usbSubmitTransfer` :1505；`UsbEndpointTransferType` :1307；`UsbIsoPacketDescriptor` :1337；`UsbDataTransferParams` :1405；`resetUsbDevice` :1538。旧 `@ohos.usb.d.ts`（since 8）整体 `@useinstead` usbManager，且无等时能力，不采用。

官方文档（交叉确认公开性）：
- ohos.usbManager API 参考：<https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-usbmanager>
- USB 开发指导：<https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/usb-guidelines-V13>

**native 路径**：OpenHarmony sysroot（`sdk/default/sysroot/usr/include/`）与 hms 目录均**无公开 USB DDK 头文件**（无 usb_ddk.h 等；find 全量核过）。OpenHarmony 社区的 USB DDK（`usb_if.h` 系）不在本 SDK 分发范围 → **native/C++ 直连路径对本工程不可用**，若做只能走 ArkTS 层。

## 3. 模拟器探针（API 可达性）

ohosTest `ActsDiagnosticsDeviceTest#usbManagerApiReachable`（`entry/src/ohosTest/ets/test/DiagnosticsDevice.test.ets`；Pura 90 API 24 模拟器，2026-08-24 10:16 `aa test` 全套 `Tests run: 5, Failure: 0, Error: 0, Pass: 5`）：`usbManager.getDevices()` 调用**不抛异常**，返回空数组（模拟器无 USB host 设备，属预期）→ 模块在设备上可达、API 面真实存在。真机 UAC 枚举/claim/等时回环**未执行**（无物理设备）。

## 4. 为什么仍不做独占模式

1. **实时性**：UAC 等时传输要求按 1ms 微帧节拍持续提交/回收 transfer（UAC2 高采样率下更紧）。Android 原版为此专门写了 C++ 独占线程 + libusb + 反馈时钟（5.7 万行 C++ + 9.9k Kotlin）。ArkTS 侧只有 JS 线程，GC 暂停与事件循环调度抖动会直接破坏等时节拍（underrun→爆音）。`usbSubmitTransfer` 是 AsyncCallback 形态，链式提交的调度延迟不可控。
2. **反馈时钟工程量**：UAC 异步端点的反馈（feedback endpoint，每微帧回报实际采样时钟偏差）+主机重采样补偿是整个工程的核心难点；没有它，时钟漂移必然周期性丢帧。在 ArkTS 层重写这套逻辑的验证成本远超收益。
3. **与系统 USB Audio HAL 的竞争无文档承诺**：插入 UAC DAC 时系统音频服务会自动 claim 音频接口；三方应用 `claimInterface(force=true)` 剥夺系统 HAL 后，系统音频路径的降级行为（其他应用播放、路由表、拔出恢复）无官方承诺，真机矩阵验证成本高。
4. **收益面窄**：独占直连的收益（绕过系统重采样/混音、位 perfect 输出）只覆盖「手机 + USB DAC + 本应用」小众场景；系统路径下 AVPlayer → USB Audio HAL 已能输出音频。

## 5. 后续若重新启用（留给未来）

- 前置条件：官方开放 native USB DDK 或 ArkTS Worker 线程提交节拍实测达标；真机（非模拟器）+ UAC1 设备先行枚举/claim force/单包等时回环三步探针。
- 本文档 §2 的 API 清单可直接作为实现规格起点。
