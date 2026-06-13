# 任務：為 SHOPLINE Payments 金流加入「分期付款」功能（信用卡分期 + 中租 zingla 銀角零卡 BNPL）

你是在一個 Next.js 15 (App Router) + Prisma 7 + PostgreSQL 的線上課程販售平台上工作。
這份文件包含你需要知道的**全部**背景、API 規範、修改範圍與驗收標準。請完整讀完再動手。

---

## 0. 最重要的架構前提（先讀，避免走錯方向）

本平台的 SHOPLINE Payments 整合是「**導轉式 hosted checkout**」：

1. Server 端呼叫 `POST /api/v1/trade/sessions/create` 建立 session
2. 取得回應中的 `sessionUrl`，把顧客 redirect 過去 SHOPLINE 託管的收銀台頁面
3. 顧客在 SHOPLINE 頁面上選擇付款方式並付款
4. SHOPLINE 以 webhook（HMAC-SHA256 驗簽）通知付款結果

**因此：**
- ❌ **不要**安裝或引入 `@shoplinepayments/payment-web` JS SDK
- ❌ **不要**在前端建立內嵌收銀台、不要呼叫 `payment.createPayment()` / `payment.pay()`
- ❌ **不要**在本平台前端做分期期數下拉選單——期數選擇 UI 由 SHOPLINE 託管頁面自己渲染
- ✅ 分期功能 = 在 server 端建立 session 的 request body 加上 `paymentMethodOptions`，
  並讓管理員能在後台設定「啟用哪些付款方式」與「開放哪些分期期數」

SHOPLINE 收銀台對 `installmentCounts` 的處理規則（由 SHOPLINE 端執行，你不需實作）：
- `"0"` 代表不分期；只傳 `["0"]` 或空陣列 = 不顯示分期選項
- 傳入的期數若特店合約不支援，SHOPLINE 會自動隱藏
- 過濾後只剩一個有效期數 → 不顯示下拉框，直接以該期數付款
- 過濾後有多個有效期數 → 顯示下拉框，由小到大排序，預設選第一個

---

## 1. 現有程式碼地圖（先逐一閱讀這些檔案）

| 檔案 | 角色 |
|------|------|
| `lib/payment/types.ts` | `PaymentGateway` 統一介面、`PaymentGatewaySettings` 型別 |
| `lib/payment/shopline-methods.ts` | SHOPLINE 付款方式代碼的集中管理（codes / labels / parse / serialize） |
| `lib/payment/shopline-gateway.ts` | `ShoplineGateway` 類別，`createPaymentSession()` 在這裡組 request body |
| `lib/payment/gateway-factory.ts` | 從 `SiteSetting` 表讀設定、建立 gateway 實例 |
| `lib/validations/settings.ts` | `SETTING_KEYS` 設定 key 註冊表 + Zod schema |
| `lib/actions/settings.ts` | 金流設定的讀寫 Server Actions（`getPaymentSettings` / `updatePaymentSettings` 一帶） |
| `components/admin/settings/payment-settings-form.tsx` | 後台金流設定 UI（已有 SHOPLINE 付款方式 checkbox 區塊） |
| `app/(admin)/admin/settings/client.tsx` | 設定頁，把設定傳給表單元件 |
| `app/api/webhooks/shopline/route.ts` | SHOPLINE webhook：驗簽、金額驗證、冪等、開通課程 |
| `app/api/payment/shopline/return/route.ts` | 付款完成導回 |
| `prisma/schema.prisma` | `PaymentMethod` enum（目前：CREDIT_CARD / APPLE_PAY / GOOGLE_PAY / ATM / CVS） |
| `components/admin/orders/order-detail-card.tsx`、`order-table.tsx`、`order-filters.tsx` | 訂單付款方式的顯示 label 與篩選 |

> 注意：你手上的程式碼版本可能與上述描述有細微差異（行號、函式名）。
> 動手前先用搜尋確認實際結構，以實際程式碼為準，但整體分層一定相同。

---

## 2. SHOPLINE Payments API 規範（完整）

### 2.1 建立 Session：`POST {baseUrl}/api/v1/trade/sessions/create`

- 沙盒：`https://api-sandbox.shoplinepayments.com`
- 正式：`https://api.shoplinepayments.com`
- Headers：`Content-Type: application/json`、`merchantId`、`apiKey`、`requestId`（32 碼 UUID 去 dash，現有 `request()` helper 已處理，不要動）

**與本任務相關的 request 欄位：**

```jsonc
{
  "referenceId": "訂單編號 orderNo",
  "amount": { "value": 150000, "currency": "TWD" },   // 金額 × 100
  "mode": "regular",
  "returnUrl": "https://.../api/payment/shopline/return?orderNo=...",

  // 允許的付款方式（既有欄位，已由 shopline-methods.ts 控制）
  "allowPaymentMethodList": ["CreditCard", "ApplePay", "LinePay", "ChaileaseBNPL", "VirtualAccount"],

  // ★ 本次新增的欄位：各付款方式的選項設定
  "paymentMethodOptions": {
    "CreditCard": {
      "installmentCounts": ["0", "3", "6", "9", "12"]   // String 陣列；"0" = 不分期
    },
    "ChaileaseBNPL": {
      "installmentCounts": ["0", "3", "6", "9", "12"],
      "paymentExpireTime": 120                          // 選填，付款逾時（分鐘）
    }
  }

  // order / customer / billing / client 等其餘欄位維持現狀，不要動
}
```

**`paymentMethodOptions` 規則：**
- 選填欄位；不帶 = 全部視為不分期（現行行為，必須保持向下相容）
- `installmentCounts` 僅對 `CreditCard` 與 `ChaileaseBNPL` 有效
- 期數為 String 型別（兼容 Number，但請一律送 String）
- 只對「同時出現在 `allowPaymentMethodList`」的付款方式帶 options，未啟用的方式不要帶

**回應（200）：**
```json
{
  "sessionId": "se_xxx",
  "referenceId": "訂單編號",
  "status": "CREATED",
  "amount": { "value": 150000, "currency": "TWD" },
  "sessionUrl": "https://.../checkout/session?sessionToken=xxx",
  "createTime": "1740711420842"
}
```
錯誤回應為 `{ "code": "...", "msg": "..." }`，現有 `request()` 已處理。

### 2.2 付款方式代碼總表（`allowPaymentMethodList` 合法值）

| Code | 中文 | 支援分期 |
|------|------|---------|
| `CreditCard` | 信用卡 | ✅（installmentCounts） |
| `ChaileaseBNPL` | 中租分期（zingla 銀角零卡） | ✅（installmentCounts） |
| `ApplePay` | Apple Pay | ❌ |
| `LinePay` | LINE Pay | ❌ |
| `VirtualAccount` | ATM 銀行轉帳 | ❌ |
| `JKOPay` | 街口支付 | ❌（本平台已確認特店不支援，**不要**加回來） |

### 2.3 Webhook（現有實作，僅需小幅擴充）

- 驗簽：HMAC-SHA256，payload = `${timestamp}.${rawBody}`，headers `timestamp` / `sign` —— **不要更動驗簽、金額驗證、冪等邏輯**
- 成功事件 payload 的 `data.payment.paymentMethod` 會回傳實際付款方式字串；
  分期相關交易會回傳 `ChaileaseBNPL`（中租）或 `CreditCard`（信用卡分期仍是 CreditCard）

---

## 3. 功能設計（請完全照此設計實作）

### 3.1 設計總覽

管理員在後台「金流設定 → SHOPLINE Payments」中：
1. 付款方式 checkbox 清單新增「**中租分期（zingla 銀角零卡）**」選項
2. 新增「**分期期數**」多選設定（3 / 6 / 9 / 12 / 18 / 24 期），預設全不勾 = 不分期
3. 分期期數設定**同時套用**於「信用卡」與「中租分期」兩種方式（共用一組期數，保持簡單；SHOPLINE 會自動過濾特店合約不支援的期數，所以多勾不會壞）
4. 只有當「信用卡」或「中租分期」至少一項被啟用時，分期期數區塊才顯示

### 3.2 逐檔修改清單

**(1) `lib/payment/shopline-methods.ts`**
- `SHOPLINE_PAYMENT_METHOD_CODES` 加入 `'ChaileaseBNPL'`
- `SHOPLINE_PAYMENT_METHOD_LABELS` 加入 `ChaileaseBNPL: '中租分期（zingla 銀角零卡）'`
- `SHOPLINE_DEFAULT_PAYMENT_METHODS` **不要**加入 ChaileaseBNPL（預設關閉，由管理員主動啟用）
- 新增分期期數的集中管理：
  ```ts
  export const SHOPLINE_INSTALLMENT_COUNT_OPTIONS = ['3', '6', '9', '12', '18', '24'] as const
  export type ShoplineInstallmentCount = (typeof SHOPLINE_INSTALLMENT_COUNT_OPTIONS)[number]
  // 並仿照付款方式，提供 parse / normalize / serialize 三個函式：
  // parseShoplineInstallmentCounts(raw: string | null | undefined): ShoplineInstallmentCount[]
  //   - JSON 陣列字串優先，逗號分隔 fallback，非法值過濾，預設 []
  // serializeShoplineInstallmentCounts(...): string  // JSON.stringify
  ```

**(2) `lib/validations/settings.ts`**
- `SETTING_KEYS` 新增 `SHOPLINE_INSTALLMENT_COUNTS: 'shopline_installment_counts'`
- 金流設定的 Zod schema 新增：
  `z.array(z.enum(SHOPLINE_INSTALLMENT_COUNT_OPTIONS)).optional()`（空陣列合法 = 不分期）
- 此設定非敏感資料，**不要**加入 `SENSITIVE_SETTING_KEYS`

**(3) `lib/payment/types.ts`**
- `PaymentGatewaySettings.shopline` 新增 `installmentCounts: ShoplineInstallmentCount[]`

**(4) `lib/payment/gateway-factory.ts`**
- `getPaymentGatewaySettings()` 的查詢 keys 加入 `SETTING_KEYS.SHOPLINE_INSTALLMENT_COUNTS`
- 解析：`parseShoplineInstallmentCounts(settingMap.get(...) || process.env.SHOPLINE_INSTALLMENT_COUNTS)`
- `createGatewayFromSettings()` 把 `installmentCounts` 傳進 `new ShoplineGateway({...})`

**(5) `lib/payment/shopline-gateway.ts`**
- `ShoplineConfig` 新增 `installmentCounts?: string[]`
- `createPaymentSession()` 組 body 時，在 `allowPaymentMethodList` 之後新增：
  ```ts
  // 分期設定：僅對已啟用且支援分期的方式帶 installmentCounts
  // SHOPLINE 規則："0" = 不分期；收銀台會自動過濾特店不支援的期數
  const methods = normalizeShoplinePaymentMethods(this.config.enabledPaymentMethods)
  const counts = this.config.installmentCounts ?? []
  const installmentCounts = ['0', ...counts]  // 永遠保留 "0"，讓顧客可選擇不分期
  const paymentMethodOptions: Record<string, unknown> = {}
  if (counts.length > 0) {
    if (methods.includes('CreditCard')) {
      paymentMethodOptions.CreditCard = { installmentCounts }
    }
    if (methods.includes('ChaileaseBNPL')) {
      paymentMethodOptions.ChaileaseBNPL = { installmentCounts }
    }
  }
  ```
  並在 body 中以 `...(Object.keys(paymentMethodOptions).length > 0 ? { paymentMethodOptions } : {})` 帶入。
  **期數未設定時 body 必須與現狀完全相同（不帶 paymentMethodOptions）。**

**(6) `prisma/schema.prisma` + webhook**
- `PaymentMethod` enum 新增 `BNPL`（中租分期），執行 `pnpm prisma generate && pnpm prisma db push`
  （enum 新增值是 additive 變更，對既有資料安全）
- `app/api/webhooks/shopline/route.ts` 的 `mapShoplinePaymentMethod()`：
  在 `return 'CREDIT_CARD'` 之前加 `if (s.includes('chailease') || s.includes('bnpl')) return 'BNPL'`
- 訂單顯示處同步加 label：`order-detail-card.tsx`、`order-table.tsx` 的 mapping 加
  `BNPL: '中租分期'`；`order-filters.tsx` 的選項與型別 union 也要加，否則 TS 會報錯。
  （請全域搜尋 `CREDIT_CARD: '信用卡'` 找出所有顯示處，一個都不能漏）

**(7) `lib/actions/settings.ts`**
- 金流設定讀取函式：回傳值的 `shopline` 物件加入 `installmentCounts`
- 更新函式：input 型別與 Zod 驗證加入 `shoplineInstallmentCounts?: ...`，
  寫入時用 `serializeShoplineInstallmentCounts()` 存成 JSON 字串
- 維持既有的 AdminLog 記錄行為（設定變更要進 AdminLog）

**(8) `components/admin/settings/payment-settings-form.tsx`（+ `app/(admin)/admin/settings/client.tsx` 傳遞 props）**
- 付款方式 checkbox 區塊：ChaileaseBNPL 加入 codes 後會自動出現（confirm 即可）
- 新增「分期期數」區塊：
  - 顯示條件：`enabledMethods` 含 `CreditCard` 或 `ChaileaseBNPL`
  - UI：6 個 checkbox（3/6/9/12/18/24 期），風格與既有付款方式 checkbox 一致
  - 說明文字：「勾選要開放給顧客的分期期數。實際可用期數依您與 SHOPLINE 簽約內容為準，未簽約的期數不會顯示給顧客。全部不勾選代表不開放分期。」
  - dirty-check（判斷表單是否變更）邏輯要把新欄位算進去

### 3.3 不要做的事

- 不要動 webhook 驗簽、金額驗證、冪等性、`grantPaidOrderAccess` 邏輯
- 不要動 Stripe / PAYUNi gateway
- 不要引入任何新 npm 套件
- 不要把分期期數做成「每個課程各自設定」——這是全站設定
- 不要在前台結帳頁加任何分期 UI（SHOPLINE 託管頁面會處理）

---

## 4. 驗收標準（全部通過才算完成）

### A. 自動驗證（你必須親自執行並貼出結果）

1. `pnpm lint` 通過，無新增錯誤
2. `pnpm build` 成功
3. `pnpm prisma generate` 成功，且 `prisma db push` 後 `PaymentMethod` enum 含 `BNPL`
4. 寫一個臨時驗證腳本（或單元測試）證明：
   - `parseShoplineInstallmentCounts('["3","6"]')` → `['3','6']`
   - `parseShoplineInstallmentCounts('3,6,99,abc')` → `['3','6']`（非法值過濾）
   - `parseShoplineInstallmentCounts(null)` → `[]`
   - `parseShoplineInstallmentCounts('[]')` → `[]`
5. 驗證 `createPaymentSession` 組出的 body（可 mock fetch 攔截，或暫時 console.log body 後還原）：
   - 期數 `['3','6']` + 啟用 CreditCard、ChaileaseBNPL →
     body 含 `paymentMethodOptions.CreditCard.installmentCounts === ['0','3','6']`
     且 `paymentMethodOptions.ChaileaseBNPL.installmentCounts === ['0','3','6']`
   - 期數 `[]` → body **完全不含** `paymentMethodOptions` 鍵
   - 期數 `['3']` 但只啟用 ApplePay、LinePay → body 不含 `paymentMethodOptions`
   - 啟用 ChaileaseBNPL 時 `allowPaymentMethodList` 含 `'ChaileaseBNPL'`

### B. 後台 UI 驗收（`pnpm dev` 起本機，實際操作截圖或逐步描述）

6. `/admin/settings` 金流設定頁可看到「中租分期（zingla 銀角零卡）」checkbox，預設未勾選
7. 勾選信用卡或中租分期時，「分期期數」區塊出現；兩者皆取消勾選時區塊隱藏
8. 勾選 3、6 期並儲存 → 重新整理頁面後勾選狀態保留（確認 DB 持久化）
9. 設定變更有寫入 AdminLog
10. 完全不動分期設定的情況下，原本的儲存流程行為不變（回歸檢查）

### C. Webhook 與訂單顯示驗收

11. 用 curl 模擬 webhook（依現有驗簽規則以測試 signKey 算出合法簽章），
    payload 的 `data.payment.paymentMethod = "ChaileaseBNPL"` →
    訂單 `paymentMethod` 寫入 `BNPL`，課程正常開通
12. 後台訂單列表 / 訂單詳情頁，該訂單付款方式顯示「中租分期」，且付款方式篩選器可篩出
13. 重送同一 webhook → 回應「訂單已處理」，不重複開通（冪等回歸）

### D. 回歸與相容性

14. 既有訂單（CREDIT_CARD / ATM 等）在後台顯示正常
15. 未設定任何分期期數的站台，建立 session 的 request body 與改動前 byte-level 等價
    （即 `paymentMethodOptions` 完全不出現）
16. TypeScript 全專案無型別錯誤（`pnpm build` 已涵蓋，但請特別確認
    `order-filters.tsx` 的 PaymentMethod union 有同步更新）

### 最終交付

- 列出所有修改的檔案與每個檔案的變更摘要
- 貼出驗收標準 A、C 的執行證據（指令輸出）
- 說明 B 的手動驗證結果
- 提醒站長：上線後需向 SHOPLINE 業務窗口確認特店合約已開通
  「信用卡分期」與「中租 ChaileaseBNPL」，否則收銀台不會顯示分期選項
