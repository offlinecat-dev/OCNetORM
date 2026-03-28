# 模块结构与产物（HAR/HAP）

## 1. 模块事实（来自真实 module.json5）
- `src/main/module.json5`：`module.type = "har"`
- `../entry/src/main/module.json5`：`module.type = "entry"`
- 根编排 `build-profile.json5` 同时声明 `entry` 与 `ocorm`

```json5
// src/main/module.json5
{
  "module": {
    "name": "ocorm",
    "type": "har",
    "deviceTypes": ["default", "tablet", "phone", "2in1"]
  }
}
```

```json5
// ../entry/src/main/module.json5（节选）
{
  "module": {
    "name": "entry",
    "type": "entry",
    "mainElement": "EntryAbility",
    "deliveryWithInstall": true,
    "installationFree": false
  }
}
```

## 2. 依赖关系与产物边界
- `entry` 通过本地依赖引入 `ocorm`：`../entry/oh-package.json5 -> "ocorm": "file:../OCORM"`
- `ocorm` 的包信息由 `oh-package.json5` 定义，当前版本 `3.0.2`
- 构建顺序必须保持：先 HAR，后 HAP

```json5
// ../entry/oh-package.json5（节选）
{
  "dependencies": {
    "ocorm": "file:../OCORM"
  }
}
```

```json5
// oh-package.json5（节选）
{
  "name": "ocorm",
  "version": "3.0.2",
  "main": "Index.ets",
  "publishConfig": {
    "registry": "https://ohpm.openharmony.cn/#/"
  }
}
```

## 3. 构建命令序列（HAR -> HAP）
```powershell
ohpm install
tools\hvigor-local.cmd clean
tools\hvigor-local.cmd assembleHar
tools\hvigor-local.cmd assembleHap
```

## 4. 常见错误与修复命令

### 4.1 `assembleHap` 失败但 `assembleHar` 成功
```powershell
# 检查 entry 模块声明
Get-Content entry\src\main\module.json5

# 检查本地依赖路径
Get-Content entry\oh-package.json5

# 重新解析依赖并重建
ohpm install
tools\hvigor-local.cmd clean
tools\hvigor-local.cmd assembleHap
```

### 4.2 运行期找不到 `ocorm` 导出 API
```powershell
# 检查库包入口与版本
Get-Content OCORM\oh-package.json5

# 重新构建 HAR + HAP
tools\hvigor-local.cmd assembleHar
tools\hvigor-local.cmd assembleHap
```

## 5. 引用的真实文件
- `build-profile.json5`
- `src/main/module.json5`
- `../entry/src/main/module.json5`
- `../entry/oh-package.json5`
- `oh-package.json5`
