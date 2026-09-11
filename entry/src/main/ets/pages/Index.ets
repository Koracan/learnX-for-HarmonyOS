/*
 * 应用首屏：主壳（五个 tab）。
 *
 * pages/ 只做“页面装配”：真正的壳与各 tab 页面在 features/ 下。foundation/01
 * 时期的自检页已由 ticket 03 的导航骨架替换（其验证内容——主题令牌、i18n
 * 资源化、日志门面——仍由各自单测覆盖）。
 */
import { ShellTabs } from '../features/shell/ShellTabs';

@Entry
@Component
struct Index {
  build() {
    // @Entry 的 build 只允许一个根节点，且必须是容器组件（不能直接放自定义组件）。
    Column() {
      ShellTabs()
    }
    .width('100%')
    .height('100%')
  }
}
