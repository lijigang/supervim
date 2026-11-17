# 稳定签名，让权限跟着升级走

Supervim 每次用新的 DMG 盖掉旧的 `Supervim.app` 时，系统都会要求重新打开辅助功能（Accessibility）和输入监控（Input Monitoring）。新旧两条在系统设置里都叫 Supervim，所以只能删掉旧行再加一次。

## 原因

发布脚本原来用 `codesign -s -` 做 ad-hoc 签名。这种签名的指定要求（designated requirement）里带的是这一次构建的 `cdhash`。代码一变，哈希就变。TCC 把每一版当成另一个应用，已经勾过的权限不会跟过去。

应用自己没有调用 `tccutil`，也没有改 bundle id。`App/Supervim/Info.plist` 里的标识一直是 `com.lijigang.supervim`，磁盘映像安装到的路径一直是 `/Applications/Supervim.app`。变的是签名，不是名字。

进程也读不到「系统设置里已经有一行、但这份二进制对不上」。`AXIsProcessTrusted()` 在从未授权和授权给了旧副本时都是 false，TCC 数据库不能从应用里列出来。所以权限窗口在缺权限时直接告诉用户：如果列表里已经有 Supervim，先选中它，按减号删掉，再把现在这份加回去并打开。从 ad-hoc 换成下面这张稳定证书时，这一步要做一次。之后的升级不再需要。

## 做法

每次发布都用同一张自签的代码签名证书。`codesign` 写出的指定要求是：

```text
identifier "com.lijigang.supervim" and certificate leaf = H"<证书的 SHA-1>"
```

`H"..."` 是证书的哈希，不是这一次构建的哈希，所以版本更新不会变。不需要付费的 Apple Developer 账号。Gatekeeper 的「无法验证开发者」警告还在，因为没有公证。

不想再看到 Gatekeeper 警告的话，用 Developer ID 证书并做公证（Apple Developer Program，每年 99 美元）。那是另一条路，不是这张自签证书能代替的。

没有用 hardened runtime。这张证书不是 Apple 颁发的，应用也没有 entitlements 文件。加上 runtime 并不能让 TCC 更稳定。

## 只做一次的设置

在自己的 Mac 上，不要在仓库目录里生成密钥：

```bash
cd /path/to/supervim
SUPERVIM_SIGNING_P12_PASSWORD='选一个长密码' \
  scripts/make-signing-cert.sh "$HOME/supervim-signing"
```

脚本写出：

- `$HOME/supervim-signing/supervim-signing.key` 私钥
- `$HOME/supervim-signing/supervim-signing.crt` 证书
- `$HOME/supervim-signing/supervim-signing.p12` 带密码的 PKCS#12

证书的代码签名扩展是 `codeSigning`，有效期 7300 天（20 年）。脚本拒绝把这些文件写进 git 仓库。不要提交 `.p12` 或私钥。

把 p12 和密码放进这个仓库的 Actions secrets。本机已经 `gh auth login` 为 lijigang 时：

```bash
base64 < "$HOME/supervim-signing/supervim-signing.p12" | gh secret set SUPERVIM_SIGNING_P12_BASE64 --repo lijigang/supervim
gh secret set SUPERVIM_SIGNING_P12_PASSWORD --repo lijigang/supervim
```

第二条命令会等你把密码粘进去。密码就是上面 `SUPERVIM_SIGNING_P12_PASSWORD` 的值。

`scripts/sign-app.sh` 在 `scripts/package-dmg.sh` 里给放进映像的那一份 `Supervim.app` 签名。GitHub Actions 的 CI 和 Release 都会把这两个 secret 传进去。导入用临时钥匙串，签完就删。指定要求必须同时有 `identifier "com.lijigang.supervim"` 和 `certificate leaf = H"`，并且不能含 `cdhash`，否则这次构建失败。

两个 secret 有一个为空时，脚本退回 `codesign -s -`，并在日志里打出 `WARNING`。那种构建的权限仍然每次都要重授。

## 用户这边的最后一次授权

从 ad-hoc 的 0.1.x 换到这张证书的第一个版本时，系统设置里的旧行不会自动生效。打开 Supervim，按权限窗口的说明：在辅助功能和输入监控里删掉旧的 Supervim，再加入现在这份并打开开关。如果开关打开了进程仍提示没有权限，退出应用再打开一次。这一步没有在这台机器上对真机 TCC 验证过。

这之后，只要发布还用同一张证书、bundle id 还是 `com.lijigang.supervim`、安装路径还是 `/Applications/Supervim.app`，升级不再要求重新授权。换一张新证书，就又要做一次。
