# HDS 沉浸光感摸底（S0 spike）

日期：2026-08-29 · 目标：验证 `@kit.UIDesignKit`（HDS 组件 + 沉浸光感/材质 API）在本机
CLT 工具链（6.1.1.300，SDK 6.1.1.125 / API 24）下的编译与运行可用性，为 S2/S3 的
官方光感路线提供决策依据。

## 结论：编译全绿（FULL GO），运行时待模拟器验证

| 能力 | 编译 | 备注 |
|---|---|---|
| `hdsMaterial.getSystemMaterialTypes()` | ✅ | 探针按钮输出设备材质能力（含 IMMERSIVE 与否） |
| `hdsEffect.pointLight` → `.visualEffect()` | ✅ | 光晕/bloom 打在任意 ArkUI 组件上 |
| `hdsEffect.pressShadow` → `.visualEffect()` | ✅ | 官方按压阴影 |
| `HdsVisualComponent().scene(DUAL_EDGE_FLOW_LIGHT_…)` | ✅ | 双边流光 + 渐变背景遮罩场景 |
| `HdsTabs` + `barFloatingStyle`（含 `miniBar`、`lightColor`） | ✅ | `barFloatingStyle` 不在 hds_tabs.json attrs 里也能编译——transform 不按 json 白名单拦截属性 |
| `HdsNavigation` + `HdsNavDestination` + 现有 `NavPathStack` | ✅ | 见下方 @Builder 模式 |

## 两个关键坑与解法

### 1. `Cannot find name 'HdsTabsAttribute'`（所有 HDS 组件共有）

ArkUI transform 为组件生成的代码以「裸全局名」引用其 Attribute 类；内部组件靠
`ets-loader/declarations/*.d.ts` 的 ambient 声明解析，而 hms 树只有
`components/*.json`、没有 declarations 桥。

**解法：在使用文件里显式导入 Attribute 类型（kit 本身有导出）：**

```ts
import { HdsTabs, HdsTabsAttribute } from '@kit.UIDesignKit';
```

组件注册本身没问题：hvigor 插件把 `hms/ets` 注入 `externalApiPaths`
（debug 日志 `Compile arkts with external api path: …\sdk\default\hms\ets`），
ets-loader 的 `readExternalComponents()` 据此合并 HDS 组件配置。

### 2. `.navDestination(() => { HdsNavDestination() {…} })` 语法错误

被补丁过的 TS 解析器只在 struct `build()` 与 `@Builder` 方法内开启
「组件表达式」解析上下文；箭头函数回调里只有语法组件（ForEach 等）继承该上下文。
`HdsNavigation(){}` 尾随 lambda 在 build() 里没问题，但 NavDestinationBuilder
回调内的组件必须搬到 `@Builder` 方法：

```ts
@Builder
hdsDestBuilder(name: string, pageInfos: Object) {
  if (name === 'hds_spike_dest') {
    HdsNavDestination() { … }.hideTitleBar(true)
  }
}
build() {
  HdsNavigation(this.navStack) { … }
    .navDestination((name: string, pageInfos: Object): void => this.hdsDestBuilder(name, pageInfos))
}
```

注意 `NavDestinationBuilder` 签名是 `(name, pageInfos)`，与 ArkUI `Navigation` 的
无参 builder 不同。

## 运行时验证清单（模拟器，2026-08-29 实测）

- [x] 应用启动/调试页/探针面板全程**无崩溃**——HDS 组件可在模拟器上挂载
- [x] **HdsTabs + barFloatingStyle 渲染成功**：S6 探针出现了官方悬浮胶囊底栏
  （甲/乙，选中蓝色高亮）——悬浮壳路线运行时可行
- [x] **HdsNavigation 推入成功**：pushPath 后目标页 chrome（返回键）出现
- [x] **S4 实测（关键结论）：HdsNavigation 与 HdsNavDestination 的路由内容
  子树在模拟器上不挂载**（目标页只剩标题栏 chrome，NowPlayingPage 整页空白
  同症状；标准 Navigation/NavDestination 正常）。外壳已回退标准组件，
  HdsNavigation/HdsNavDestination 待真机或后续 SDK 复核后再启用；
  HdsTabs（含 barFloatingStyle/miniBar）不受影响，已上线
- [x] **HdsVisualComponent 有渲染但很淡**：仅两侧可见微弱流光痕迹，
  backgroundMaskColors 渐变未显出——S2 需调参（颜色带 alpha / 场景尺寸）
- [x] `getSystemMaterialTypes()` 返回 **`[]`（空数组）**：模拟器不支持任何
  HDS 材质。**降级路径必须保留**——所有 `systemMaterialEffect` 调用点都要有
  自绘玻璃兜底；真实设备（HarmonyOS 6.x）预计返回含 IMMERSIVE 的数组，待真机复核
- [x] 动态配色管线运行正常：播放无封面歌曲时回落中性方案并已上色
  （迷你播放器播放键/背景 accent 层为色卡吸附的中性色）；
  effectKit 取色路径执行无异常
- [ ] 彩色封面（高饱和）下的重点色与对比度——留待 S2 验收一并截图验证
- [ ] WithTheme 整树重绘（换歌时非订阅组件是否刷新）——留待 S2 验收

## 工程影响

- HDS 不需要任何 ohpm 依赖，`import from '@kit.UIDesignKit'` 即可；运行时依赖系统
  HSP（`com.huawei.hmos.hdscomponent`）。
- 新增 @hms 引用会带来 codelinter 计数变化（探针面板本身贡献了 1 条
  avoid-overusing-custom-component warn）；S0 收尾清理探针面板时一并消除。
- 探针入口：调试页顶部「HDS 沉浸光感探针」分区（`HdsSpikePanel`），S3 落地后移除。
