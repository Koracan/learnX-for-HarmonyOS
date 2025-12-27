import { createReducer } from 'typesafe-actions';
import {
  getAllNoticesForCoursesAction,
  getNoticesForCourseAction,
  setArchiveNotices,
  setFavNotice,
} from 'data/actions/notices';
import type { NoticesAction } from 'data/types/actions';
import type { NoticeState } from 'data/types/state';

/**
 * 公告初始状态。
 */
const initialState: NoticeState = {
  fetching: false,
  favorites: [],
  archived: [],
  items: [],
  error: null,
};

/**
 * 公告 reducer：处理公告拉取、收藏、归档。
 */
export const notices = createReducer<NoticeState, NoticesAction>(initialState)
  .handleAction(getAllNoticesForCoursesAction.request, state => ({
    ...state,
    fetching: true,
    error: null,
  }))
  .handleAction(getAllNoticesForCoursesAction.success, (state, action) => ({
    ...state,
    fetching: false,
    items: action.payload,
  }))
  .handleAction(getAllNoticesForCoursesAction.failure, (state, action) => ({
    ...state,
    fetching: false,
    error: action.payload,
  }))
  .handleAction(getNoticesForCourseAction.request, state => ({
    ...state,
    fetching: true,
    error: null,
  }))
  .handleAction(getNoticesForCourseAction.success, (state, action) => ({
    ...state,
    fetching: false,
    items: [
      ...state.items.filter(item => item.courseId !== action.payload.courseId),
      ...action.payload.notices,
    ],
  }))
  .handleAction(getNoticesForCourseAction.failure, (state, action) => ({
    ...state,
    fetching: false,
    error: action.payload,
  }))
  .handleAction(setFavNotice, (state, action) => ({
    ...state,
    favorites: action.payload.flag
      ? [...state.favorites, action.payload.noticeId]
      : state.favorites.filter((id: string) => id !== action.payload.noticeId),
  }))
  .handleAction(setArchiveNotices, (state, action) => ({
    ...state,
    archived: action.payload.flag
      ? [...state.archived, ...action.payload.noticeIds]
      : state.archived.filter(
          (id: string) => !action.payload.noticeIds.includes(id),
        ),
  }));
