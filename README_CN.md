# DebianChroot Magisk 模块

这是一个在 Android 设备上部署完整 Debian Bookworm rootfs 的 Magisk 模块，内置了 Runit 服务管理和强大的辅助工具 (`lm`)。

## 功能特性

- **完整 Debian 12 (Bookworm)**: 在 Android 上运行完整的 Debian 环境。
- **Runit 服务管理**: 集成 `runit` init 系统，用于管理后台服务。
- **无缝集成**:
  - 自动挂载 Android 的 `/dev`, `/proc`, `/sys`, `/system`, `/data`, 和 `/sdcard`。
  - 修复网络权限和 Android 特有的 GID 问题。
- **Linux 管理器 (`lm`)**: 内置辅助工具，轻松管理容器：
  - **一键换源**: 切换到更快的本地镜像源 (通过 LinuxMirrors)。
  - **SSH 服务设置**: 轻松配置并启动 SSH 服务。
  - **TMOE 集成**: 启动 TMOE 工具进行高级管理。
  - **Systemd 模拟**: 包含 `servicectl` 用于模拟 systemd 的服务控制体验。

## 安装

1. 下载最新的 Release zip 文件。
2. 通过 Magisk Manager 或 KernelSU 安装模块。
3. 重启设备。

## 使用方法

### 进入容器

你可以通过终端模拟器（如 Termux）或 ADB 访问 Debian shell。

1. 打开终端。
2. 切换到 root 用户：
   ```bash
   su
   ```
3. 运行启动脚本：
   ```bash
   /data/adb/modules/DebianChroot/scripts/start.sh
   ```
   *(如果容器服务未运行，此脚本会自动启动它们，然后进入 shell。)*

### 管理容器 (`lm`)

进入容器后，只需输入 `lm` 即可打开管理菜单：

```bash
root@localhost:~# lm
```

在此菜单中，你可以：
- 安装基础依赖。
- 切换软件源镜像。
- 配置 SSH（端口、密码、公钥）。
- 启动 TMOE 工具。
- 修复/设置服务控制。

### 服务管理

容器使用 **Runit** 作为 init 系统。服务配置文件位于 `/etc/service`。

- **检查状态**: `sv status <服务名>`
- **启动/停止**: `sv start <服务名>` / `sv stop <服务名>`

你也可以使用内置的 `servicectl` 封装工具（通过 `lm` 配置）来获得类似 systemd 的体验：
```bash
servicectl start <服务名>
servicectl status <服务名>
```

#### 示例：配置 Nginx 使用 Runit 运行

以下是如何设置 Nginx 通过 Runit 自动运行的步骤，遵循标准规范（`/etc/sv` -> `/etc/service`）。

1.  **安装 Nginx**:
    ```bash
    apt update && apt install nginx
    ```

2.  **在 `/etc/sv` 中创建服务目录**:
    ```bash
    mkdir -p /etc/sv/nginx
    ```

3.  **创建运行脚本**:
    创建一个名为 `/etc/sv/nginx/run` 的文件，内容如下：
    ```bash
    #!/bin/sh
    # Nginx 必须在前台运行，以便 runit 能够监控它
    exec nginx -g 'daemon off;'
    ```

4.  **赋予执行权限**:
    ```bash
    chmod +x /etc/sv/nginx/run
    ```

5.  **启用服务 (软链接到 `/etc/service`)**:
    ```bash
    ln -s /etc/sv/nginx /etc/service/nginx
    ```

6.  **启动服务**:
    Runit 会在几秒钟内自动发现并启动新服务。你可以通过以下命令验证：
    ```bash
    sv status nginx
    # 或者
    servicectl status nginx
    ```

## 构建与发布

本项目包含 GitHub Actions workflow，支持自动发布。

1. Fork/Clone 本仓库。
2. 更新 `module.prop` 中的 `version` 和 `versionCode`。
3. 提交并推送更改到 GitHub。
4. Workflow 将自动构建 zip 包并创建一个新的 Release。

> **注意**: 请确保在仓库设置中开启了 "Read and write permissions" (Settings -> Actions -> General -> Workflow permissions)。

## 致谢

- **Debian**: 坚如磐石的操作系统。
- **Magisk**: 强大的模块系统。
- **BusyBox**: 必不可少的工具集。
- **TMOE/LinuxMirrors**: 很棒的辅助脚本。
