# SASE Control（macOS）

[English](README.md)

以 Bash 腳本停止與恢復 macOS 上的 NETGEAR SASE，以及相關背景服務，包括 Velociraptor 與 Wazuh。

`down` 停用服務，設定跨重開機保留；`up` 重新啟用與啟動服務。腳本不卸載軟體，也不變更執行檔權限。

**停止這些服務也會停止端點監控，並可能中斷私人網路資源的存取。** 恢復服務後，相關能力也會重新啟用。

## 適用安裝方式

針對以下安裝結構撰寫：

- Apple Silicon macOS 上的 NETGEAR SASE 4.9.7。
- Homebrew 位於 `/opt/homebrew`。
- SASE 位於 `/Applications/SASE.app`。
- 下方列出的六項 launchd 服務。
- macOS `/bin/bash` 3.2 或更新版本。

使用前請核對安裝路徑與服務名稱。本腳本並非適用於所有 NETGEAR SASE 版本與部署方式的通用控制器。

## 使用方式

```bash
git clone https://github.com/ch010060/sase-control.git
cd sase-control
```

唯讀查看服務與程序：

```bash
bash ./sase-please.sh status
```

預覽操作，不執行需要權限的指令：

```bash
bash ./sase-please.sh --dry-run down
bash ./sase-please.sh --dry-run up
```

停止 SASE 與相關服務：

```bash
bash ./sase-please.sh down
```

恢復服務：

```bash
bash ./sase-please.sh up
```

真正執行 `up` 與 `down` 時會透過 `sudo` 要求管理員權限。使用 `bash` 執行，不需安裝或 `chmod`。

`up` 恢復服務，不覆寫 App 原有的手動斷線或登入設定；必要時請從 SASE 選單按 Connect 或完成登入。服務需要啟動時間，已載入不代表 VPN 已連線。

## 管理的服務

| launchd Label | 元件 |
|---|---|
| `net.speerity.monagent` | 定期網路監看與代理程式修復 |
| `net.speerity.saseapp` | SASE.app 常駐啟動器 |
| `net.speerity.comagent` | 本機控制服務 |
| `net.speerity.agent` | VPN 服務 |
| `com.velocidex.velociraptor` | Velociraptor 代理程式 |
| `com.wazuh.agent` | Wazuh 啟動器與代理程序 |

`down` 先停用全部六項 launchd Label，再依序卸載，優先停止定期修復監看服務。適用時呼叫 `wazuh-control stop`，再終止剩餘的匹配程序。先送 TERM，五秒後仍存在的程序再送 KILL。

如果 `/var/run/wireguard/speerity.name` 存在，則呼叫已安裝的 `wg-quick down /opt/homebrew/etc/wireguard/speerity.conf`；通道的路由與 DNS 清理由 WireGuard 處理。不停止所有 `wireguard-go` 程序，也不操作其他 WireGuard VPN 設定檔。

`up` 重新啟用並載入六項服務，啟動非排程服務，最後恢復修復監看服務原有的排程。

## 限制與回復

- launchd 停用設定會跨重開機保留，直到重新啟用。`up` 會啟用全部六項服務，不是依快照還原各項原本的個別狀態。
- 沒有或無法讀取 `speerity.name`，不代表所有 VPN 都已斷線。`status` 回報服務與程序狀態，不進行端到端連線驗證。
- 操作或停止驗證失敗會回傳非零值；請先檢查錯誤，再判定是否停止成功。若停用服務失敗，不繼續卸載；已完成的停用可以用 `up` 重新啟用。
- 部分停止後，可執行 `up` 回復服務。若服務 plist 缺失會回報錯誤，不自行下載或重裝。
- 正常服務啟停可能改變 VPN 路由與 DNS。目前未完整驗證從連線中停止通道、DNS 回復、重開機後狀態與長時間運作。
- MDM、管理工具、更新程式或手動重新開啟 App，可能重新啟用服務或改變安裝結構。之後新增的服務不在本腳本固定範圍內。
- 不修改 App 二進位檔、服務 plist、VPN 設定檔、sudoers 或 macOS 隱私權授權；相關軟體仍可能在正常啟停時更新自身狀態與日誌。

## 致謝

啟停介面參考 [Zscaler please](https://gist.github.com/christopher-hopper/c8033839ef927a201feb8a8e8d256ed7) 的可逆操作方式，依適用 SASE 安裝的服務名稱與路徑重新實作。

## 授權

[MIT](LICENSE)。
