import { createReducer } from 'typesafe-actions';
import {
  getAllNoticesForCoursesAction,
  setArchiveNotices,
  setFavNotice,
} from 'data/actions/notices';
import { NoticesAction } from 'data/types/actions';
import { NoticeState } from 'data/types/state';

const initialState: NoticeState = {
  fetching: false,
  favorites: [],
  archived: [],
  items: [],
  error: null,
};

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
