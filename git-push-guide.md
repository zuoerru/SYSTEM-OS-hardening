# Git 推送操作指南

## 概述

本文档记录了向 GitHub 推送代码的方法，特别是使用 SSH 密钥进行身份验证的流程。

## 仓库信息

- **仓库地址**: `https://github.com/zuoerru/SYSTEM-OS-hardening.git`
- **SSH 地址**: `git@github.com:zuoerru/SYSTEM-OS-hardening.git`
- **本地分支**: `master`
- **远程分支**: `origin/master`

## 推送步骤

### 1. 确保 Git 仓库已初始化

如果还没有初始化 Git 仓库：

```bash
git init
```

### 2. 添加远程仓库

使用 SSH 协议添加远程仓库：

```bash
git remote add origin git@github.com:zuoerru/SYSTEM-OS-hardening.git
```

如果已经添加过，可以查看远程仓库：

```bash
git remote -v
```

### 3. 配置 SSH 密钥

#### 查看可用的 SSH 密钥

```bash
ls -la ~/.ssh/
```

#### 启动 SSH Agent 并添加密钥

```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519_new
```

#### 测试 SSH 连接

```bash
ssh -T git@github.com
```

成功后会显示：
```
Hi zuoerru/SYSTEM-OS-hardening! You've successfully authenticated, but GitHub does not provide shell access.
```

### 4. 添加和提交文件

```bash
# 添加所有文件
git add .

# 提交更改
git commit -m "提交信息"
```

### 5. 推送到远程仓库

#### 方法一：使用 GIT_SSH_COMMAND 指定密钥

```bash
GIT_SSH_COMMAND="ssh -i ~/.ssh/id_ed25519_new -o IdentitiesOnly=yes" git push -u origin master
```

**参数说明**：
- `-i ~/.ssh/id_ed25519_new`: 指定使用的 SSH 私钥
- `-o IdentitiesOnly=yes`: 只使用指定的密钥，不使用 SSH agent 中的其他密钥

#### 方法二：配置 SSH Config（推荐长期使用）

编辑 `~/.ssh/config` 文件：

```bash
cat >> ~/.ssh/config << 'EOF'
Host github.com-SYSTEM-OS-hardening
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519_new
    IdentitiesOnly yes
EOF
```

然后修改远程仓库 URL：

```bash
git remote set-url origin git@github.com-SYSTEM-OS-hardening:zuoerru/SYSTEM-OS-hardening.git
```

之后可以直接推送：

```bash
git push -u origin master
```

### 6. 验证推送结果

推送成功后，会显示类似以下信息：

```
Enumerating objects: 10, done.
Counting objects: 100% (10/10), done.
Delta compression using up to 2 threads
Compressing objects: 100% (9/9), done.
Writing objects: 100% (10/10), 15.83 KiB | 1.44 MiB/s, done.
Total 10 (delta 3), reused 0 (delta 0), pack-reused 0 (from 0)
remote: Resolving deltas: 100% (3/3), done.
To github.com:zuoerru/SYSTEM-OS-hardening.git
 * [new branch]      master -> master
branch 'master' set up to track 'origin/master'.
```

## 常见问题

### 1. 错误："The key you are authenticating with has been marked as read only"

**原因**: SSH 密钥被标记为只读权限

**解决方案**:
- 使用有写入权限的 SSH 密钥
- 或者在 GitHub 仓库设置中添加 Deploy Key 并勾选 "Allow write access"

### 2. 错误："Could not open a connection to your authentication agent"

**原因**: SSH Agent 未启动

**解决方案**:
```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519_new
```

### 3. 错误："Permission denied (publickey)"

**原因**: SSH 密钥未添加到 GitHub 或密钥不匹配

**解决方案**:
- 确认公钥已添加到 GitHub 账户或仓库的 Deploy Keys
- 确认使用的是正确的私钥

## 常用命令速查

| 命令 | 说明 |
|------|------|
| `git status` | 查看仓库状态 |
| `git add .` | 添加所有更改的文件 |
| `git commit -m "消息"` | 提交更改 |
| `git push` | 推送到远程仓库 |
| `git pull` | 从远程仓库拉取更新 |
| `git log` | 查看提交历史 |
| `git remote -v` | 查看远程仓库地址 |

## 最佳实践

1. **定期提交**: 小步快跑，频繁提交
2. **写有意义的提交信息**: 描述清楚本次提交的内容
3. **先拉取再推送**: 避免冲突，`git pull` 后再 `git push`
4. **使用 SSH**: 比 HTTPS 更安全，且不需要每次输入密码
5. **保护好私钥**: 不要分享或上传私钥文件

## 参考链接

- [GitHub SSH 文档](https://docs.github.com/en/authentication/connecting-to-github-with-ssh)
- [Git 官方文档](https://git-scm.com/doc)

---

**最后更新**: 2026-03-12
