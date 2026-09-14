# 鸿蒙特色能力结合规划（HARMONYOS_EXCLUSIVE_FEATURES）

> 2026-09-14 编制，基于对 HarmonyOS 26（API 26，对应本工程 `targetSdkVersion 26.0.0`）公开 API 的调研：传感器与硬件交互（`@ohos.sensor` / `@ohos.vibrator` / NFC / BLE）、端侧 AI（`@kit.CoreSpeechKit` / `@kit.VisionKit` / `@kit.AREngineKit` / MindSpore Lite）、系统体验（智慧手势 / 实况窗 / 卡片 / 防窥）、分布式跨设备（`abilityConnectionManager` / 分布式相机 / 接续 / 分布式数据）与 ArkUI 动效（粒子扰动场 / `effectKit` / 可变字体）。全部条目均与本机 SDK（`/opt/command-line-tools/sdk/default`，API 26）声明文件核对过模块存在性。
>
> **定位**：本清单是「NeriPlayer 已经是全功能播放器之后，用鸿蒙独有的 API 做出别人做不了的体验」的规划，与 `ANDROID_PARITY_BACKLOG.md`（把基础功能补齐到 Android 对齐）互补，不设时间承诺、不阻塞开源发布。工程当前 `targetSdkVersion 26.0.0`，清单内所有 API 均可用，无需升级 SDK。
>
> **调研边界**：模块存在性以本地 SDK 声明文件为准；具体接口签名、行为与权限以真机验证为准。文中「完成状态」均为文档级调研结论，未经真机验证，需在 Windows 工作站真机执行。

---

## 0. 优先级与节奏

- **P0（爽点密度高 / 用户直接可感知 / 工程量小）**：波形进度条机械阻尼震感、隔空手势切歌、桌面服务卡片。
- **P1（核心场景深潜 / 有前置依赖或工程量中大）**：audioHaptic 节奏触感、PiP 全局歌词画中画、AVCastPicker 音频流转、陀螺仪视差封面。
- **P2（彩蛋 / 长尾 / 条件性）**：睡眠定时器实况窗、跨端接续、离线语音点歌、粒子扰动场律动、摇一摇切歌、待机屏保黑胶摆台、留声机音效彩蛋、NFC 歌单标签、折叠屏演奏台。
- **明确不做**：AR 贴纸、骨骼点体感、智能抠图、BLE 雷达、防窥检测——与音乐播放器场景不契合，强行添加会稀释产品定位。

每项均按固定结构记录：**功能名 / 效果 / 实现理论基础 / 完成状态 / 工程量 / 风险与注意**。README 的「未来功能」板块是本清单的摘要视图，状态以本文档为准。

---

## 1. P0：波形进度条机械阻尼震感（WaveformSlider + haptic.clock.timer）

- **功能名**：波形进度条机械阻尼震感
- **效果**：拖拽 `WaveformSlider` 时每经过一个波形峰值，触发一次拨轮式短震，做出「机械卡齿」的 seek 手感；波形振幅大处震感略强。
- **实现理论基础**：`@ohos.vibrator`（`@kit.SensorServiceKit`）的 `VibratePreset`——`effectId: 'haptic.clock.timer'` 模拟精密机械齿轮每拨动一格的滴答感（API 12+）；`intensity` 字段（API 12+）随波形振幅调制强度 0~100。波形数据直接复用 `WaveformSlider` 已有的采样缓存，无需新增数据链路。
- **完成状态**：📋 已规划，未实现。模块 `@ohos.vibrator` 已在本地 SDK 核实存在。
- **工程量**：小。仅 UI 层 + vibrator 调用；`ohos.permission.VIBRATE` 为 normal 级。
- **风险与注意**：低。真机需确认线性马达机型震感；失败可静默降级为无震感。注意 `stopVibrationSync()`（API 12+）在拖拽中断时急停，避免拖尾。

## 2. P0：隔空手势切歌（SmartGesture）

- **功能名**：智慧手势隔空控制播放
- **效果**：做饭、吃饭等手脏场景下，隔空「敲一敲」暂停/播放、「划一划」切歌。
- **实现理论基础**：ArkUI `SmartGestureController` + 组件 `smartGestureShortcut` 属性（API 26 新增，本工程 targetSdk 26 恰好可用）——利用设备传感器捕获隔空手势（TAP / SLIDE_FORWARD / 翻腕），通过 `ActionProposal` 覆写组件默认行为。
- **完成状态**：📋 已规划，未实现。API 26 新能力，真机行为未知，**必须真机先 spike**。
- **工程量**：小-中。挂在 NowPlayingPage 即可，但需验证传感器精度与误触率。
- **风险与注意**：中。误触可能干扰正常播放；设置页需加开关（`np.*` 键）；与「一起听」暂停语义联动需考虑。隔空手势仅特定机型支持（带姿态传感器的旗舰），需做能力检测降级。

## 3. P0：桌面服务卡片（Form Kit）

- **功能名**：正在播放桌面卡片
- **效果**：2×2 / 2×4 桌面常驻磁贴：旋转封面 + 歌名歌手 + 播放/暂停/切歌按钮，封面主色动态染色背景，glass_ui 美学延伸到桌面。
- **实现理论基础**：`FormExtensionAbility`（`@kit.FormKit`，API 12+ 全量开放）+ `postCardAction` 的 `call` 模式（后台拉起 UIAbility 静默控制 `PlayerManager`，用户无感）+ `formBindingData` 按事件刷新。关键约束：卡片与主应用是**两个进程**，不能依赖 `AppStorage`——封面取色结果与播放状态需落 preferences（或 `@ohos.data.distributedKVStore` 单机模式），卡片侧读快照渲染。
- **完成状态**：📋 已规划，未实现。
- **工程量**：中。新增 FormExtensionAbility + 卡片 UI + 跨进程数据桥；卡片内 ArkTS 动画（封面旋转）支持有限，需真机验证效果。
- **风险与注意**：低。普通卡片无资质门槛；卡片刷新频率受系统管控（定时刷新有最小间隔限制），播放状态变化建议走 `formProvider` 主动推送。

## 4. P1：audioHaptic 节奏触感（Music-Driven Haptics）

- **功能名**：低音节拍同步震动
- **效果**：播放中重低音鼓点触发马达跟随律动震颤，震感强度与音量联动。
- **实现理论基础**：`@ohos.multimedia.audioHaptic`（本地 SDK 核实存在）——系统「音频-触觉协同」服务。**前置调研结论**：该服务设计初衷是系统音效/短音频触感（通知、铃声），对 AVPlayer 播放的**在线流媒体是否生效是最大不确定点**。实现前先读 d.ts 确认 source 类型约束。
- **完成状态**：📋 已规划，未实现，**先 spike 再承诺**。
- **工程量**：中。新增 `player/AudioHapticController.ets` 与 `PlayerManager` 生命周期联动；设置页加「触感反馈」开关（默认关，避免打扰）。
- **风险与注意**：中。若在线流不生效，降级方案为「实时音频能量检测 + `vibrator` 自定义波形 JSON」（`VibrateFromFile`，频率/强度/包络可编程），或放弃本项只保留 §1 波形条震感。与 `ANDROID_PARITY_BACKLOG.md` §2.3 Crossfade（双 AVPlayer 轮换）正交，但需注意双实例下的源切换衔接。

## 5. P1：PiP 全局歌词画中画（PiPWindow）

- **功能名**：全局悬浮歌词画中画
- **效果**：应用内悬浮歌词条（`FloatingLyricBar` 已有）升级为跨应用全局悬浮的歌词胶囊——边刷别的 App 边看逐字歌词，点按可展开控制条。
- **实现理论基础**：`@ohos.PiPWindow`（本地 SDK 核实存在）——画中画窗口承载歌词视图，跨应用悬浮；需在 `module.json5` 的 abilities 声明 `supportWindowMode: ["fullscreen", "floating"]`。歌词数据经事件通道驱动窗口内视图更新。
- **完成状态**：📋 已规划，未实现。**前置依赖**：先读 `DESKTOP_LYRIC_M102_SPIKE.md` 结论——桌面歌词已打通至系统服务层、图形上屏待真机验证；PiP 歌词与桌面歌词是同一诉求的两条路线，若 M102 落地则本项降级为备选或不做，避免重复造轮子。
- **工程量**：中。`LyricPiPController.ets`（窗口生命周期）+ 歌词数据跨窗口更新通道（可复用 `LyricDispatcher` 管线）。
- **风险与注意**：中。浮窗位置/点击/息屏后表现均需真机验证；PiP 场景在系统侧有白名单约束（视频/通话/导航类），纯文本歌词能否过审需真机确认。

## 6. P1：AVCastPicker 音频流转（投屏）

- **功能名**：音频投屏与多设备流转
- **效果**：一键投到 Sound X / 智慧屏 / 车机 / DLNA 设备，手机端变为带封面与歌词的沉浸式遥控器。
- **实现理论基础**：`@kit.AVSessionKit` 的 `avCastPicker` 组件（API 13+）+ `AVCastController`——系统级设备流转弹窗，经 Cast+ / DLNA 协议投播。本工程 AVSession 基础扎实（`AVSessionManager` 已深接），接入顺水推舟。
- **完成状态**：📋 已规划，未实现。
- **工程量**：小-中。NowPlayingPage 加 avCastPicker 组件 + AVCastController 状态同步。
- **风险与注意**：低。需真机 + 实体投屏设备验证链路。

## 7. P1：陀螺仪视差封面（Parallax Cover Art）

- **功能名**：裸眼 3D 视差封面
- **效果**：NowPlayingPage 封面/黑胶随设备倾斜微移（Apple Music 式景深视差），配合 glass_ui 背景流光。
- **实现理论基础**：`sensor.on(sensor.SensorId.ROTATION_VECTOR)`（无需权限）——四元数转欧拉角驱动封面 `translate`/`rotate`，玻璃底板反向微移形成多层深度。采样节流（约 20Hz）避免与属性动画冲突。
- **完成状态**：📋 已规划，未实现。纯 UI 层改动。
- **工程量**：小。
- **风险与注意**：低。视差变换应在转场动画结束后激活，且与一镜到底转场层、封面弹性回弹动效分层，避免多层 translate 打架。

---

## 8. P2：睡眠定时器实况窗（Live View Kit）

- **功能名**：睡眠定时倒计时实况窗
- **效果**：睡眠定时器启动后，状态栏胶囊/锁屏/AOD 实时显示剩余分钟，不用解锁即可暂停或加时。
- **实现理论基础**：`@kit.LiveViewKit`（`liveViewManager`）——实况窗白名单场景恰好包含 `TIMER`（另有 16 类场景白名单、单次 ≤8h、胶囊 2h 未更新自动隐藏等约束）。项目已有 `SleepTimer`，只差实况窗展示层。
- **完成状态**：📋 已规划，未实现。**资质门槛：需在 AGC 申请实况窗权限**，是全清单门槛最高的一项；demo 阶段可跳过。
- **工程量**：中。SleepTimer 事件 → liveViewManager 更新胶囊。
- **风险与注意**：资质审批以「睡眠定时」场景申请，不依赖也不影响「正在播放」诉求（播放状态本身已由 AVSession 锁屏卡片覆盖，勿重复建设）。

## 9. P2：跨端接续（Continuation）

- **功能名**：手机 → 平板无缝接力播放
- **效果**：手机听到一半靠近平板，任务栏出现接力图标，一点即在平板续播（队列、进度、歌词位置同步迁移）。
- **实现理论基础**：`UIAbility.onContinue`（小数据 <100KB 塞 `wantParam`）+ `@ohos.data.distributedDataObject`（`save()`/按 `sessionId` 恢复）+ `context.distributedFilesDir`（文件资产迁移）；`module.json5` abilities 配 `continuable: true`，权限 `ohos.permission.DISTRIBUTED_DATASYNC`（normal 级 user_grant）。
- **完成状态**：📋 已规划，未实现。
- **工程量**：中-大。需双端设备与华为同账号组网验证；队列与进度的序列化已具备基础（同步引擎已有 Protobuf/JSON 编解码管线可复用）。
- **风险与注意**：双设备用户才可感知，单设备用户无感；依赖同账号可信组网。

## 10. P2：离线语音点歌（Core Speech Kit）

- **功能名**：语音 DJ（点歌/切歌/暂停）
- **效果**：驾车或双手占用时，说「播放周杰伦」「切歌」「暂停」即可控制；可选 TTS 播报歌名。
- **实现理论基础**：`@kit.CoreSpeechKit` 的 `speechRecognizer`（端侧离线识别，支持注入最多 200 个热词提升歌名/指令识别率）+ `textToSpeech`（`speed`/`pitch`/`volume` 可调）。需 `ohos.permission.MICROPHONE`。
- **完成状态**：📋 已规划，未实现。
- **工程量**：中。语音指令 NLU 映射到 PlayerManager 指令；热词注入用歌单高频曲目动态生成。
- **风险与注意**：麦克风常驻监听有耗电与隐私感知问题，建议「按住说话」或车载场景激活式触发。

## 11. P2：粒子扰动场律动背景（Particle + 音乐能量）

- **功能名**：歌词页音乐律动粒子
- **效果**：歌词页背景粒子随音乐能量呼吸吞吐，副歌段粒子爆发。
- **实现理论基础**：ArkUI `Particle` 组件的扰动场 `disturbanceFields`（API 12+，引力/斥力场使粒子轨道偏转）+ 运行时 `emitter` 更新发射速率。驱动源用 `WaveformSlider` 已有的波形能量数据（纯 ArkTS，无需音频分析引擎）；更精细可上 `AudioCapturer` 采样 RMS。
- **完成状态**：📋 已规划，未实现。
- **工程量**：中。粒子系统配置 + 能量驱动桥。
- **风险与注意**：低-中。注意低端机粒子数量与帧率平衡；建议与视差封面（§7）共用一套「NowPlayingPage 氛围层」驱动框架。

## 12. P2：摇一摇随机切歌（Accelerometer）

- **功能名**：摇一摇换歌
- **效果**：用力摇晃手机触发随机切歌（带防误触：走路/跑步不触发）。
- **实现理论基础**：`sensor.on(sensor.SensorId.ACCELEROMETER)`（`ohos.permission.ACCELEROMETER`，normal 级）——幅度阈值 + 时间窗口去抖 + 陀螺仪辅助排除规律性运动。
- **完成状态**：📋 已规划，未实现。
- **工程量**：小。经典玩法，半天量级。
- **风险与注意**：低。需设置页开关；跑步场景误触是主要风险点。

## 13. P2：待机屏保黑胶摆台（Standby Form）

- **功能名**：充电摆台黑胶时钟
- **效果**：横屏充电且 45°~90° 摆放时，进入全屏待机屏保：黑胶唱片 + 当前歌名 + 时钟的摆台界面。
- **实现理论基础**：待机屏保卡片（API 23+，2×2 卡片）——需在 AGC 申请待机屏保能力并在 `form_config.json` 声明 `standby` 节点；与 §3 桌面卡片共享 FormExtensionAbility 基础设施。
- **完成状态**：📋 已规划，未实现。有 AGC 资质门槛。
- **工程量**：中（在 §3 落地后增量小）。
- **风险与注意**：依赖 §3 先行；屏保态动画能力受限需真机验证。

## 14. P2：留声机音效彩蛋（OHAudioSuite 环境音场）

- **功能名**：复古留声机 / 水下音效模式（隐藏彩蛋）
- **效果**：输出加「老留声机」「水下」「广播喇叭」等环境音场滤镜，怀旧听感彩蛋。
- **实现理论基础**：Native `OHAudioSuite`（API 22+）的 `EFFECT_NODE_TYPE_ENVIRONMENT_EFFECT`（GRAMOPHONE / UNDERWATER / BROADCAST 等内置环境）。**前置不确定点**：该效果链挂在 Native 音频管线，对 ArkTS 层 AVPlayer 输出如何挂接需先读 Native d.ts 确认路径（可能需要 Native XComponent/音频通路改造，工程量大）。
- **完成状态**：📋 已规划（彩蛋定位），未实现，**先 spike 再承诺**。
- **工程量**：中-大（Native 侧改造）。
- **风险与注意**：高。若挂接成本过高则放弃，保持彩蛋定位不进主线排期。

## 15. P2：NFC 歌单标签（NDEF Tag）

- **功能名**：碰一碰切歌单
- **效果**：床头/车上贴一张 NFC 标签写入歌单 ID，手机碰一下自动切到对应歌单开始播放。
- **实现理论基础**：`@ohos.nfc.tag`（`ohos.permission.NFC_TAG`）——应用内前台分发 `registerForegroundDispatch` 读取 NDEF 记录（歌单 ID 或深链 URI）；NDEF Application Record 还可顺带拉起应用。
- **完成状态**：📋 已规划，未实现。
- **工程量**：小-中。读取 + 歌单路由。
- **风险与注意**：低。需用户自备 NFC 标签（NTAG213 几毛钱一张）；无标签时功能完全无感，适合做成「实验室」入口里的隐藏功能。

## 16. P2：折叠屏演奏台（Fold Angle）

- **功能名**：半折悬停播放台
- **效果**：折叠屏半折立在桌面时，下屏变控制面板（进度/切歌/音量），上屏展示封面与歌词，形成「演奏台」形态。
- **实现理论基础**：`display.on('foldStatusChange')` + `display.on('foldAngleChange')`（API 12+，无需权限）——半折态（`FOLD_STATUS_HALF_FOLDED`）触发上下分屏布局切换。本工程已有折叠屏 LG 断点适配基础，属增量改造。
- **完成状态**：📋 已规划，未实现。
- **工程量**：中。NowPlayingPage 半折布局分支。
- **风险与注意**：低。仅折叠屏用户可感知；需真机（Mate X 系）验证转轴角度阈值。

---

## 17. 明确不做清单（调研后排除）

| 能力 | 排除原因 |
| :--- | :--- |
| AR 贴纸 / AR Engine | 与音乐播放场景不契合，无自然结合点 |
| 骨骼点体感 | 同上 |
| 智能抠图 / 主体分割 | 同上（无视觉媒体流） |
| BLE 雷达寻物 | 与播放器无关的独立产品 |
| 防窥检测（dlpAntiPeep） | 资质门槛高且场景牵强 |
| 动态壁纸 / AOD 自定义 / 注视不熄屏 | 系统私有 API，不向三方开放 |
| `effectKit.createColorPicker` 取色 | 项目自研 ColorScience（CIE Lab / ΔE00）更精细，不换 |

---

## 18. 落地提示（全局）

- **权限现状**：工程已声明 `INTERNET` / `GET_NETWORK_INFO` / `FILE_ACCESS_PERSIST` / `KEEP_BACKGROUND_RUNNING`；清单内新增权限均为 normal 级（`VIBRATE` / `ACCELEROMETER` / `NFC_TAG` / `DISTRIBUTED_DATASYNC`）或 user_grant 弹窗（`MICROPHONE`），无 restricted 级。
- **资质门槛**：仅 §8 实况窗与 §13 待机屏保需 AGC 申请；其余全部零门槛。
- **推进建议**：§1 波形震感（半天爽点）→ §2 隔空手势（API 26 独占卖点，先真机 spike）→ §3 桌面卡片（用户留存利器）；三项互不依赖、均无需资质。
- **验证边界**：本文档所有「实现理论基础」为 API 文档级调研，未经真机验证；涉及传感器、马达、投屏、PiP、跨端的行为均需在 Windows 工作站真机执行后回填状态。
