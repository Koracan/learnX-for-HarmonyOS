import type { Notice, Assignment, File, Course } from 'data/types/state';

/**
 * 课程栈路由参数定义。
 */
export type CourseStackParams = {
  Courses: undefined;
  CourseDetail: Course;
  NoticeDetail: Notice;
  AssignmentDetail: Assignment;
  FileDetail: File;
};

/**
 * 公告栈路由参数定义。
 */
export type NoticeStackParams = {
  Notices: undefined;
  NoticeDetail: Notice;
};

/**
 * 作业栈路由参数定义。
 */
export type AssignmentStackParams = {
  Assignments: undefined;
  AssignmentDetail: Assignment;
};

/**
 * 文件栈路由参数定义。
 */
export type FileStackParams = {
  Files: undefined;
  FileDetail: File;
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
  CourseStack: undefined;
  NoticeStack: undefined;
  AssignmentStack: undefined;
  FileStack: undefined;
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
