import type { Notice } from 'data/types/state';

/**
 * 公告栈路由参数定义。
 */
export type NoticeStackParams = {
  Notices: undefined;
  NoticeDetail: Notice;
};

/**
 * 设置栈路由参数定义。
 */
export type SettingsStackParams = {
  Settings: undefined;
};

/**
 * 主选项卡导航参数定义。
 */
export type MainTabParams = {
  NoticeStack: undefined;
  SettingsStack: undefined;
};

/**
 * 根栈路由参数定义。
 */
export type RootStackParams = {
  Login: undefined;
  SSO: { username: string; password: string };
  MainTab: undefined;
};
