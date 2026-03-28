# hvigor 构建与发布

## 1. 命令入口与任务图
- 推荐入口：`tools/hvigor-local.cmd`
- 该脚本通过 DevEco 内置 Node 执行 hvigor，避免系统 Node 漂移
- 根工程支持 `clean / assembleHar / assembleHap / test`

```bat
:: tools/hvigor-local.cmd（节选）
set "NODE_EXE=%DEVECO_HOME%\tools\node\node.exe"
set "HVIGOR_JS=%DEVECO_HOME%\tools\hvigor\hvigor\bin\hvigor.js"
"%NODE_EXE%" "%HVIGOR_JS%" --no-daemon %*
```

## 2. 构建命令序列（开发与发布前）
```powershell
# 开发回归序列
ohpm install
tools\hvigor-local.cmd clean
tools\hvigor-local.cmd assembleHar
tools\hvigor-local.cmd assembleHap
tools\hvigor-local.cmd test
```

```powershell
# 发布前最小序列（仍然先库后应用）
tools\hvigor-local.cmd clean
tools\hvigor-local.cmd assembleHar
tools\hvigor-local.cmd assembleHap
```

## 3. release 配置事实（真实文件）
- `build-profile.json5`：`buildOptionSet.release.arkOptions.obfuscation.ruleOptions.enable = true`
- 根 `build-profile.json5`：只有 `debug` 与 `release` 两个模式

```json5
// build-profile.json5（release 节选）
{
  "buildOptionSet": [
    {
      "name": "release",
      "arkOptions": {
        "obfuscation": {
          "ruleOptions": {
            "enable": true,
            "files": ["./obfuscation-rules.txt"]
          },
          "consumerFiles": ["./consumer-rules.txt"]
        }
      }
    }
  ]
}
```

## 4. 常见错误与修复命令

### 4.1 构建脚本入口不可用
```powershell
# 修正 DEVECO_HOME 后重新执行
notepad tools\hvigor-local.cmd
tools\hvigor-local.cmd clean
```

### 4.2 release 行为异常（仅 release 出现）
```powershell
# 先重跑完整链路确认可复现
tools\hvigor-local.cmd clean
tools\hvigor-local.cmd assembleHar
tools\hvigor-local.cmd assembleHap
tools\hvigor-local.cmd test

# 然后检查混淆规则文件
Get-Content OCORM\build-profile.json5
Get-Content OCORM\obfuscation-rules.txt
Get-Content OCORM\consumer-rules.txt
```

### 4.3 模块依赖解析异常
```powershell
ohpm install
tools\hvigor-local.cmd clean
tools\hvigor-local.cmd assembleHar
tools\hvigor-local.cmd assembleHap
```

## 5. 引用的真实文件
- `tools/hvigor-local.cmd`
- `build-profile.json5`
- `build-profile.json5`
- `obfuscation-rules.txt`
- `consumer-rules.txt`
