/*
 * 认证夹具。成色逐条标注（与 fixtures/README.md 的约定一致）：
 *
 *   [抓取]  开发机上从校园站点实际取回的字节（公开页，无需登录）
 *   [设备]  前期 SM2 验证在模拟器上产出的真实输出（.scratch/migration/sm2-verify/）
 *   [反推]  由参考实现的正则/字段映射反推构造，**非抓取**
 *
 * 夹具用常量而非资源文件（理由同一：让用例自足）。
 */

/**
 * [抓取] 真实 ID 登录页里 #sm2publicKey 的片段。
 *
 * 关键事实：它是 **div 的文本**，不是 input 的 value；且公钥**带 04 前缀**（130 hex）。
 * 这一条此前的技术验证里只是**推断**，这里用真实页面落实。
 */
export const REAL_SM2_PUBLIC_KEY: string =
  '04d0c9e1ae89279fe05b435d63e3eba437bf510e09da5f71558974a19dc596724227f08dc2fc6e74bbb9d8b468d4dd5205e9b6793a3bbc48df3fdf219b3ea140e3';

export const REAL_ID_LOGIN_FORM_SNIPPET: string = `<div class="form-group">
  <label class="control-label" for="password">密码</label>
  <input type="password" id="password" class="form-control" placeholder='密码' required>
  <input type="hidden" id="sm2pass" name="password">
  <div style="display: none;visibility:hidden" id="sm2publicKey">04d0c9e1ae89279fe05b435d63e3eba437bf510e09da5f71558974a19dc596724227f08dc2fc6e74bbb9d8b468d4dd5205e9b6793a3bbc48df3fdf219b3ea140e3</div>
  <div style="display: none;visibility:hidden" id="sm2publicKeyBackup">deadbeef</div>
  <a href="/f/recovery/password/reset"><span id="helpBlock" class="help-block">忘记密码</span></a>
</div>`;

/** [反推] input 形态的变体（兼容分支；真实页面是 div）。 */
export const INPUT_STYLE_SM2_PUBLIC_KEY_HTML: string =
  '<input type="hidden" id="sm2publicKey" value="04d0c9e1ae89279fe05b435d63e3eba437bf510e09da5f71558974a19dc596724227f08dc2fc6e74bbb9d8b468d4dd5205e9b6793a3bbc48df3fdf219b3ea140e3" />';

/** [反推] ID 登录检查成功页：第一个 <a> 指向漫游地址，票据是最后一个 '=' 之后的部分。 */
export const ID_CHECK_WITH_TICKET_HTML: string = `<html><body>
<div class="alert">登录成功，正在跳转…</div>
<a href="https://learn.tsinghua.edu.cn/b/j_spring_security_thauth_roaming_entry?ticket=ST-1234567-abcdef">进入网络学堂</a>
</body></html>`;

/** [反推] 服务端要求验证码/异常页：没有 <a>，票据必然取不到（失败必须由此暴露）。 */
export const ID_CHECK_CAPTCHA_HTML: string = `<html><body>
<div class="alert alert-danger">请输入验证码</div>
<img src="/do/off/ui/auth/captcha" />
</body></html>`;

/**
 * [反推] 学生课程列表页（登录成功后抓 CSRF 的那一页）。
 *
 * 刻意构造三个判据：
 *   1. 同一行里出现**两个** `&_csrf=`，贪婪正则必须取**后一个**（SECOND）；
 *   2. 有一行只有 `_csrf=` 没有前导 `&`，必须**不**命中；
 *   3. 语言标签是整串精确匹配（含前导斜杠）。
 */
export const COURSE_LIST_PAGE_HTML: string = `<html><head>
<script src="/f/wlxt/common/languagejs?lang=zh"></script>
</head><body>
<script>window.a = "&_csrf=FIRST_TOKEN"; window.b = "&_csrf=SECOND_TOKEN";</script>
<div data-x="_csrf=NOT_A_MATCH"></div>
<input type="hidden" name="_csrf" value="THIRD_TOKEN">
</body></html>`;

/** [反推] 语言为英文的变体。 */
export const COURSE_LIST_PAGE_EN_HTML: string =
  '<html><head><script src="/f/wlxt/common/languagejs?lang=en"></script></head><body><script>var u="&_csrf=EN_TOKEN";</script></body></html>';

/** [反推] 会话已失效：响应里带 login_timeout（thu-learn-lib 路径的判据之一）。 */
export const LOGIN_TIMEOUT_BODY: string = '<html><body>location.href="/f/login_timeout"</body></html>';

/** [反推] 原生处理器路径的失效形态：空 JSON 数组。 */
export const EMPTY_LIST_BODY: string = '[]';

/* ------------------------------------------------------------------
 * [设备] SM2 上线密文向量（.scratch/migration/sm2-verify/arkts-wire.txt，模拟器实测产出）
 * 明文 = learnOH-sm2-probe-2026-密码Æ，排列 C1C3C2，全小写 hex，04 前缀。
 * 纯组装函数必须能由下面四段原样拼出 WIRE。
 * ------------------------------------------------------------------ */
export const SM2_WIRE: string =
  '04c345866a7f6c1f5272df6686a0774ddd905a35a0903fde52f8f7b3d2cafaf25457f00c032cbc9ac3af989f13084b58ee344890cb63ba4d5329c1a4350727a87c402fec274cf9826ed6661a62b29858561e0ee826d3337b6ed1cffb09786a2124a893a22e65f2222e36cb66882999290fd7e58f08de403628a54810d552b0d6';

export const SM2_WIRE_X: string = 'c345866a7f6c1f5272df6686a0774ddd905a35a0903fde52f8f7b3d2cafaf254';
export const SM2_WIRE_Y: string = '57f00c032cbc9ac3af989f13084b58ee344890cb63ba4d5329c1a4350727a87c';
export const SM2_WIRE_C3: string = '402fec274cf9826ed6661a62b29858561e0ee826d3337b6ed1cffb09786a2124';
export const SM2_WIRE_C2: string = 'a893a22e65f2222e36cb66882999290fd7e58f08de403628a54810d552b0d6';

/** [设备] 首字节被高零截断的形态：把 X 的最前一个字符去掉，组装时必须左补零还原。 */
export const SM2_WIRE_X_TRUNCATED: string = '345866a7f6c1f5272df6686a0774ddd905a35a0903fde52f8f7b3d2cafaf254';

/* ------------------------------------------------------------------
 * [反推] Set-Cookie 样本：覆盖多 cookie 拼接、值里含逗号、Expires 含逗号、空值。
 * ------------------------------------------------------------------ */
export const SET_COOKIE_TWO_COOKIES: string =
  'JSESSIONID=ABC123; Path=/; HttpOnly, SERVERID=node1; Path=/';

export const SET_COOKIE_WITH_EXPIRES: string =
  'CASTGC=TGT-1; Path=/; Expires=Wed, 21 Oct 2026 07:28:00 GMT; Secure; HttpOnly';

export const SET_COOKIE_EMPTY_JSESSIONID: string = 'JSESSIONID=; Path=/; HttpOnly';

/* ------------------------------------------------------------------
 * [设备] 平台 `HttpResponse.cookies` 的**实测形态**（模拟器 Pura 90 / 127.0.0.1:5555）：
 * 制表符分隔的 7 字段 Netscape cookie-file 行，不是 `name=value; attrs`。
 *
 * 逐字来源：`.scratch/enrollment/evidence/experiment-w12/E5-page-cookie-format.txt`
 * （`POST /do/off/ui/auth/login/check` 的响应；值只留前缀，其余用 `…` 占位以保持长度可比）。
 * ------------------------------------------------------------------ */
export const NETSCAPE_COOKIE_LINE: string =
  '#HttpOnly_id.tsinghua.edu.cn\tFALSE\t/\tFALSE\t0\tJSESSIONID\tFB9C7214ABA6E5BDE3BCD45DA90494CC.authweb1';

/** [反推] 两行 Netscape 形态（多 cookie；第二条带前导点域、secure=TRUE、有 expiry）。 */
export const NETSCAPE_COOKIE_TWO_LINES: string =
  '#HttpOnly_id.tsinghua.edu.cn\tFALSE\t/\tFALSE\t0\tJSESSIONID\tAAA111\n'
  + '.tsinghua.edu.cn\tTRUE\t/\tTRUE\t1893456000\tCASTGC\tTGT-9';

/** [反推] 值里含 '='、且域不带前导点的 Netscape 行。 */
export const NETSCAPE_COOKIE_VALUE_WITH_EQUALS: string =
  'id.tsinghua.edu.cn\tFALSE\t/do/off\tFALSE\t0\tTOKEN\tYWJjPT0=';

