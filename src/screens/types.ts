import type { Notice } from 'data/types/state';

/**
 * 公告栈路由参数定义。
 */
export type NoticeStackParams = {
  Notices: undefined;
  NoticeDetail: Notice;
};

/**
 * 根栈路由参数定义。
 */
export type RootStackParams = {
  Login: undefined;
  SSO: { username: string; password: string };
  NoticeStack: undefined;
};
