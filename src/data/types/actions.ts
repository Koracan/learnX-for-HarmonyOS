import type { ThunkAction } from 'redux-thunk';
import type { ActionType } from 'typesafe-actions';
import { loginAction, setSSOInProgress } from 'data/actions/auth';
import {
  setSetting,
  setEventIdForAssignment,
  removeEventIdForAssignment,
  clearEventIds,
} from 'data/actions/settings';
import {
  setCourses,
  setHideCourse,
  setCourseOrder,
  getCoursesForSemesterAction,
} from 'data/actions/courses';
import {
  getAllNoticesForCoursesAction,
  getNoticesForCourseAction,
  setFavNotice,
  setArchiveNotices,
} from 'data/actions/notices';
import {
  getAllAssignmentsForCoursesAction,
  getAssignmentsForCourseAction,
  setFavAssignment,
  setArchiveAssignments,
  setPendingAssignmentData,
} from 'data/actions/assignments';
import {
  getAllFilesForCoursesAction,
  getFilesForCourseAction,
  setFavFile,
  setArchiveFiles,
} from 'data/actions/files';
import type { PersistAppState } from 'data/types/state';
import { getUserInfoAction } from 'data/actions/user';
import {
  getAllSemestersAction,
  getCurrentSemesterAction,
  setCurrentSemester,
} from 'data/actions/semesters';
import { resetLoading } from 'data/actions/root';

type LoginAction = ActionType<typeof loginAction>;
type SetSsoInProgressAction = ActionType<typeof setSSOInProgress>;
export type AuthAction = LoginAction | SetSsoInProgressAction;

type SetSettingAction = ActionType<typeof setSetting>;
type SetEventIdForAssignmentAction = ActionType<typeof setEventIdForAssignment>;
type RemoveEventIdForAssignmentAction = ActionType<
  typeof removeEventIdForAssignment
>;
type ClearEventIdsAction = ActionType<typeof clearEventIds>;
export type SettingsAction =
  | SetSettingAction
  | SetEventIdForAssignmentAction
  | RemoveEventIdForAssignmentAction
  | ClearEventIdsAction;

type SetCoursesAction = ActionType<typeof setCourses>;
type SetHideCourseAction = ActionType<typeof setHideCourse>;
type SetCourseOrderAction = ActionType<typeof setCourseOrder>;
type GetCoursesForSemesterAction = ActionType<
  typeof getCoursesForSemesterAction
>;
export type CoursesAction =
  | SetCoursesAction
  | SetHideCourseAction
  | SetCourseOrderAction
  | GetCoursesForSemesterAction;

type GetAllNoticesForCoursesAction = ActionType<
  typeof getAllNoticesForCoursesAction
>;
type GetNoticesForCourseAction = ActionType<typeof getNoticesForCourseAction>;
type SetFavNoticeAction = ActionType<typeof setFavNotice>;
type SetArchiveNoticesAction = ActionType<typeof setArchiveNotices>;
export type NoticesAction =
  | GetAllNoticesForCoursesAction
  | GetNoticesForCourseAction
  | SetFavNoticeAction
  | SetArchiveNoticesAction;

type GetAllAssignmentsForCoursesAction = ActionType<
  typeof getAllAssignmentsForCoursesAction
>;
type GetAssignmentsForCourseAction = ActionType<
  typeof getAssignmentsForCourseAction
>;
type SetFavAssignmentAction = ActionType<typeof setFavAssignment>;
type SetArchiveAssignmentsAction = ActionType<typeof setArchiveAssignments>;
type SetPendingAssignmentDataAction = ActionType<
  typeof setPendingAssignmentData
>;
export type AssignmentsAction =
  | GetAllAssignmentsForCoursesAction
  | GetAssignmentsForCourseAction
  | SetFavAssignmentAction
  | SetArchiveAssignmentsAction
  | SetPendingAssignmentDataAction;

type GetFilesForCourseAction = ActionType<typeof getFilesForCourseAction>;
type GetAllFilesForCoursesAction = ActionType<
  typeof getAllFilesForCoursesAction
>;
type SetFavFileAction = ActionType<typeof setFavFile>;
type SetArchiveFilesAction = ActionType<typeof setArchiveFiles>;
export type FilesAction =
  | GetFilesForCourseAction
  | GetAllFilesForCoursesAction
  | SetFavFileAction
  | SetArchiveFilesAction;

type GetUserInfoAction = ActionType<typeof getUserInfoAction>;
export type UserAction = GetUserInfoAction;

type GetAllSemestersAction = ActionType<typeof getAllSemestersAction>;
type GetCurrentSemesterAction = ActionType<typeof getCurrentSemesterAction>;
type SetCurrentSemesterAction = ActionType<typeof setCurrentSemester>;
export type SemestersAction =
  | GetAllSemestersAction
  | GetCurrentSemesterAction
  | SetCurrentSemesterAction;

export type ResetLoadingAction = ActionType<typeof resetLoading>;
export type StoreAction = ResetLoadingAction;

export type AppActions =
  | AuthAction
  | SettingsAction
  | CoursesAction
  | NoticesAction
  | AssignmentsAction
  | FilesAction
  | UserAction
  | SemestersAction
  | StoreAction;

export type ThunkResult = ThunkAction<
  void,
  PersistAppState,
  undefined,
  AppActions
>;
