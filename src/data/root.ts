import { combineReducers } from 'redux';
import { auth } from 'data/reducers/auth';
import { settings } from 'data/reducers/settings';
import { courses } from 'data/reducers/courses';
import { notices } from 'data/reducers/notices';
import { user } from 'data/reducers/user';
import { AppState } from 'data/types/state';
import { AppActions } from 'data/types/actions';

const appReducer = combineReducers({
	auth,
	settings,
	courses,
	notices,
	user,
}) as (state: AppState | undefined, action: AppActions) => AppState;

export function rootReducer(
	state: AppState | undefined,
	action: AppActions,
): AppState {
	return appReducer(state, action as any);
}
