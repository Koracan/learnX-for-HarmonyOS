/*
 * 搜索页的路由名与参数。
 *
 * 参考实现是一个**根级**的 SearchStack（`src/App.tsx:350-378`）：
 *   Search + NoticeDetail + AssignmentDetail + FileDetail。
 * 本工程同构：ShellTabs 的根 Navigation 里一条 `Search` 路由，搜索页内部再放一个自己的栈
 * （单栏时详情压在里面；分栏时压进右栏 —— 见 features/search/SearchPage.ets 文件头）。
 */

/** 搜索页路由名（唯一入口是页头右侧的 search 图标，见 SearchEntry.openSearch）。 */
export const ROUTE_SEARCH: string = 'Search';

/**
 * 搜索页的入口参数。
 *
 * 参考实现是 `useState(route.params?.query ?? '')`（`Search.tsx:39`）—— 搜索页**可以被带着
 * 查询词进入**。这里保留同一个能力（页头图标目前只传空查询，接口留着）。
 */
export interface SearchRouteParams {
  query: string;
}
