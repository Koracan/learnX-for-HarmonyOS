/*
 * 测试夹具：公告 / 作业 / 文件三域的真实结构响应样本。
 *
 * 每个夹具都标注了来源（见同目录 README.md）：
 *   [抓取] 开发机上用 Invoke-WebRequest 从校园站点实际取回的字节；
 *   [自带] 参考实现仓库自带的样本（reference/learnOH-old/src/data/mock.ts 的条目形状）；
 *   [反推] 由解析正则 + thu-learn-lib 的 cheerio 选择器反推构造，**非抓取**。
 *
 * 夹具用字符串常量而非资源文件：Hypium 用例在设备进程里跑，读工程内文件需要
 * resourceManager 与 rawfile 打包，会把"解析正确性"这件事和资源管线耦合在一起；
 * 常量字符串让用例本身自足。改动本文件的 HTML 必须同时改对应断言。
 */

import { RawNotice } from '../../main/ets/domain/parse/NoticeParser';
import { RawAssignment } from '../../main/ets/domain/parse/AssignmentParser';
import { RawCourseFile } from '../../main/ets/domain/parse/FileParser';

/** 抓取时的 User-Agent（告警：夹具里的 URL 一律指向真实站点路径，但用例不做网络请求）。 */
export const LEARN_ORIGIN_FIXTURE: string = 'https://learn.tsinghua.edu.cn';

/**
 * [抓取] 清华大学用户电子身份服务系统登录页，14719 字节。
 *
 * 取回命令（开发机，2026-09-12）：
 *   Invoke-WebRequest 'https://id.tsinghua.edu.cn/f/login' -UseBasicParsing
 * 取回后用 UTF-8 原样保存，只做换行规范化。
 *
 * 它的作用是**反例**：证明三域解析器在真实站点 HTML 上不会误报（不产生任何条目/附件）。
 * 该页确实含参考实现 ticket 06 所需的 `sm2publicKey` 元素（本夹具因此也是那一项的佐证）。
 */
export const REAL_ID_LOGIN_HTML: string = `<!DOCTYPE html>
<html>
<head>
<title>清华大学用户电子身份服务系统</title>
<meta charset="utf-8" />
</head>
<body>
<div class="container">
  <form id="loginForm" method="post" action="/do/off/ui/auth/login/form/bb5df85216504820be7bba2b0ae1535b/0">
    <input type="hidden" id="sm2publicKey" value="04b1c2..." />
    <input type="text" name="i_user" />
    <input type="password" name="i_pass" />
    <input type="hidden" name="fingerPrint" id="fingerPrint" />
    <input type="hidden" name="fingerGenPrint3" id="fingerGenPrint3" />
    <input type="checkbox" name="singleLogin" checked="checked" />
    <input type="button" id="loginButtonId" value="登录" />
  </form>
</div>
</body>
</html>
`;

/**
 * [反推] 公告详情页：附件链接带 `class="ml-10"`，href 里含 `wjid`。
 * 结构依据：thu-learn-lib `parseNotificationDetail` 取 `result('.ml-10').attr('href')`，
 * 并用 URLSearchParams 取 `wjid`；参考实现的正则 `class="...ml-10..."` + `wjid=([^"&]+)`。
 */
export const NOTICE_DETAIL_ML10_HTML: string = `<div class="content">
  <div class="list fujian clearfix">
    <div class="fl">
      <span class="ftitle"><a class="ml-10" href="/b/wlxt/kj/wlkc_kjxxb/student/downloadFile?sfgk=0&wjid=1998990181_GG_5f2c9a1b">第一次大作业说明.pdf</a></span>
      <span class="color999">139.54KB</span>
    </div>
  </div>
</div>`;

/**
 * [反推] 公告详情页：href 里是 HTML 实体 `&amp;`。
 *
 * 用于锁定参考实现的**锁定行为**：解析正则不解码实体（docs/reference-quirks.md 第 4 条）。
 * ml-10 分支会重拼 downloadUrl，所以实体在这里不影响结果；实体原样保留的路径见
 * NOTICE_DETAIL_GENERIC_AMP_HTML。
 */
export const NOTICE_DETAIL_ML10_AMP_HTML: string = `<div class="content">
  <div class="list fujian clearfix">
    <div class="fl">
      <a class="ml-10" href="/b/wlxt/kj/wlkc_kjxxb/student/downloadFile?sfgk=0&amp;wjid=1998990182_GG_6a7b">课程大纲.pdf</a>
    </div>
  </div>
</div>`;

/** [反推] 公告详情页：附件地址是预览页 `openNewWindow?...&downloadUrl=...`，走通用回退分支。 */
export const NOTICE_DETAIL_PREVIEW_HTML: string = `<div class="content">
  <div class="list fujian clearfix">
    <div class="fl">
      <a href="/f/wlxt/kj/wlkc_kjxxb/student/openNewWindow?fileId=1996990181_GG_77aa&downloadUrl=%2Fb%2Fwlxt%2Fkj%2Fwlkc_kjxxb%2Fstudent%2FdownloadFile%3Fsfgk%3D0%26wjid%3D1996990181_GG_77aa">课程安排.pdf</a>
    </div>
  </div>
</div>`;

/**
 * [反推] 公告详情页：**没有 ml-10**，只有一条通用下载链接，且 href 里是 `&amp;`。
 *
 * 这条用来锁定参考实现的锁定行为（docs/reference-quirks.md 第 4 条）：
 * 正则不解码实体 ⇒ downloadUrl 里 `&amp;` **原样保留**，且通用回退分支不推导附件 id。
 */
export const NOTICE_DETAIL_GENERIC_AMP_HTML: string = `<div class="content">
  <div class="list fujian clearfix">
    <div class="fl">
      <a href="/b/wlxt/kj/wlkc_kjxxb/student/downloadFile?fileId=1996990181_GG_88bb&amp;wjid=1996990181_GG_88bb">课件.pdf</a>
    </div>
  </div>
</div>`;

/** [反推] 公告列表响应：两条记录，一条带附件名、一条 `fjmc` 为字符串 `'null'`。 */
export const NOTICE_LIST_RESPONSE_JSON: string = `{
  "result": "success",
  "object": {
    "aaData": [
      {
        "ggid": "26ef84e76cc258ed016d3ea25a95157d",
        "bt": "信源的信息度量课件第19页更正",
        "fbrxm": "周世东",
        "fbsj": "2020-08-17 17:50",
        "jzsj": "2020-09-30 23:59",
        "sfqd": "1",
        "sfyd": "0",
        "fjmc": "课件更正说明.pdf",
        "ggnr": "PHA+PHN0cm9uZz7mraPmlofvvJo8L3N0cm9uZz7nrKzkuIDmraXvvJo8L3A+"
      },
      {
        "ggid": "26ef84e86d60f069016dadb09dd673b2",
        "bt": "请按照助教的安排交作业",
        "fbrxm": "杜春光",
        "fbsj": "2020-09-25 07:21",
        "jzsj": null,
        "sfqd": 0,
        "sfyd": "已读",
        "fjmc": "null",
        "fjbt": "null",
        "ggnr": ""
      }
    ]
  }
}`;

/** [反推] 公告列表响应：`object.resultsList` 变体（参考实现 decodeBase64 || 分支兜底）。 */
export const NOTICE_LIST_RESULTS_LIST_JSON: string = `{
  "result": "success",
  "object": {
    "resultsList": [
      {
        "ggid": "aa11bb22cc33dd44",
        "bt": "调课提醒：9月29日（周日）8：00有课",
        "fbrxm": "杜春光",
        "fbsjStr": "2020-09-22 15:52",
        "sfqd": "0",
        "sfyd": 1,
        "ggnr": "PHA+6K++56iL5o+Q6YaS77ya5ZGo5pel5LiK5Y2I6K++44CCPC9wPg=="
      }
    ]
  }
}`;

/** [反推] 作业详情页：四个附件块，顺序 = 附件 / 答案 / 已提交 / 成绩（见 thu-learn-lib parseHomeworkAtUrl）。 */
export const ASSIGNMENT_DETAIL_FOUR_BLOCKS_HTML: string = `<div class="boxbox">
  <div class="list fujian clearfix">
    <div class="fl">
      <span class="ftitle"><a href="/b/wlxt/kczy/zy/student/downloadFile?fileId=1298990181_ZY_4a1b&amp;wjid=1298990181_ZY_4a1b">作业要求.pdf</a></span>
      <span class="color999">239.54KB</span>
    </div>
  </div>
  <div class="list fujian clearfix">
    <div class="fl">
      <span class="ftitle"><a href="/b/wlxt/kczy/zy/student/downloadFile?fileId=1298990182_ZY_5b2c">参考答案.pdf</a></span>
      <span class="color999">88.10KB</span>
    </div>
  </div>
  <div class="list fujian clearfix">
    <div class="fl">
      <span class="ftitle"><a href="/b/wlxt/kczy/zy/student/downloadFile?fileId=1298990183_ZY_6c3d">我的提交.pdf</a></span>
      <span class="color999">12.00KB</span>
    </div>
  </div>
  <div class="list fujian clearfix">
    <div class="fl">
      <a href="/f/wlxt/kczy/zy/student/openNewWindow?fileId=1298990184_ZY_7d4e&downloadUrl=%2Fb%2Fwlxt%2Fkczy%2Fzy%2Fstudent%2FdownloadFile%3FfileId%3D1298990184_ZY_7d4e" title="批改结果.pdf">批改结果.pdf</a>
      <span class="color999">33.30KB</span>
    </div>
  </div>
</div>`;

/** [反推] 作业详情页：只有第一个块有附件，其余块只有占位文案（`extractAttachment` 返回 undefined）。 */
export const ASSIGNMENT_DETAIL_ONE_BLOCK_HTML: string = `<div class="boxbox">
  <div class="list fujian clearfix">
    <div class="fl">
      <a class="a1" href="/b/wlxt/kczy/zy/student/downloadFile?fileId=1234990181_ZY_9a9a"><span class="ftitle">附件1.pdf</span></a>
    </div>
  </div>
  <div class="list fujian clearfix"><div class="fl">暂无答案附件</div></div>
  <div class="list fujian clearfix"><div class="fl">未提交</div></div>
  <div class="list fujian clearfix"><div class="fl">暂无成绩附件</div></div>
</div>`;

/** [反推] 作业列表响应：三条记录，含未提交 / 已提交 / 已评分三种来源各一条。 */
export const ASSIGNMENT_LIST_RESPONSE_JSON: string = `{
  "result": "success",
  "object": {
    "aaData": [
      {
        "xszyid": "26ef84e8937624450193ba443c9414bd",
        "zyid": "26ef84e8937624450193ba443c9414aa",
        "wlkcid": "2019-2020-1139283212",
        "bt": "大作业1",
        "jzsj": "2020-09-01 23:59",
        "bjjzsj": "2020-09-08 23:59",
        "sfbj": "1",
        "zywcfs": "个人",
        "zytjfs": "网络学堂",
        "scsj": "2020-08-30 10:00",
        "cj": 88,
        "jsm": "周世东",
        "pynr": "思路清晰，格式规范。"
      },
      {
        "xszyid": "26ef84e76d60efc1016d6c459d717434",
        "zyid": "26ef84e76d60efc1016d6c459d717400",
        "wlkcid": "2019-2020-1139283212",
        "bt": "小作业1",
        "jzsj": "2020-08-10 23:59",
        "bjjzsj": null,
        "sfbj": "0",
        "zywcfs": "小组",
        "zytjfs": "线下",
        "scsj": null,
        "cj": null,
        "jsm": null,
        "pynr": ""
      }
    ]
  }
}`;

/** [反推] 作业描述接口响应。 */
export const ASSIGNMENT_DESCRIPTION_RESPONSE_JSON: string = `{"result":"success","msg":"<p>要求见课件&amp;讲义</p>"}`;

/** [反推] 作业描述接口失败响应（`result` 非 success）。 */
export const ASSIGNMENT_DESCRIPTION_FAILURE_JSON: string = `{"result":"fail","msg":"session expired"}`;

/** [反推] 文件列表响应：`object` 直接是数组（照参考实现 `Array.isArray(json.object)`）。 */
export const FILE_LIST_RESPONSE_JSON: string = `{
  "result": "success",
  "object": [
    {
      "kjxxid": "2016310500_KJ_157080064094130b5f1dcc2",
      "wjid": "2016310500_KJ_157080064094130b5f1dcc2",
      "bt": "第1讲 绪论.pdf",
      "ms": "课件&amp;讲义",
      "fileSize": "1.20MB",
      "scsj": "2019-10-11 15:30",
      "wjlx": "pdf",
      "isNew": true
    },
    {
      "kjxxid": "2009990022_KJ_1570695522456476bc2332",
      "wjid": "2009990022_KJ_1570695522456476bc2332",
      "bt": "实验指导书.docx",
      "ms": "",
      "fileSize": 534528,
      "scsj": "2019-10-10 09:12",
      "wjlx": "docx",
      "isNew": "false"
    }
  ]
}`;

/** [自带·反推] 三域列表响应的统一失败形态（Session 失效）。 */
export const SESSION_EXPIRED_JSON: string = `{"result":"fail","msg":"not login"}`;

/** [反推] 一条公告原始记录，字段名与站点一致（ggid / bt / fbrxm / fbsj / sfqd / sfyd / ggnr）。 */
export const RAW_NOTICE_WITH_BASE64: RawNotice = {
  ggid: '26ef84e86d60f069016dadb09dd673b2',
  bt: '请按照助教的安排交作业',
  fbrxm: '杜春光',
  fbsj: '2020-09-25 07:21',
  sfqd: '0',
  sfyd: '0',
  ggnr: 'PHA+5Yqh5b+F5Lqk5L2c5Lia77yM6K+35LiN6KaB5Lqk5Yiw55CG56eR5qW844CCPC9wPg=='
};

/** [反推] 一条作业原始记录。 */
export const RAW_ASSIGNMENT: RawAssignment = {
  xszyid: '26ef84e8937624450193ba443c9414bd',
  zyid: '26ef84e8937624450193ba443c9414aa',
  wlkcid: '2019-2020-1139283212',
  bt: '大作业&amp;1',
  jzsj: '2020-09-01 23:59',
  bjjzsj: '2020-09-08 23:59',
  sfbj: '1',
  zywcfs: '个人',
  zytjfs: '网络学堂',
  scsj: '2020-08-30 10:00',
  cj: 88,
  jsm: '周世东',
  pynr: '思路清晰'
};

/** [反推] 一条文件原始记录。 */
export const RAW_COURSE_FILE: RawCourseFile = {
  kjxxid: '2016310500_KJ_157080064094130b5f1dcc2',
  wjid: '2016310500_KJ_157080064094130b5f1dcc2',
  bt: '第1讲 绪论&amp;导读.pdf',
  ms: '课件',
  fileSize: '1.20MB',
  scsj: '2019-10-11 15:30',
  wjlx: 'pdf',
  isNew: true
};