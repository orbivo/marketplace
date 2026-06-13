接續煙霧測試。Resend 測試模式只能寄到帳號本人信箱（ray948787@gmail.com），用它測完整流程：


Ran 5 commands, edited 2 files, read 2 files。 
最終驗證並收尾：


Ran 2 commands, edited 2 files
完成。正式登入系統（magic link + Google OAuth）全部做完並實測通過，剛剛還寄了一封真的登入信到 slwarray01@gmail.com（zh-TW 版、寄件人 login@skillpod.app——域a名驗證在做的過程中剛好轉綠了，所以已經能寄到任意信箱）。

這次做了什麼
Magic link（Resend）

LoginToken 新表：DB 只存 SHA-256 hash、15 分鐘過期、單次使用；next 導回路徑存 DB 不進信中連結（lib/login-token.ts）
lib/email.ts：fetch 直打 Resend API（不裝 SDK），信件依 NEXT_LOCALE 出 en/zh-TW/ja 三語（emails.magicLink.*，i18n 現在 264 keys × 3 同步）
api/auth/login：Redis 限流（同 email 60 秒 1 封、同 IP 每小時 10 次，lib/rate-limit.ts）、回應不洩漏帳號存在性；無 key 且非 production 才走 dev 直接放行
api/auth/verify：驗 token → 簽 session → 無 handle 導 onboarding（帶 next）、有 handle 導回 next
Google OAuth（google + callback）

自寫 code flow，不引 NextAuth；state cookie 防 CSRF；只信 email_verified，以 email 合併帳號（先 magic link 後 Google 落同一個 User），順手撿 name/頭像補空欄
登入頁（login-form.tsx）：Google 按鈕置頂 → email 表單；寄出後切「查收信箱」狀態（60 秒重寄倒數、可換 email）；連結過期/Google 失敗/限流都有對應錯誤文案。

實測結果：寄信 ✅（zh-TW 信真的寄出）→ 60 秒內重寄 429 ✅ → 點連結首次成功（導 onboarding 帶 next + session）✅ → 同連結重放被擋 ✅ → Google 未設定時優雅 fallback ✅ → pnpm build、check:i18n 全綠。文件已同步：06-implementation-log.md、CLAUDE.md/AGENTS.md（auth 紀律更新）、.env.example。

只剩一件事要你動手
GCP Console 建 OAuth Client（APIs & Services → Credentials → OAuth client ID, type: Web），redirect URI 填 http://localhost:3000/api/auth/google/callback（上線再加正式域名那條），把 Client ID/Secret 填進 .env 的 GOOGLE_CLIENT_ID/GOOGLE_CLIENT_SECRET 就通了。在那之前 Google 按鈕會顯示但點了回登入頁帶錯誤提示。

另外提醒：Resend key 在對話裡出現過，上線前建議去後台 rotate 一次。
