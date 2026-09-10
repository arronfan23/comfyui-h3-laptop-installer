# ComfyUI + H3 一键安装器（笔记本版 / Windows）

> 由 **三猫云 SanMaoCloud** 打包维护

一条命令在笔记本上装好 **ComfyUI + MiniMax H3（Hailuo 3）模型**，并自动配置好
**Codex ↔ ComfyUI 的 MCP 控制接口**——装完直接让 Codex 用自然语言帮你画图、生成视频。

本版为**笔记本适配版**：按 **RTX 3080 Laptop 16GB 显存 + 32GB 内存** 调优，
与桌面版相比做了三处精简：

| 调整 | 说明 |
| --- | --- |
| 主模型 | 换为 **INT4/INT8 混合量化**（14~15GB/个），官方推荐的 16GB 显存档位 |
| 文本编码器 | 保留 **32B**（nvfp4 版，15.6GB；该编码器不挑显卡架构，3080 可用）。注意 H3 模型必须搭配 32B 编码器（5120 维），4B 版（2560 维）会直接报错 |
| 启动参数 | 默认 `--lowvram` 低显存模式，权重自动在显存/内存间调度 |
| 下载总量 | 约 **58GB**（桌面版 70GB） |

## 快速开始

1. 点击页面右上角 **Code → Download ZIP** 下载
   （或 `git clone https://github.com/arronfan23/comfyui-h3-laptop-installer.git`）
2. **右键下载的 ZIP →「全部解压缩」**（不要在压缩包窗口里直接双击！）
3. 打开解压后的文件夹，双击 **`一键安装.bat`**
   - 若出现"Windows 已保护你的电脑"：点「更多信息」→「仍要运行」
4. 等待完成（视网速 1~2 小时，模型支持断点续传）

完成后会自动启动 ComfyUI 并打开 http://127.0.0.1:8188 。

## 系统要求

- Windows 10 / 11 64 位笔记本
- NVIDIA 显卡，**显存 16GB**（按 RTX 3080 Laptop 调试；12GB+ 显存的其他型号也可尝试）
- **内存 32GB**（低显存模式下模型权重经内存调度，内存不足会明显变慢）
- **显卡驱动 580 或更新版本**（PyTorch cu130 要求；安装器会自动检测并提示，
  笔记本驱动请到 [NVIDIA 官网](https://www.nvidia.cn/Download/index.aspx?lang=cn) 选择对应型号下载）
- 磁盘剩余 **60GB+**
- 全程联网（国内网络无需配置，HuggingFace 不通会自动切换 hf-mirror 镜像）

## 它会自动做什么

| 步骤 | 内容 |
| --- | --- |
| 主程序 | 下载 ComfyUI（固定提交 `34744cd`，含 H3 支持的官方 master） |
| 自定义节点 | ComfyUI-Manager + 界面中文翻译 |
| Python | 没有 Python 3.12 则自动静默安装（当前用户，无需管理员） |
| 依赖 | venv + PyTorch 2.11 (cu130) + 全部锁定版本依赖 |
| 模型 | 从 HuggingFace 官方仓库下载 H3 模型（断点续传，国内自动切镜像） |
| MCP | 内置 comfyui-mcp + Node.js 便携版，自动写入 Codex `config.toml` |

## 日常使用

1. 双击安装目录里的 **`启动ComfyUI.bat`**（已带 `--lowvram`）
2. 打开 Codex，直接说"帮我画一张……" / "生成一段……的视频"即可

## 高级选项

```powershell
# 自定义安装目录
powershell -ExecutionPolicy Bypass -File installer\install.ps1 -InstallDir "E:\AI\ComfyUI"

# 国内用户强制走镜像下载模型
powershell -ExecutionPolicy Bypass -File installer\install.ps1 -UseMirror

# 只装环境不下模型（之后可重跑补齐）
powershell -ExecutionPolicy Bypass -File installer\install.ps1 -SkipModels
```

中断后重跑同一命令即可：已完成步骤自动跳过，模型自动断点续传。

## 模型清单与来源

安装时从 HuggingFace 官方仓库直接下载（本仓库不转存模型文件）：

| 文件 | 大小 | 来源 |
| --- | --- | --- |
| `diffusion_models/MiniMax_H3_Ref2VA_pruned_mixed_int4_int8_convrot.safetensors` | 14.1 GB | [Abiray/Minimax-H3-nvfp4-INT4-INT8-Convrot](https://huggingface.co/Abiray/Minimax-H3-nvfp4-INT4-INT8-Convrot) |
| `diffusion_models/MiniMax_H3_FL2VA_pruned_mixed_int4_int8_convrot.safetensors` | 14.8 GB | 同上 |
| `text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors` | 14.6 GB | [Comfy-Org/MiniMax-H3](https://huggingface.co/Comfy-Org/MiniMax-H3) |
| `vae/minimax_h3_video_vae_fp16.safetensors` | 4.9 GB | 同上 |
| `vae/minimax_h3_audio_vae_fp32.safetensors` | 0.6 GB | 同上 |

模型的使用许可以 HuggingFace 上对应仓库的说明为准。

## 桌面版

台式机大显存（16GB+，如 RTX 5080）请用完整版（含 32B 文本编码器，质量更高）：
[comfyui-h3-installer](https://github.com/arronfan23/comfyui-h3-installer)

## 免责声明

本项目仅为安装脚本，不包含也不分发任何模型权重；模型均于安装时从上述
官方仓库下载，其使用权与限制以各仓库许可证为准。ComfyUI 遵循其
[GPL-3.0 许可证](https://github.com/comfyanonymous/ComfyUI/blob/master/LICENSE)。
