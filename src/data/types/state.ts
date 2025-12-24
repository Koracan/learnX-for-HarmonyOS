// Minimal state and entity definitions for the mini prototype (login + notices)

export interface Auth {
  username: string | null;
  password: string | null;
  fingerPrint: string | null;
  fingerGenPrint: string | null;
  fingerGenPrint3: string | null;
}

export interface AuthState extends Auth {
  loggingIn: boolean;
  ssoInProgress: boolean;
  loggedIn: boolean;
  error?: any | null;
}

export interface SettingsState {
  graduate: boolean;
}

export interface Course {
  id: string;
  name: string;
  teacherName?: string;
}

export interface CoursesState {
  fetching: boolean;
  items: Course[];
  hidden: string[];
  error?: any | null;
}

export interface CourseExtraInfo {
  courseId: string;
  courseName: string;
}

export interface Notice extends CourseExtraInfo {
  id: string;
  title: string;
  publishTime: string;
  content?: string;
}

export interface NoticeState {
  fetching: boolean;
  favorites: string[];
  archived: string[];
  items: Notice[];
  error?: any | null;
}

export interface UserState {
  fetching: boolean;
  info: any | null;
  error?: any | null;
}

export interface AppState {
  auth: AuthState;
  settings: SettingsState;
  courses: CoursesState;
  notices: NoticeState;
  user: UserState;
}

export interface PersistAppState extends AppState {
  _persist?: any;
}
