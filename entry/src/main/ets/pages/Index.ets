/*
 * 应用首屏：认证门（未登记 → 登录页；已登记 → 主壳）。
 *
 * 参考实现用 showMain = !!username && !!password && !!fingerPrint && loggedIn 把主界面与
 * 登录界面分开（src/App.tsx:720-725）；移植后同一语义落在 AuthStore.phase 上：
 *   LOADING    —— 启动时读一次 asset store，然后用持久化凭据走**纯 HTTP 静默重登**
 *                 （ticket 08；零 WebView，用户无需任何输入）；
 *   UNENROLLED —— 显示登录页（ticket 07 的网页登记入口）。**任何非预期结果都停在这里**
 *                 （信任过期 / 403 / login_timeout / 断网），并给出可理解的提示；
 *   ENROLLED   —— 显示五 tab 主壳（ticket 03/04 交付）。只有会话真的建起来才会到这里，
 *                 因此不存在"带着不存在的会话显示空列表"这条路径。
 *
 * ticket 08 与 07 的边界：07 的 LOADING 只读一次存储（"有没有凭据"）；现在它还要等一次
 * 纯 HTTP 重登，所以启动的首屏空白会多持续一小段（有界：见 SessionRestore 的整体超时）。
 */
import { AuthPhase, authStore } from '../features/auth/AuthStore';
import { LoginPage } from '../features/auth/LoginPage';
import { ShellTabs } from '../features/shell/ShellTabs';

@Entry
@Component
struct Index {
  aboutToAppear(): void {
    // 读凭据 + 静默重登都是异步的；phase 会在完成时刷新界面（@ObservedV2/@Trace）。
    authStore.start();
  }

  build() {
    // @Entry 的 build 只允许一个根节点，且必须是容器组件（不能直接放自定义组件）。
    Column() {
      if (authStore.isEnrolled()) {
        ShellTabs()
      } else if (authStore.phase === AuthPhase.LOADING) {
        // 读凭据 + 重登的一瞬间：空容器而不是闪一下登录页（避免"已登记"用户看到登录框闪屏）。
        Column()
      } else {
        LoginPage()
      }
    }
    .width('100%')
    .height('100%')
  }
}
