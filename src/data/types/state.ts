import type {
  CourseInfo,
  FailReason,
  Homework,
  Notification,
  File as IFile,
} from 'thu-learn-lib';

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
  error?: FailReason | null;
}

export interface SettingsState {
  graduate: boolean;
  immersiveMode: boolean;
  fileUseDocumentDir: boolean;
  fileOmitCourseName: boolean;
}

export interface SemestersState {
  fetching: boolean;
  items: string[];
  current: string | null;
  error?: FailReason | null;
}

export type Course = Pick<
  CourseInfo,
  | 'id'
  | 'name'
  | 'teacherNumber'
  | 'teacherName'
  | 'timeAndLocation'
  | 'courseNumber'
  | 'courseIndex'
  | 'chineseName'
  | 'englishName'
> & {
  semesterId: string;
};

export interface CoursesState {
  fetching: boolean;
  items: Course[];
  names: {
    [id: string]: {
      name: string;
      teacherName: string;
    };
  };
  hidden: string[];
  order: string[];
  error?: FailReason | null;
}

export interface CourseExtraInfo {
  courseId: string;
  courseName: string;
  courseTeacherName: string;
}

export type Notice = Pick<
  Notification,
  | 'id'
  | 'title'
  | 'publisher'
  | 'publishTime'
  | 'expireTime'
  | 'markedImportant'
  | 'content'
  | 'hasRead'
  | 'attachment'
  | 'url'
> &
  CourseExtraInfo;

export interface NoticeState {
  fetching: boolean;
  favorites: string[];
  archived: string[];
  items: Notice[];
  error?: FailReason | null;
}

export type Assignment = Pick<
  Homework,
  | 'id'
  | 'studentHomeworkId'
  | 'title'
  | 'description'
  | 'deadline'
  | 'lateSubmissionDeadline'
  | 'completionType'
  | 'submissionType'
  | 'attachment'
  | 'submitted'
  | 'isLateSubmission'
  | 'submitTime'
  | 'submittedContent'
  | 'submittedAttachment'
  | 'graded'
  | 'grade'
  | 'gradeLevel'
  | 'graderName'
  | 'gradeTime'
  | 'gradeContent'
  | 'gradeAttachment'
  | 'answerContent'
  | 'answerAttachment'
  | 'url'
  | 'excellentHomeworkList'
> &
  CourseExtraInfo;

export interface AssignmentsState {
  fetching: boolean;
  favorites: string[];
  archived: string[];
  items: Assignment[];
  error?: FailReason | null;
  pendingAssignmentData?: {
    data: string;
    mimeType: string;
  } | null;
}

export type File = Pick<
  IFile,
  | 'id'
  | 'title'
  | 'description'
  | 'category'
  | 'size'
  | 'fileType'
  | 'markedImportant'
  | 'isNew'
  | 'uploadTime'
  | 'downloadUrl'
> &
  CourseExtraInfo;

export interface FilesState {
  fetching: boolean;
  favorites: string[];
  archived: string[];
  items: File[];
  error?: FailReason | null;
}

export interface UserState {
  name: string | null;
  department: string | null;
  email: string | null;
  phone: string | null;
}

export interface SemestersState {
  fetching: boolean;
  items: string[];
  current: string | null;
  error?: FailReason | null;
}

export interface AppState {
  auth: AuthState;
  settings: SettingsState;
  courses: CoursesState;
  notices: NoticeState;
  assignments: AssignmentsState;
  files: FilesState;
  user: UserState;
  semesters: SemestersState;
}

export interface PersistAppState extends AppState {
  _persist?: any;
}
