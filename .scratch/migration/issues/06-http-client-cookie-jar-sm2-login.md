# 06: HTTP 客户端 + cookie jar + SM2 登录

**What to build:** 用纯 HTTP 完成一次完整登录：取登录页公钥、SM2 加密口令、换取票据、走漫游、抓取请求令牌，建立仅存在于内存的会话；从而证实或证伪「不启动 Web 容器即可登录」这一前提。

**Blocked by:** 01（工程分层 + 日志门面 + 主题令牌）

**Status:** ready-for-agent

- [ ] 真机上用真实账号完成纯 HTTP 登录，日志显示成功取得会话 cookie 与请求令牌 —— **未验证（凭据门控）**；`AuthProbe` + 脚本已就绪，见 Comments
- [x] 全程不启动任何 Web 容器 —— 登录路径四个目录内零 Web 引用，只用 `@ohos.net.http`（见 Comments）
- [ ] SM2 加密输出能被服务端接受（以登录成功为证），并与参考库的输出格式一致 —— **未验证（凭据门控）**；本地已用设备真实密文向量锁定组装格式
- [x] cookie jar 能在请求之间保持与拼接 Cookie 头，且有可诊断日志 —— `core.CookieJar` 8 条（诊断串脱敏）
- [ ] 若证伪（服务端强制要求浏览器），在 Comments 中记录证据与结论，并提请复审 ADR-0004 —— **未触发**；判定出口（`NO_TICKET_IN_RESPONSE` + `idLoginPage=true`）已就绪

## Comments

### 派单前的参考实现核查（统筹，逐行取证，2026-09-12）

**结论先说**：登录是 7 步、全部可纯 HTTP 完成；SM2 那一半已在上文验证完毕。真正的风险不在密码学，而在三个**容易漏掉却会改变服务端行为**的细节：UA 伪装、登录前清 cookie、CSRF 正则的贪婪语义。

#### 1. 确切登录序列（`node_modules/thu-learn-lib/lib/module/index.js`）

`getRoamingTicket()` `:101-141`
1. 先在 ID 域清 JSESSIONID：`setCookie("JSESSIONID=; path=/; HttpOnly", ID_PREFIX)`（`:108`）。`:99-106` 的注释写明必须清掉 id 域 cookie，否则换用户登录会被残留 cookie 影响。
2. GET 登录表单 `ID_LOGIN()`。
3. 用 cheerio **XML 模式**（`CHEERIO_CONFIG = { xml: true }`，`:15-20`）取 `#sm2publicKey` 的 text 并 trim（`:118`）。
4. POST `ID_LOGIN_CHECK()`，**FormData** 字段（`:119-130`）：

   | 字段 | 值 |
   | --- | --- |
   | `i_user` | 用户名 |
   | `i_pass` | `'04' + sm2.doEncrypt(password, sm2publicKey)` |
   | `singleLogin` | `'on'`（= 信任该浏览器） |
   | `fingerPrint` | 我们生成并持久化的指纹 |
   | `fingerGenPrint` | 同，空则 `''` |
   | `fingerGenPrint3` | 同，空则 `''` |
   | `i_captcha` | **恒为空串**（`:126`）——参考实现总是带这个字段 |

5. 解析响应 HTML 取**第一个 `<a>`** 的 `href`，`ticket = href.split('=').slice(-1)[0]`（`:131-133`）。

`login()` `:144-183`
6. GET `LEARN_AUTH_ROAM(ticket)`，`ok !== true` → `ERROR_ROAMING`（`:164-169`）。
7. GET 学生课程列表页 `LEARN_STUDENT_COURSE_LIST_PAGE()`，用 `/^.*&_csrf=(\S*)".*$/gm` 提取 CSRF → `matchAll(...)[0][1]`（`:171-179`）；提取不到 → `INVALID_RESPONSE`。同时用 `/<script src="\/f\/wlxt\/common\/languagejs\?lang=(zh|en)"><\/script>/g` 取 lang（`:180-182`）。

**两个必须逐字保真的正则**（它们决定登录成不成）：
- CSRF 那条里 `.*` 是**贪婪**的，所以每行取到的是**最后一个** `&_csrf=`；且必须有 `&` 前缀（不是行首直接 `_csrf=`）。夹具要覆盖"一行内有多个 `&_csrf=`"，断言取到最后一个。
- lang 那条是整串标签精确匹配，含 `src="/f/wlxt/..."` 的前导斜杠。
这两条都适合当纯函数夹具测，不必上设备。

#### 2. 凭据来源与调用边界

- `login(username, password, fingerPrint, fingerGenPrint, fingerGenPrint3)` **接收参数**；只有参数缺失时才回落到注入的 `provider()`（`:145-160`）。
- 参考实现在组合点 `src/data/source.ts:48-71` 把 provider 接到 store 上。**新实现里 provider 应由 07/08 提供（读凭据库），登录客户端自己不读盘**——与 ticket 07 Comments 里已写下的接口约定一致。
- `FailReason` 值得照搬成可诊断分类：`NO_CREDENTIAL` / `ERROR_SETTING_COOKIES` / `ERROR_FETCH_FROM_ID` / `ERROR_ROAMING` / `INVALID_RESPONSE` / `NOT_LOGGED_IN` / `UNEXPECTED_STATUS`。

#### 3. 三个容易漏掉、但会改变服务端行为的事实

1. **必须伪装桌面 Chrome UA**：`src/data/source.ts:55-57` 的自定义 fetch 强制
   `Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36`。
   这不只是"像浏览器"：页面自己的 `userAgentUtil.getUserAgentName()` 会把它写进 `deviceName`，而服务端把信任绑在设备指纹上。发原生 HarmonyOS UA 可能直接改变服务端行为（例如弹验证码）。**必须复刻同一 UA，并在证据里写明用的是它。**
2. **登录前清空 cookie**：`loginWithFingerPrint`（`source.ts:30-46`）先 `clearLoginCookies()`（`:11-28`：`clearAll(true)` + 把 id 域 `JSESSIONID` 置空），注释原文 "HarmonyOS cookies may persist unexpectedly"——又一处平台能力缺口补丁，与怪癖第 1 条同类。我们的 jar 在内存（ADR-0004），等价行为是**每次登录前显式重置内存 jar**，别依赖"反正是空的"。
3. **`i_captcha` 恒发空串**（`:126`）。若服务端此时要求验证码，POST 拿不到那个 `<a>`，失败会由"取不到 ticket"暴露而不是静默成功。这正是 `idp-login-flow.md` 第 4 节待验证第 3 项（无交互 re-auth 是否弹验证码）的判定出口——**一旦碰到，保留原始响应并提请复审 ADR-0004**（本 ticket 验收第 5 条要求）。

#### 4. 重登：见 `docs/reference-quirks.md` 第 2 条（刚更正）

参考实现有**两条**重登路径、两个触发条件：原生处理器路径用 `result === '[]'`（`source.ts:104`，并有单飞 `reAuthPromise` 防并发重复登录，`:111-121`）；thu-learn-lib 路径用 `noLogin(res)` = URL 含 `login_timeout` 或 `status == 403`（`index.js:21`、`:46-71`）。**新实现取两者并集，且只重试一次。**

- 并发那条 `reAuthPromise` 单飞值得照搬，并且**可以纯单测**（并发 N 个请求只触发一次登录）。
- `getCSRFToken()` 在登录/重登后即失效（`index.js:87-90` 注释），而 `#myFetchWithToken` 在 token 为空时会先自动登录（`:37-40`）——cookie jar 与 token 的生命周期要一起设计。

#### 5. 与 05 已交付的衔接

`data/remote/Port.ets`（`FetchPort`：`postForm`/`get`/`upload` + `UploadProgress`）、`HttpClient.ets`（`@ohos.net.http`，失败折算 outcome 不抛）、`HttpFetchPort.ets` 已就绪。**扩展而不是重写**：把 cookie jar、SM2、登录流通过 `Session` 与自定义 `FetchPort` 注入即可，三域仓储无需改动。

### 2026-09-12 技术验证：SM2 变换字符串与密文排列（spec 第 11 节第 1 项，判定：**已验证通过**）

**结论：可以。** `cryptoFramework` 能产出与 `'04' + sm2.doEncrypt(...)` 同构、服务端可解的密文，纯 ArkTS（零 WebView）Re-auth 路线成立，**ADR-0004 不需要推翻**。
下方第 6 条列了唯一未覆盖的边界：与**真实服务端**的端到端接受度（需真实账号登录，属本 ticket 自身的验收项，未在本次验证内）。

#### 1. 本机 SDK 的权威事实

SDK：`C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\ets\api\@ohos.security.cryptoFramework.d.ts`（API 24 SDK；`%LOCALAPPDATA%\Huawei\Sdk` 下只有 licenses/system-image，没有 SDK 本体）。
kit re-export：`sdk/default/openharmony/ets/kits/@kit.CryptoArchitectureKit.d.ts`（`import { cryptoFramework } from '@kit.CryptoArchitectureKit'`）。

| 事实 | 证据 |
| --- | --- |
| `function createCipher(transformation: string): Cipher;` | .d.ts **4281** |
| transformation 是用 `"|"` 拼接的多参数串（.d.ts 注释 "Multiple parameters need to be concatenated by '|'"） | .d.ts **4270**；.d.ts **不写明 SM2 的确切串** |
| `initSync(opMode: CryptoMode, key: Key, params: ParamsSpec \| null): void;` | .d.ts **3551** |
| `doFinalSync(data: DataBlob \| null): DataBlob;` | .d.ts **4061** |
| `SM2CipherTextSpec{xCoordinate: bigint, yCoordinate: bigint, cipherTextData: Uint8Array, hashData: Uint8Array}` | .d.ts **9295-9336** |
| `static genCipherTextBySpec(spec, mode?: string): DataBlob` / `static getCipherTextSpec(cipherText, mode?: string): SM2CipherTextSpec` | .d.ts **9362** / **9379** |
| `SM2_MD_NAME_STR = 104`（CipherSpecItem 里唯一的 SM2 项） | .d.ts **3006** |
| 全 SDK **不存在** `SM2CipherMode` 类型 | grep `SM2CipherMode\|CipherMode` → 0 命中 |

**确切变换字符串 = `'SM2_256|SM3'`**（来自本机离线文档，`devecocli docs read` 抓下并存盘）：
- `.scratch/migration/sm2-verify/doc-faq-31.txt:80` → `let transformation: string = 'SM2_256|SM3';`
- `.scratch/migration/sm2-verify/doc-faq-38.txt:75` → 同一串，且 `cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, encryptKey, null)`（**SM2 的 params 传 null，没有额外的模式参数**）。
- `.scratch/migration/sm2-verify/doc-sm2-conversion.txt:28` → `SM2CryptoUtil.genCipherTextBySpec(spec, 'C1C3C2')`。

**排列由 `mode` 字符串控制，不由 transformation 控制**：`getCipherTextSpec(der, 'C1C3C2')` 取出 C1x/C1y/C3/C2，自行拼 `'04'+C1x+C1y+C3+C2`（doc-faq-31.txt:36-45 就是官方给出的这段代码）。`doFinal` 的输出是 **ASN.1 DER**（`DataBlob`，不是字符串）：31 字节明文 → 139 字节 DER，首字节 `0x30`。

#### 2. sm-crypto 侧的事实

`reference/learnOH-old/node_modules/sm-crypto`（软链到 `D:\Koracan\source\harmony\learnOH-old`；**未修改**）。实测版本 **0.3.14**，`package.json:5` `"main": "src/index.js"` → require 走 `src/`，不是 `dist/`。

- `function doEncrypt(msg, publicKey, cipherMode = 1)` —— `src/sm2/index.js:13` → **默认 cipherMode = 1**。
- `const C1C2C3 = 0`（`:8`）；`return cipherMode === C1C2C3 ? c1 + c2 + c3 : c1 + c3 + c2`（`:54`）→ 默认 **C1C3C2**。
- `c1` 被截成 128 hex：`if (c1.length > 128) c1 = c1.substr(c1.length - 128)`（`:22`）→ doEncrypt **不返回 `04` 前缀**，`04` 由调用方拼（`thu-learn-lib/lib/module/index.js:121`）。输出是 **小写 hex 字符串**。
- `c3 = SM3(x2 || msg || y2)`（`:30`），**hash 不含 Z 值/用户 ID**；KDF 亦用 SM3（`:36-43`）。
- 随机数：`_.generateKeyPairHex()`（`:17`）→ `new BigInteger(n.bitLength(), rng)`，`rng = new SecureRandom()`（`src/sm2/utils.js:5,39`）。
- **更正一处 ticket 描述**：`decodePointHex` 只认 `04/02/03` 开头的点（`src/sm2/ec.js:292-325`）；传 128 hex 无前缀会返回 `null` 并在 `publicKey.multiply` 处抛 `TypeError`（本次实测）。因此登录页 `#sm2publicKey` 的文本**必然带 `04`（130 hex）**，否则页面自己的 `sm2Util.doEncryptStr` 也会崩。这条是**推断**（`idp-login-flow.md:7,17` 只记录它是页内元素文本，没存下实际值），不是直接取证。

#### 3. 对照实验（真实输出，已落盘）

脚本与日志目录：`.scratch/migration/sm2-verify/`

**(a) sm-crypto 侧**（`sm2-probe.js` → `sm2-probe.log` / `node-output.json`）：
固定密钥对取自官方文档 faq-31 第 86-87/137 行（先用 `sm2.getPublicKeyFromPrivateKey` 验过 `sk*G == pk`）。
```
明文 = "learnOH-sm2-probe-2026-密码Æ"  (utf8 hex 6c65...c386, 31 bytes)
同一 (明文,公钥) 连跑两次密文不同（随机 k），长度都是 254 hex = C1(128)+C3(64)+C2(62)
按 c1+c3+c2 切分后：
  C1 是合法曲线点? true
  独立用 sk 重算 SM3(x2||msg||y2) == 中段  => true   <== 决定：中段是 C3、末段是 C2
doDecrypt(ct, sk, 1)  = "learnOH-sm2-probe-2026-密码Æ"
doDecrypt(ct, sk, 0)  = ""            (C1C2C3 解不出)
doDecrypt(ct, sk)     = "learnOH-sm2-probe-2026-密码Æ"   (证明默认就是 1)
i_pass = "04" + doEncrypt(...)  → 256 hex / 128 bytes
```

**(b) 设备侧**（模拟器 Pura 90，`--device 127.0.0.1:5555`；原始日志 `device-sm2probe-hilog.log`）：
临时探测 ability（`entry/src/main/ets/__sm2probe/Sm2ProbeAbility.ets` + module.json5 里的一条 ability）——**验证完成后已删除，module.json5 已还原，`git status` 无残留**。
```
P3 pubKey.getEncoded().data.length=91 hex=3059301306072a8648ce3d020106082a811ccf5501822d03420004<X><Y>  (X.509 SPKI DER, OID 1.2.156.10197.1.301)
T[SM2_256|SM3]  createCipher OK / initSync(ENCRYPT,pubKey,null) OK / doFinalSync OK len=139 first2bytes=3081
T[SM2_256|SHA256] doFinalSync OK len=140
T[SM2|SM3]      doFinalSync OK len=139
T[SM2_256]      createCipher FAILED code=401 name=Error message=create C cipher fail!
T[SM2]          createCipher FAILED code=401 name=Error message=create C cipher fail!
T[SM2_256|SM3|C1C3C2] doFinalSync OK len=139   (串被接受，但第 3 段被忽略)
T[SM2_256|SM3|C1C2C3] createCipher FAILED code=801 name=Error message=create C cipher fail!  (801=不支持)
S[C1C3C2] x=c345866a...  y=57f00c03...  C3(hashData)=402fec27...  C2(cipherTextData)=a893a22e...  (C2 31 bytes == 明文长度)
S[C1C2C3] getCipherTextSpec FAILED code=401 name=Error message=get cipher text spec fail.
ARTS_WIRE[C1C3C2]=04c345866a...d552b0d6   (130+64+62 字符)
DECRYPT_NODE_CIPHER=learnOH-sm2-probe-2026-密码Æ
DECRYPT_NODE_MATCH=YES                    <== cryptoFramework 解的开 sm-crypto 的密文
ARTS_WIRE_SELFROUNDTRIP=YES
```
（`getCipherTextSpec(der)` 不带 mode 与带 `'C1C3C2'` 结果完全一致 → 默认就是 C1C3C2。）

**(c) 跨语言判定**（`verify-arkts-output.js`，输入 `arkts-wire.txt` = 设备产出的上线密文 → `arkts-verify.log`）：
```
[PASS] C1 是 SM2 曲线上的合法点
sm2.doDecrypt(wire[2:], sk, cipherMode=1/C1C3C2) = "learnOH-sm2-probe-2026-密码Æ"
sm2.doDecrypt(wire[2:], sk, cipherMode=0/C1C2C3) = ""    (空串=该排列不成立)
独立重算 SM3(x2||msg||y2) == wire 中段  → [PASS]
=== 结论: PASS —— cryptoFramework 输出与 sm-crypto 逐字节兼容 ===
```
**双向互解**成立：cryptoFramework 解得开 sm-crypto 的密文，sm-crypto 也解得开 cryptoFramework 的密文，且排列独立验证为 C1C3C2。

**(d) `SM2_256|SHA256` 不兼容的证据**（`analyze-sha256-der.js` → `analyze-sha256-der.log`，用设备日志里那份 DER 离线分析）：
```
KDF 用 SM3 解 C2    = 26075bea...  <非 UTF-8>
KDF 用 SHA256 解 C2 = 6c656172...c386  "learnOH-sm2-probe-2026-密码Æ"   (命中)
重算 SM3(x2||msg||y2)    = c87ce830...
重算 SHA256(x2||msg||y2) = a88c3f65...  == 设备返回的 C3
sm2.doDecrypt(该 wire, sk, 1) = ""   (不兼容)
```
→ `SM2_256|SHA256` 下 **KDF 与 C3 都换成 SHA256**，不是国密 SM2 密文格式，**不可用于 Re-auth**。

#### 4. 试过但失败的变换串（真实报错，比成功路径更有价值）

| transformation | 结果 |
| --- | --- |
| `SM2_256\|SM3` | ✅ 可用（**推荐**） |
| `SM2\|SM3` | ✅ 可用（长度别名，输出同构） |
| `SM2_256\|SM3\|C1C3C2` | ⚠️ createCipher 通过，但第 3 段被静默忽略，等价于 `SM2_256\|SM3`；**排列无法用 transformation 指定** |
| `SM2_256\|SM3\|C1C2C3` | ❌ 801 `create C cipher fail!` |
| `SM2_256\|SHA256` | ⚠️ 能加密但与国密/sm-crypto 不兼容（见上） |
| `SM2_256` | ❌ 401 `create C cipher fail!` |
| `SM2` | ❌ 401 `create C cipher fail!` |
| `SM2CryptoUtil.getCipherTextSpec(der,'C1C2C3')` | ❌ 401 `get cipher text spec fail.`（只有 C1C3C2 可用） |

#### 5. 给实现的直接结论

1. 变换串固定 `'SM2_256|SM3'`；`initSync(CryptoMode.ENCRYPT_MODE, pubKey, null)`；`doFinalSync` 拿到 DER。
2. 用 `SM2CryptoUtil.getCipherTextSpec(der, 'C1C3C2')` 取出 `xCoordinate/yCoordinate/hashData/cipherTextData`，**各自按 32 字节左侧补零**（官方 FAQ 明确警告 OpenSSL 会丢高位 0，见 doc-faq-31.txt:188），再拼 `'04' + X(64) + Y(64) + C3(64) + C2`。
3. 公钥来自 `#sm2publicKey`（应带 `04`）：剥掉 `04` 后切两半，用 `ECCKeyUtil.genECCCommonParamsSpec('NID_sm2')` + `createAsyKeyGeneratorBySpec` + `generatePubKeySync()` 造 `PubKey`（与 doc-faq-38.txt:16-32 一致；本次设备实测 `buildPubKey` 带/不带 04 都成功）。
4. 反向（解服务端密文）用 `genCipherTextBySpec(spec, 'C1C3C2')` 造 DER 再 `initSync(DECRYPT_MODE, priKey, null)`。
5. 不要用 `SM2_256|SHA256`；不要指望 transformation 能选排列。

#### 6. 未验证 / 边界（不要用推测填坑）

- **没有**向真实 `id.tsinghua.edu.cn` / learn 站点发过任何请求。"服务端能解开"是通过与参考客户端 sm-crypto 的**格式级双向互解**证明的，不是通过真实登录证明的。真正端到端的那条仍属本 ticket 的验收项（"以登录成功为证"），未勾选。
- `#sm2publicKey` 到底带不带 `04` 是**推断**（依据 `src/sm2/ec.js:292-325` 的入参要求），未取到页面实际值；实现时按"若有 04 就剥掉"处理即可，两种情况都兼容。
- 只测了 31 字节明文（单块 KDF）。**未测**长明文（>32 字节需要多轮 KDF）和空串；不过 sm-crypto 与 cryptoFramework 的 KDF 轮次结构一致，风险低。
- 只在**模拟器** Pura 90（API 24）上测过；未在真机 MatePad Air 上测。
- 本次 `devecocli log --keyword SM2PROBE` 只返回 3 行（BEGIN/END，中间全丢），完整日志靠 `hdc shell "hilog -x -D 0x0A0B > /data/local/tmp/x.txt"` + `hdc file recv` 才拿到。**诊断 hilog 时不要只信 devecocli log 的输出行数。**

#### 7. 置信度与反证条件

- 置信度：**高**（格式兼容部分）。依据是本机 SDK 的 .d.ts + 本机离线官方文档 + 设备实测 + 双向密码学互解（含独立重算 C3），路径全部可复现。
- 服务端实际接受度：**未测**，不做判断。
- 会推翻本判定的新证据：① 真实登录时服务端拒绝 ArkTS 产物（例如服务端其实按 C1C2C3 或要求 DER）；② 服务端要求密码以外的东西参与（时间戳/HMAC）；③ `#sm2publicKey` 实际是压缩点或带其它前缀。前两条只能靠 ticket 06 的真实登录来回答。

### 实现与门禁（2026-09-12，模拟器口径 / 提交见下）

**交付清单**（全部为新增或对 ticket 05 交付物的**扩展**）：

| 文件 | 作用 |
| --- | --- |
| `core/http/CookieJar.ets`（新） | 纯内存 cookie jar：Set-Cookie 拆分/解析、域与路径匹配、Cookie 头拼接、同名同域同路径覆盖、过期删除、id 域 JSESSIONID 重置；诊断串**只含域名/名字/条数/字符数，不含值**（日志会被导出，脱敏是硬要求） |
| `core/crypto/Sm2Cipher.ets`（新） | SM2 口令加密：纯组装（`04`+X+Y+C3+C2、左补零、小写）+ 平台 `cryptoFramework`（`SM2_256\|SM3`、`getCipherTextSpec(der,'C1C3C2')`） |
| `data/auth/AuthTypes.ets`（新） | `FailReason`（照 thu-learn-lib 的字符串值）、`Credentials`、`LoginResult.requiresEnrollment()` |
| `data/auth/LoginParsers.ets`（新） | 两条逐字保真正则（CSRF 贪婪 / lang 精确）+ `#sm2publicKey` + 票据 + 失效判据 |
| `data/auth/LoginClient.ets`（新） | 7 步纯 HTTP 登录（清 jar → 取公钥 → SM2 → multipart 检查 → 票据 → 漫游 → CSRF/语言） |
| `data/auth/ReAuth.ets`（新） | 触发并集（`'[]'` ∪ `noLogin`）、**单飞**、只重试一次、失败分类 |
| `data/remote/Port.ets`（扩展） | 新增 `RawFetchPort`（`sendRaw`）+ `RawRequest/RawResponse`；**`FetchPort` 契约未动** |
| `data/remote/HttpClient.ets`（扩展） | 响应带 `headers`/`setCookie`；新增 `sendBinary` |
| `data/remote/HttpFetchPort.ets`（扩展） | `implements FetchPort, RawFetchPort`；原始通道**不自动注入 Cookie**（cookie 由调用方按 jar 显式给） |
| `data/upload/UploadForm.ets`（修） | **修掉 ticket 05 遗留的错误 import 路径**（见下「顺手修的不是参考实现」） |
| `entry/src/test/{CookieJar,LoginParsers,Sm2Wire,LoginFlow,ReAuth}.test.ets` | 43 条新单测 |
| `entry/src/test/fixtures/AuthFixtures.ets` + README 增补 | 认证夹具与成色 |
| `.scratch/auth/tools/`（新） | 一次性设备探针 `AuthProbe.ets` + `run-auth-probe.ps1` + README（用法与失败判读） |

**门禁（真实输出）**：
- 单测：`Tests run: 159, Failure: 0, Error: 0, Pass: 159`（先删 `entry/.test`、`--no-incremental`；日志 `.dsh/logs/ticket06-test4.log`）。
  我这轮的 5 个类共 **43** 条：`core.CookieJar` 8、`data.auth.LoginParsers` 7、`core.Sm2Cipher` 6、`data.auth.LoginClient` 13、`data.auth.ReAuth` 9（116 + 43 = 159）。
- 领域纯度：`node scripts/check-domain-purity.mjs` → PASS（12 个领域源文件）。
- i18n：`node scripts/check-i18n-keys.mjs` → `RESULT: OK`（231 键；本轮无新增文案，登录错误只走日志）。
- 构建：`devecocli build` → `BUILD SUCCESSFUL in 24 s 89 ms`，产物 `entry-default-signed.hap` 重新生成（1 282 920 字节，05:08:41；日志 `.dsh/logs/ticket06-build.log`）。
- 探针编译校验：把 `AuthProbe.ets` 临时放进树里跑一次 `hvigorw test` → `PROBE_COMPILE_EXIT=0`，随后 `git checkout` 复原（`.dsh/logs/ticket06-probe-compile2.log`）。

### 逐条验收

- [ ] **真机用真实账号完成纯 HTTP 登录，日志显示成功取得会话 cookie 与请求令牌** —— **未验证（凭据门控）**。
  能力已实现并通过 43 条注入式单测；`AuthProbe.ets` 就是那条「换个真实凭据就能跑」的通道（用法见 `.scratch/auth/tools/README.md`），
  它会在设备上打 `PROBE login ok=… csrfChars=… cookieChars=…` 与 `PROBE session page status=… firstCourseId=…`。
  本项**不勾选**：没跑过真实服务端。
- [x] **全程不启动任何 Web 容器** —— 登录路径只用 `@ohos.net.http`。静态证据：
  登录路径的四个目录（`data/auth`、`data/remote`、`core/http`、`core/crypto`）内 `webview|WebView|@ohos.web|@kit.ArkWeb` **零命中**；
  `core/web/`（ticket 04 的公告详情渲染）不在登录路径上。导入 `@ohos.net.http` 的只有 `data/remote/HttpClient.ets`。
- [ ] **SM2 加密输出能被服务端接受（以登录成功为证）** —— **未验证（凭据门控）**。
  本地能做的那半已做且证据强：用**模拟器产出的真实上线密文**（`.scratch/migration/sm2-verify/arkts-wire.txt`）锁定纯组装 `'04'+X+Y+C3+C2` 与左补零（`core.Sm2Cipher` 6 条）。
  「服务端接受」这半只能靠 `AuthProbe` 的真跑（`ERROR_ROAMING` 就是它的反证出口）。
- [x] **cookie jar 在请求之间保持与拼接 Cookie 头，且有可诊断日志** —— `core.CookieJar` 8 条：多 cookie 拆分（含 `Expires` 里的逗号）、
  域/路径匹配（`learn` 的 cookie 不发往 `id`；`.tsinghua.edu.cn` 两者都发）、头拼接顺序、同名覆盖、过期删除（`Max-Age=0` 与 1970 `Expires`）、
  `resetIdDomainSession`（URL 与 host 两种入参）、`describe()` **不泄漏值**。
- [ ] **若证伪（服务端强制要求浏览器），记录证据并提请复审 ADR-0004** —— **未触发**（无账号）。
  判定出口已就绪：`NO_TICKET_IN_RESPONSE` + `diagnostic` 里的 `idLoginPage=true`（`LoginClient` 3 条单测覆盖），
  且 `RequiresEnrollment()` 对所有失败返回 true（spec 第 5 节的降级在代码里可见，不是注释）。

### 三条最容易错的细节：都照参考实现做了，并有单测

1. **桌面 Chrome UA**：`USER_AGENT` 与参考实现 `src/data/source.ts:55-57` 逐字相同；`LoginFlow.test` 断言**每个**请求（4 个）的 `User-Agent` 都等于它，且含 `Windows NT 10.0` 与 `Chrome/120.0.0.0`。
2. **登录前显式重置 jar**：`jar.reset()` + `resetIdDomainSession`，对应 `clearLoginCookies`（`source.ts:11-46`，锁定行为）。单测先往 jar 里塞 `JSESSIONID=STALE-ID` / `SERVERID=STALE-LEARN`，再断言第一个请求的 Cookie 头里都没有它们。
3. **`i_captcha` 恒发空串**：multipart 里字段存在且值为空（单测断言字段名存在 + 值为 `''`）；若服务端要验证码，会由「取不到票据」暴露成 `NO_TICKET_IN_RESPONSE`，不会被静默当成功。

另：**`i_pass` 不再重复拼 `04`**。参考实现是 `'04' + sm2.doEncrypt(...)`（`doEncrypt` 不返回 04），我的 `assembleCipherText` 已经把 `04` 拼好，单测直接断言 `i_pass === SM2_WIRE` 且不以 `0404` 开头。

### 重登：并集 + 各自保留语义（照台账第 2 条）

| 首次结果 | 触发重登 | 重试后 | 返回 |
| --- | --- | --- | --- |
| 正常 | 否 | —— | ok |
| `'[]'`（原生路径，`source.ts:104`） | 是（单飞） | 仍 `'[]'` | ok + `sessionLostAfterReAuth=true`（照原生路径不重分类） |
| `noLogin`（403 / `login_timeout`，`index.js:21`） | 是（单飞） | 仍 noLogin | 失败 `NOT_LOGGED_IN` |
| `noLogin` | 是 | 非 200 | 失败 `UNEXPECTED_STATUS` |
| 任意 | 登录失败 | —— | 失败（透传登录原因，`requiresEnrollment=true`） |

单飞照搬 `source.ts:111-121`：单测用 5 个并发 `gate.run()` + 30ms 延迟的替身登录，断言 `login.calls === 1`、5 个任务各跑 2 次（只重试一次）。

### 与参考实现的有意差异（均已在此登记）

1. **`FailReason.NO_TICKET_IN_RESPONSE`（新增）**：参考实现把「取不到票据」并进 `ERROR_FETCH_FROM_ID`；这里单独一类，因为它是**验收第 5 条（服务端强制浏览器）的唯一可判读出口**。既有分类的字符串值未改动。
2. **`noLogin` 的 URL 判据补了响应体判据**：平台 `@ohos.net.http` **不暴露重定向后的最终 URL**，`res.url.includes('login_timeout')` 这一半在设备上可能永远拿不到；因此判据是「403 ∪ URL 含 ∪ **响应体含**」，是**并集**（更保守），不是替换。
3. **`CookieJar` 的域参数接受 URL 或 host**（内部规范化为 host）：参考实现用 `CookieManager.set(Urls.id, …)` 传的是 URL；单测覆盖两种入参。
4. **`ReAuthRunResult` 多一个 `sessionLostAfterReAuth`**：让「重登后仍失效」这条（原生路径原本静默返回 `'[]'`）在日志与返回值里可见，便于日后升级为 Enrollment 而不改行为。
5. **`Port` 扩展而非改动**：`FetchPort` 的三个方法原样保留，新增 `RawFetchPort`；三域仓储与既有测试端口未受影响。

### 顺手修的不是参考实现的怪癖（如实登记）

`data/upload/UploadForm.ets` 从 ticket 05 起就 import 了 `'../../domain/parse/Multipart'`——而 `Multipart.ets` 实际在 `data/upload/`。
这个错误路径此前**没有暴露**，因为 `UploadForm.ets` 在应用里不可达（`HttpFetchPort` 无人 import，ArkTS 不编译不可达模块）。本轮登录流第一次真正 import 它，编译立刻报 `Could not resolve`。
已改成 `'./Multipart'`（模块位置未变）。这与 `docs/reference-quirks.md` 无关：它不是参考实现的行为，是我在 ticket 05 留下的路径错误。

### 未验证项（判据可复核，不要当成「应该没问题」）

1. **真实账号纯 HTTP 登录**（验收 1）：需要用户先手动登记（ticket 07）。关闭方式：在 `AuthProbe.ets` 填三个常量 → `pwsh -File .scratch/auth/tools/run-auth-probe.ps1` → 看 `PROBE login ok=true` 与 `PROBE session page status=200`。
2. **SM2 产物被服务端接受**（验收 3）：同上那条命令；失败时 `reason` 是 `ERROR_ROAMING`（票据不被接受）即命中 ticket 06 派单前写下的反证条件 ①。
3. **平台 `cryptoFramework` 加密路径本身**：本地只验了纯组装（真实向量）；`createCipher/initSync/doFinalSync/getCipherTextSpec` 只能设备上验。ticket 06 派单前已在模拟器上验过这条链（`.scratch/migration/sm2-verify/device-sm2probe-hilog.log`），但**那次的探针不是本轮代码**——本轮代码的这条路径同样只在探针里跑过编译，没跑过执行。
4. **服务端是否要求验证码**：无账号，无法判断。这是 `idp-login-flow.md` 第 4 节待验证第 3 项。
5. **自动重登在真实 403/`login_timeout` 下的行为**：单测用替身覆盖了全部分支；真实触发条件没遇到过。

### 给 07/08 的接口

- 凭据：`LoginClient.login(credentials?)` 或注入 `provider: () => Promise<Credentials>`；**本模块不读盘**（凭据库归 07）。
- 会话：`LoginResult.session`（`{cookie, csrfToken}` 快照）+ `LoginClient.getJar()` / `sessionForLearn(csrf)`（cookie 会随响应轮换，随用随组）。
- 抓取：`NoticesFetcher/AssignmentsFetcher/FilesFetcher` 接收 `Session`；重登用 `SessionGate.run(task)` 包一层即可，`ReAuthCoordinator` 保证并发只登录一次。