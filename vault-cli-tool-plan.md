# HashiCorp Vault 管理工具實作計畫

## 專案概述

建立本地開發用的 Vault 管理命令行工具，使用 Shell Script 實作。

### 目標
- 使用 userpass 認證方式登入 Vault
- 支援 KV secrets 的完整 CRUD 操作
- 機敏資料透過環境變數管理，不納入版控
- 支援 JSON 和人類可讀的表格輸出格式

### Vault 環境資訊
- Vault 地址：`https://vault.web.internal`
- 跳過 TLS 驗證：`VAULT_SKIP_VERIFY=true`
- KV mount point：`secrets`
- 認證方式：userpass

---

## 實作步驟

### 階段 1：專案結構與環境配置

- [x] 步驟 1.1：建立專案目錄結構
  - 原因：組織程式碼和配置檔案，便於維護
  - 目錄結構：
    ```
    vault-manage-script/
    ├── vault-manage.sh              # Shell Script 主程式
    ├── .env.example              # 環境變數範本（不含機敏資料）
    ├── .gitignore                # Git 忽略檔案配置
    ├── README.md                 # 使用說明文檔
    └── EXAMPLES.md               # 使用範例文檔
    ```

- [x] 步驟 1.2：建立 `.gitignore` 檔案
  - 原因：確保機敏資料不會被納入版控
  - 內容：忽略 `.env`、備份檔案、日誌檔案、編輯器產生的檔案等

- [x] 步驟 1.3：建立 `.env.example` 範本檔案
  - 原因：提供環境變數設定範本，但不包含實際機敏資料
  - 內容：
    ```bash
    VAULT_ADDR=https://vault.web.internal
    VAULT_SKIP_VERIFY=true
    VAULT_USERNAME=your-username
    VAULT_PASSWORD=your-password
    ```

- [x] 步驟 1.4：建立專案 `README.md`
  - 原因：提供專案說明和使用指引
  - 內容：專案介紹、安裝步驟、環境配置說明、使用範例

### 階段 2：Shell Script 實作

- [x] 步驟 2.1：實作 Vault 連線與認證函式
  - 原因：建立與 Vault 的連線，處理 userpass 認證
  - 檔案：`vault-manage.sh`
  - 使用 `curl` + `jq`
  - 功能：
    - 從環境變數讀取配置
    - 使用 userpass 方法登入
    - 取得並儲存 token
    - 環境變數檢查
    - 依賴工具檢查
    - 完整錯誤處理

- [x] 步驟 2.2：實作讀取 secret 函式
  - 原因：讀取指定路徑的 KV secret
  - 檔案：`vault-manage.sh`
  - 功能：
    - 支援指定 mount 和 path
    - 使用 `jq` 處理 JSON 輸出
    - 支援表格格式輸出（使用 `column`）
    - 404 錯誤處理
    - 自動登入

- [x] 步驟 2.3：實作建立 secret 函式
  - 原因：建立新的 KV secret
  - 檔案：`vault-manage.sh`
  - 功能：
    - 支援 key-value pairs 輸入
    - 驗證輸入格式
    - 動態建立 JSON payload
    - 錯誤處理

- [x] 步驟 2.4：實作更新 secret 函式
  - 原因：更新現有的 KV secret
  - 檔案：`vault-manage.sh`
  - 功能：
    - 支援部分更新（merge）
    - 支援完整覆蓋（replace）
    - --replace 參數解析
    - 讀取現有資料進行 merge

- [x] 步驟 2.5：實作刪除 secret 函式
  - 原因：刪除指定的 KV secret
  - 檔案：`vault-manage.sh`
  - 功能：
    - 支援刪除確認提示
    - 防止誤刪
    - 使用 metadata API 永久刪除

- [x] 步驟 2.6：實作列出 secrets 函式
  - 原因：列出指定路徑下的所有 secrets
  - 檔案：`vault-manage.sh`
  - 功能：
    - 使用 metadata API LIST 方法
    - 區分目錄和檔案（📁 / 📄）
    - 404 處理（空路徑）

- [x] 步驟 2.7：實作 CLI 參數解析與主程式邏輯
  - 原因：提供友善的命令行介面
  - 檔案：`vault-manage.sh`
  - 使用 case 語句進行命令路由
  - 支援子命令：get, create, update, delete, list
  - 參數驗證與錯誤提示

- [x] 步驟 2.8：實作錯誤處理與輸出格式切換
  - 原因：提供清楚的錯誤訊息與彈性的輸出格式
  - 檔案：`vault-manage.sh`
  - 功能：
    - 檢查必要工具（curl, jq）
    - 處理連線錯誤
    - 處理認證失敗
    - 支援 --format json/table 參數
    - 彩色輸出（錯誤/成功/警告/資訊）
    - HTTP 狀態碼檢查
    - 404 特別處理

### 階段 3：測試與文檔

- [x] 步驟 3.1：功能測試
  - 原因：確保所有功能正常運作
  - 測試項目：
    - ✅ 使用說明顯示
    - ✅ 依賴工具檢查
    - ✅ 環境變數檢查
    - ✅ 錯誤訊息輸出
    - ⚠️ 實際 Vault 操作（需實際環境）

- [x] 步驟 3.2：建立使用範例文檔
  - 原因：提供實際使用案例參考
  - 檔案：`EXAMPLES.md`
  - 內容：
    - ✅ 環境設定（2 種方式）
    - ✅ 基本操作範例
    - ✅ 進階使用（批次操作、檔案處理）
    - ✅ 常見場景（初始化、密碼輪替、環境遷移、審計）
    - ✅ 疑難排解（5 種常見問題）
    - ✅ 安全最佳實踐

- [x] 步驟 3.3：完善專案 README
  - 原因：確保文檔完整且最新
  - 檔案：`README.md`
  - 內容：
    - ✅ 功能特色
    - ✅ 系統需求與安裝指引
    - ✅ 快速開始（環境設定、基本使用）
    - ✅ 完整命令說明
    - ✅ 輸出格式範例
    - ✅ 安全注意事項
    - ✅ 疑難排解
    - ✅ 參考資料連結

---

## 技術決策

### Shell Script 實作
- **API 呼叫**：使用 `curl` (通用性高，不需額外安裝 vault CLI)
- **JSON 處理**：`jq` (必要依賴，用於解析和格式化 JSON)
- **環境變數管理**：直接使用 shell 環境變數
- **輸出格式化**：
  - JSON：透過 `jq` 美化輸出
  - 表格：使用 `column` 或自訂格式化函式

### 安全性考量
1. **絕不將機敏資料寫入程式碼**
2. **使用 `.gitignore` 排除 `.env` 檔案**
3. **提供 `.env.example` 範本，不含實際密碼**
4. **Token 只存在於記憶體中，不寫入檔案**
5. **在文檔中明確標註安全注意事項**

---

## 依賴關係

```
步驟 1.1 (目錄結構)
  └─→ 步驟 1.2 (.gitignore)
      └─→ 步驟 1.3 (.env.example)
          └─→ 步驟 1.4 (專案 README)

步驟 2.1 (Shell 認證函式)
  └─→ 步驟 2.2 (讀取 secret)
  └─→ 步驟 2.3 (建立 secret)
  └─→ 步驟 2.4 (更新 secret)
  └─→ 步驟 2.5 (刪除 secret)
  └─→ 步驟 2.6 (列出 secrets)
  └─→ 步驟 2.7 (CLI 參數解析)
      └─→ 步驟 2.8 (錯誤處理與輸出格式)

步驟 2.8
  └─→ 步驟 3.1 (功能測試)
      └─→ 步驟 3.2 (使用範例文檔)
          └─→ 步驟 3.3 (完善專案 README)
```

---

## 預期產出

### 檔案清單
- `/vault-manage-script/vault-manage.sh` - Shell Script 主程式
- `/vault-manage-script/.gitignore` - Git 忽略配置
- `/vault-manage-script/.env.example` - 環境變數範本
- `/vault-manage-script/README.md` - 專案說明與使用指引
- `/vault-manage-script/EXAMPLES.md` - 使用範例文檔

### 使用範例（預期）

```bash
# 設定環境變數
export VAULT_ADDR='https://vault.web.internal'
export VAULT_SKIP_VERIFY=true
export VAULT_USERNAME='yao'
export VAULT_PASSWORD='Rr1980690911'

# 讀取 secret（預設 JSON 格式）
./vault-manage.sh get secrets teams/job-finder/environments/qa/db-user

# 讀取 secret（表格格式）
./vault-manage.sh get secrets teams/job-finder/environments/qa/db-user --format table

# 建立 secret
./vault-manage.sh create secrets teams/test/api-key key1=value1 key2=value2

# 更新 secret（部分更新）
./vault-manage.sh update secrets teams/test/api-key key3=value3

# 更新 secret（完整覆蓋）
./vault-manage.sh update secrets teams/test/api-key key1=newvalue1 key2=newvalue2 --replace

# 列出 secrets
./vault-manage.sh list secrets teams/job-finder

# 刪除 secret
./vault-manage.sh delete secrets teams/test/api-key
```

---

## 注意事項

1. **機敏資料管理**
   - 絕不將帳號密碼寫入程式碼
   - 使用環境變數管理
   - `.env` 檔案必須加入 `.gitignore`

2. **安全性**
   - Token 只存在於記憶體中
   - 避免在日誌中顯示機敏資料
   - 使用 HTTPS 連線（雖然目前 SKIP_VERIFY，但在生產環境應啟用驗證）

3. **相容性**
   - 需要 bash 4.0+
   - 需要 curl（API 呼叫）
   - 需要 jq（JSON 處理）

4. **錯誤處理**
   - 提供清楚的錯誤訊息
   - 驗證必要環境變數是否設定
   - 處理網路連線失敗情況

---

## 下一步

請確認此實作計畫是否符合需求。確認後，我會依序執行各階段步驟。

每完成一個步驟，我會在對應的 checkbox 打勾，並等待你的確認後再繼續下一步。
