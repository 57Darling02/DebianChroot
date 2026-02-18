# fake_systemd

**fake_systemd** 是一个专为无 Systemd 环境（如 Docker 容器、Alpine Linux、Android chroot/proot）设计的高性能、轻量级 Systemd 兼容层。

它的核心目标是：**让你在不支持 Systemd 的环境中，依然可以使用标准的 `systemctl` 命令来管理服务。**

它并不模拟复杂的 Systemd 依赖树，而是将 `systemctl` 命令智能转换为底层的 Runit (`sv`) 操作，实现了**命令级兼容**。

---

## 🚀 快速上手 (Quick Start)

在已经部署了 fake_systemd 的环境中，你可以像在标准 Linux 发行版中一样使用 `systemctl`。

### 1. 服务状态查询
```bash
# 查看所有正在运行的服务
systemctl status

# 查看特定服务的详细状态
systemctl status nginx
systemctl status sshd
```

### 2. 服务生命周期管理
```bash
# 启动服务
systemctl start nginx

# 停止服务
systemctl stop nginx

# 重启服务
systemctl restart nginx

# 重新加载配置 (SIGHUP)
systemctl reload nginx
```

### 3. 开机自启管理
```bash
# 设置开机自启 (Enable)
# 这会自动将服务配置链接到激活目录
systemctl enable nginx

# 取消开机自启 (Disable)
# 这会停止服务并移除链接
systemctl disable nginx
```

---

## 🛠️ 进阶：如何添加新服务

fake_systemd 支持标准的 Systemd `.service` 文件解析，但采用了**半自动化**的策略来确保稳定性。

### 步骤 1: 安装服务包
通常你可以直接通过包管理器安装服务，例如：
```bash
apt install nginx
# 或者
apt install openssh-server
```
安装过程中，包管理器可能会报错说 Systemd 不存在，**这是正常的，请忽略**。

### 步骤 2: 启用服务 (自动转换)
使用 `enable` 命令，fake_systemd 会自动扫描 `/lib/systemd/system` 或 `/etc/systemd/system` 下的 `.service` 文件，并将其转换为 Runit 脚本。

```bash
systemctl enable nginx
```

**⚠️ 关键提示：**
你会看到如下输出：
```text
[INFO] Found service file at /lib/systemd/system/nginx.service
[WARN] Runit script generated at: /opt/fake_systemd/etc/sv/nginx/run
[WARN] YOU MUST REVIEW AND EDIT THIS SCRIPT BEFORE STARTING!
```
**fake_systemd 不会替你做决定。** Systemd 服务通常是后台运行 (`Type=forking`)，而 Runit 强制要求服务在前台运行 (`Foreground`)。

### 步骤 3: [必须] 修改启动脚本
根据上一步的提示，编辑生成的 `run` 脚本：

```bash
vi /opt/fake_systemd/etc/sv/nginx/run
```

你需要检查 `exec` 行，确保服务**在前台运行**：

*   **Nginx**: 
    *   ❌ `exec /usr/sbin/nginx` (错误：会后台运行导致 Runit 认为服务挂了并无限重启)
    *   ✅ `exec /usr/sbin/nginx -g 'daemon off;'` (正确)
*   **SSHD**:
    *   ❌ `exec /usr/sbin/sshd`
    *   ✅ `exec /usr/sbin/sshd -D` (正确)
*   **Apache**:
    *   ✅ `exec /usr/sbin/apache2ctl -D FOREGROUND`

### 步骤 4: 启动服务
确认脚本无误后，启动服务：
```bash
systemctl start nginx
```

---

## 🔍 原理与目录结构

fake_systemd 是**环境自洽 (Self-contained)** 的，所有数据都存储在 `/opt/fake_systemd` 下，不污染系统根目录。

*   **二进制路径**: `/opt/fake_systemd/bin/` (包含 `systemctl`, `fake_systemd`, `sv` 等)
*   **服务仓库**: `/opt/fake_systemd/etc/sv/` (存放所有已转换的服务配置)
*   **运行目录**: `/opt/fake_systemd/service/` (存放当前激活/正在运行的服务)
*   **日志目录**: `/opt/fake_systemd/var/log/`

### 兼容性命令
为了兼容依赖 Systemd 的安装脚本，以下命令会被**拦截并静默成功**（即什么都不做，但返回 0）：
*   `daemon-reload`
*   `mask` / `unmask`
*   `preset`
*   `reset-failed`

---

## ❓ 常见问题 (FAQ)

**Q: 为什么 `systemctl status` 显示 PID 但服务没反应？**
A: 请检查服务的日志。通常是因为服务在后台运行了，Runit 会不断重启它。请参考“步骤 3”修改启动参数。

**Q: 我可以直接使用 `sv` 命令吗？**
A: **当然可以！** fake_systemd 底层就是 Runit。你可以直接使用 `sv status nginx` 或 `sv up nginx`，效果与 `systemctl` 完全一致。

**Q: 如何查看服务日志？**
A: fake_systemd 默认将所有服务的标准输出/错误输出重定向到自己的日志系统。你可以查看 `/opt/fake_systemd/var/log/` 下的文件，或者直接使用 `svlogd` (如果已配置)。对于简单调试，直接看 `systemctl status <service>` 的输出即可。
