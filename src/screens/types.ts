import { type NavigatorScreenParams } from '@react-navigation/native';
import type { Notice, Assignment, File, Course } from 'data/types/state';

export interface ExtraParams {
  disableAnimation?: boolean;
}

/**
 * 课程栈路由参数定义。
 */
export type CourseStackParams = {
  Courses: undefined;
  CourseDetail: Course & ExtraParams;
  NoticeDetail: Notice & ExtraParams;
  AssignmentDetail: Assignment & ExtraParams;
  FileDetail: File & ExtraParams;
  AssignmentSubmission: Assignment & ExtraParams;
};

/**
 * 公告栈路由参数 definition.
 */
export type NoticeStackParams = {
  Notices: undefined;
  NoticeDetail: Notice & ExtraParams;
  FileDetail: File & ExtraParams;
};

/**
 * 作业栈路由参数 definition.
 */
export type AssignmentStackParams = {
  Assignments: undefined;
  AssignmentDetail: Assignment & ExtraParams;
  FileDetail: File & ExtraParams;
  AssignmentSubmission: Assignment & ExtraParams;
};

/**
 * 文件栈路由参数定义。
 */
export type FileStackParams = {
  Files: undefined;
  FileDetail: File & ExtraParams;
};

/**
 * 设置栈路由参数定义。
 */
export type SettingsStackParams = {
  Settings: undefined;
  SemesterSelection: ExtraParams;
  FileSettings: ExtraParams;
  About: ExtraParams;
  Help: ExtraParams;
  CourseInformationSharing: ExtraParams;
  CalendarEvent: ExtraParams;
};

/**
 * 主选项卡导航参数定义。
 */
export type MainTabParams = {
  NoticeStack: NavigatorScreenParams<NoticeStackParams>;
  AssignmentStack: NavigatorScreenParams<AssignmentStackParams>;
  FileStack: NavigatorScreenParams<FileStackParams>;
  CourseStack: NavigatorScreenParams<CourseStackParams>;
  SettingsStack: NavigatorScreenParams<SettingsStackParams>;
};

export type LoginStackParams = {
  Login: undefined;
  SSO: {
    username: string;
    password: string;
  };
};

export type CourseXStackParams = {
  CourseX: { id: string } | undefined;
};

export type SearchStackParams = {
  Search:
    | {
        query: string;
      }
    | undefined;
  NoticeDetail: Notice & ExtraParams;
  AssignmentDetail: Assignment & ExtraParams;
  FileDetail: File & ExtraParams;
};

export type AssignmentSubmissionStackParams = {
  AssignmentSubmission: Assignment;
  FileDetail: File & ExtraParams;
};

export type DetailStackParams = {
  EmptyDetail: undefined;
  NoticeDetail: Notice & ExtraParams;
  AssignmentDetail: Assignment & ExtraParams;
  AssignmentSubmission: Assignment & ExtraParams;
  FileDetail: File & ExtraParams;
  CourseDetail: Course & ExtraParams;
  SemesterSelection: ExtraParams;
  FileSettings: ExtraParams;
  About: ExtraParams;
  Help: ExtraParams;
  CourseInformationSharing: ExtraParams;
  CalendarEvent: ExtraParams;
};

/**
 * 根栈路由参数定义。
 */
export type RootStackParams = {
  MainTab: NavigatorScreenParams<MainTabParams>;
  CourseXStack: NavigatorScreenParams<CourseXStackParams>;
  SearchStack: NavigatorScreenParams<SearchStackParams>;
  AssignmentSubmissionStack: NavigatorScreenParams<AssignmentSubmissionStackParams>;
  LoginStack: NavigatorScreenParams<LoginStackParams>;
};
