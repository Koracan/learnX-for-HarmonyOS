import type { Notice } from 'data/types/state';

export type NoticeStackParams = {
  Notices: undefined;
  NoticeDetail: Notice;
};

export type RootStackParams = {
  Login: undefined;
  SSO: { username: string; password: string };
  NoticeStack: undefined;
};
