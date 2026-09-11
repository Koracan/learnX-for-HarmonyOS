/*
 * 应用首屏：认证门（未登记 → 登录页；已登记 → 主壳）。
 *
 * 参考实现用 showMain = !!username && !!password && !!fingerPrint && loggedIn 把主界面与
 * 登录界面分开（src/App.tsx:720-725）；移植后同一语义落在 AuthStore.phase 上：
 *   LOADING    —— 启动时读一次 asset store（凭据在，就是「已登记」）；
 *   UNENROLLED —— 显示登录页（ticket 07 的网页登记入口）；
 *   ENROLLED   —— 显示五 tab 主壳（ticket 03/04 交付）。
 *
 * **本 ticket 只判定"是否已登记"**：冷启动用凭据静默重登、会话失效降级是 ticket 08 的范围。
 * 因此这里不做任何网络请求，也就不存在"启动卡在加载态"的问题。
 */
import { AuthPhase, authStore } from '../features/auth/AuthStore';
import { LoginPage } from '../features/auth/LoginPage';
import { ShellTabs } from '../features/shell/ShellTabs';

@Entry
@Component
struct Index {
  aboutToAppear(): void {
    // 读凭据是异步的；phase 会在读完时刷新界面（@ObservedV2/@Trace）。
    authStore.loadPersisted();
  }

  build() {
    // @Entry 的 build 只允许一个根节点，且必须是容器组件（不能直接放自定义组件）。
    Column() {
      if (authStore.isEnrolled()) {
        ShellTabs()
      } else if (authStore.phase === AuthPhase.LOADING) {
        // 读凭据的一瞬间：空容器而不是闪一下登录页（避免"已登记"用户看到登录框闪屏）。
        Column()
      } else {
        LoginPage()
      }
    }
    .width('100%')
    .height('100%')
  }
}
