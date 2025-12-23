import type { ThunkAction } from 'redux-thunk';
import type { ActionType } from 'typesafe-actions';
import { loginAction, setSSOInProgress } from 'data/actions/auth';
import { setSetting } from 'data/actions/settings';
import { setCourses, getAllCoursesAction } from 'data/actions/courses';
import {
  getAllNoticesForCoursesAction,
  setFavNotice,
  setArchiveNotices,
} from 'data/actions/notices';
import type { PersistAppState } from 'data/types/state';
import { getUserInfoAction } from 'data/actions/user';

type LoginAction = ActionType<typeof loginAction>;
type SetSsoInProgressAction = ActionType<typeof setSSOInProgress>;
export type AuthAction = LoginAction | SetSsoInProgressAction;

type SetSettingAction = ActionType<typeof setSetting>;
export type SettingsAction = SetSettingAction;

type SetCoursesAction = ActionType<typeof setCourses>;
type GetAllCoursesAction = ActionType<typeof getAllCoursesAction>;
export type CoursesAction = SetCoursesAction | GetAllCoursesAction;

type GetAllNoticesForCoursesAction = ActionType<
  typeof getAllNoticesForCoursesAction
>;
type SetFavNoticeAction = ActionType<typeof setFavNotice>;
type SetArchiveNoticesAction = ActionType<typeof setArchiveNotices>;
export type NoticesAction =
  | GetAllNoticesForCoursesAction
  | SetFavNoticeAction
  | SetArchiveNoticesAction;

type GetUserInfoAction = ActionType<typeof getUserInfoAction>;
export type UserAction = GetUserInfoAction;

export type AppActions =
  | AuthAction
  | SettingsAction
  | CoursesAction
  | NoticesAction
  | UserAction;

export type ThunkResult = ThunkAction<
  void,
  PersistAppState,
  undefined,
  AppActions
>;
