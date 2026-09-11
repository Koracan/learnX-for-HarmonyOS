# React Native learnOH — Factual Inventory (spec input for the ArkTS rewrite)

Source: `reference/learnOH-old` (symlink → `D:\Koracan\source\harmony\learnOH-old`), read-only. All facts from that tree. `UNKNOWN` = not determinable from source.

## 1. Navigation graph

**Library:** `@react-navigation` v7 (`native` 7.1.6, `native-stack` ^7.2.0, stack via `@react-native-ohos/stack` 7.2.11-rc.1, `bottom-tabs` 7.3.10) + `react-native-safe-area-context`; `enableScreens(false)`. All navigators are declared inline in `src/App.tsx`; param types in `src/screens/types.ts`.

| Navigator (kind) | Parent | Screens (params) |
|---|---|---|
| RootNavigator (native-stack) | root | MainTab, CourseXStack, SearchStack, AssignmentSubmissionStack, LoginStack — Main vs Login branch mounted per `showMain` |
| LoginNavigator (stack) | Root | Login (—); SSO {username,password} |
| MainNavigator (bottom-tabs) | Root→MainTab | NoticeStack, AssignmentStack, FileStack, CourseStack, SettingsStack (icons notifications/event/folder/apps/settings) |
| NoticeStackNavigator | tab | Notices; NoticeDetail (Notice&Extra); FileDetail (File&Extra) |
| AssignmentStackNavigator | tab | Assignments; AssignmentDetail; FileDetail; AssignmentSubmission |
| FileStackNavigator | tab | Files; FileDetail |
| CourseStackNavigator | tab | Courses; CourseDetail (Course&Extra); NoticeDetail; AssignmentDetail; FileDetail; AssignmentSubmission |
| SettingsStackNavigator | tab | Settings; ImmersiveSettings, SemesterSelection, FileSettings, About, Help, CalendarEvent*, CourseInformationSharing* (all Extra; *render Empty) |
| CourseXNavigator | Root | CourseX {id}|undefined → Empty (placeholder, unreachable from UI) |
| SearchNavigator | Root | Search {query}|undefined; NoticeDetail; AssignmentDetail; FileDetail |
| AssignmentSubmissionNavigator | Root | AssignmentSubmission (typed Assignment only) |
| DetailNavigator (stack) | second NavigationContainer under NavigationIndependentTree | EmptyDetail; NoticeDetail; AssignmentDetail; AssignmentSubmission; FileDetail; CourseDetail; + all SettingsStack detail routes |

`ExtraParams = {disableAnimation?: boolean}`. Detail headers derive title/subtitle from params (CourseDetail name+teacherName; FileDetail title; Notice/Assignment courseName+courseTeacherName||publisher). Non-settings lists show a header-right button → SearchStack. `CardStyleInterpolators.forHorizontalIOS`; `gestureEnabled:false` only on the three Root children.

**Tablet/desktop**
- `showMain = !auth.error && username && password && fingerPrint && auth.loggedIn`.
- `showDetail = showMain && effectiveWidth >= 750 && isLandscape`; width from the root `View` `onLayout` else `max(windowWidth, safeAreaFrame.width)`.
- `SplitViewProvider` renders master | Divider | detail when `splitEnabled`, else master only; master width is fixed at 393 (`Numbers`). `showMaster` is toggled by FileDetail's fullscreen header button.
- Entering split mode: if the master stack is on a detail route, after 100 ms it is navigated onto the detail container with identical params and master `goBack()`s past consecutive detail routes.
- `useDetailNavigator.ts` exposes `SplitViewContext.detailNavigationContainerRef`; Settings/Courses/Notices/Assignments/Files/AssignmentDetail push right when non-null, else `navigation.push`.
- `constants/DeviceInfo.ts` caches `isTablet/model/buildNo/systemVersion`; only `buildNo()` is used (About.tsx). `isTablet()` is referenced nowhere.
- `ImmersiveModeController` calls `Immersive.setImmersive(settings.immersiveMode)`; header top-inset fallback disabled when `immersiveMode && !immersiveAvoidFrontCamera`.
- Back handler at root with `!canGoBack()` → native `LearnOHDataProcessor.moveToBackground()`, consumes. AppState `active` → `resetLoading()` + re-login when >10 min idle or logged out; `background/inactive` records the time. First auto-login attempt after an 800 ms delay.

## 2. Screen inventory

| Screen | Purpose | Redux slices / actions | LOC |
|---|---|---|---|
| Login | Credentials; routes to SSO or mock | auth.loggingIn; setSetting('graduate'), setSSOInProgress, setMockStore | 152 |
| SSO | Auth WebView; captures fingerprint form | login, setSSOInProgress | 107 |
| Notices | Notice list + filters | notices, courses, settings.tabFilterSelections; getAllNoticesForCourses | 68 |
| NoticeDetail | Notice HTML + attachment link | — (route params) | 143 |
| Assignments | Assignment list + filters | assignments, courses; getAllAssignmentsForCourses | 70 |
| AssignmentDetail | Description/grade/answer/attachments | — (route params) | 401 |
| AssignmentSubmission | Submit text/file/photo | assignments.pendingAssignmentData; setPendingAssignmentData, getAssignmentsForCourse, submitAssignment | 475 |
| Files | File list + filters | files, courses; getAllFilesForCourses | 69 |
| FileDetail | Download, preview PDF/image, share, open | settings (via helpers/fs) | 331 |
| Courses | Courses of current semester | courses, semesters; getCoursesForSemester, getCurrentSemester | 62 |
| CourseDetail | Per-course notices/assignments/files | notices, assignments, files, courses.names; getNotices/getAssignments/getFilesForCourse | 221 |
| Search | Fuzzy search across three domains | notices, assignments, files; useSearch | 157 |
| Settings | Profile, logout, sub-page + privacy links | user, auth.username; clearStore | 133 |
| SemesterSelection | Semester picker + refresh | semesters; getAllSemesters, getCurrentSemester, setCurrentSemester | 89 |
| FileSettings | Dir/name prefs, clear cache | settings.fileUseDocumentDir/fileOmitCourseName; setSetting, removeFileDir | 121 |
| ImmersiveSettings | Immersive toggles | settings.immersiveMode/immersiveAvoidFrontCamera; setSetting | 74 |
| About / Help | Version+build / static text | package.json, DeviceInfo.buildNo / none | 105 / 64 |

Notices, Assignments, Files, Courses and Search all render through `components/FilterList.tsx` and read `data/selectors/filteredData.ts`.

## 3. State model

Store: `configureStore` over `persistReducer(rootPersistConfig, rootReducer)`, thunk middleware, `serializableCheck` ignoring redux-persist actions.

| Domain | State fields | Actions / thunks | Side effects |
|---|---|---|---|
| auth | username, password, fingerPrint, fingerGenPrint, fingerGenPrint3, loggingIn, ssoInProgress, loggedIn, error | `login({username,password,fingerPrint,fingerGenPrint,fingerGenPrint3,reset})`, `loginWithOfflineMode()`, `setSSOInProgress` | network (thu-learn-lib login), cookie reset, `retry` (3 tries, 1000·2^(3−n) ms + <100 ms jitter), then `getUserInfo()` |
| user | every `UserInfo` key, nullable (init name, department) | `getUserInfo()` | network `getUserInfo(CourseType.STUDENT)` |
| semesters | fetching, items:string[], current:string\|null, error | `getAllSemesters`, `getCurrentSemester`, `setCurrentSemester` | network `getSemesterIdList()` (sorted, reversed); `getCurrentSemester` also sets `current` when unset |
| courses | fetching, hidden:string[], items:Course[], names{id:{name,teacherName}}, order:string[], error | `getCoursesForSemester(id)`, `setCourses`, `setHideCourse`, `setCourseOrder` | network `getCourseList(id, STUDENT, lang)`; results tagged with semesterId; dispatch deferred through `InteractionManager.runAfterInteractions`; no-op for mock user |
| notices | fetching, favorites[], archived[], items:Notice[], error | `getNoticesForCourse`, `getAllNoticesForCourses`, `setFavNotice`, `setArchiveNotices` | per-course `getNotificationList`; bulk: native fetch(cookie+CSRF) → native `processNotices(raw, courseNamesJson)` → JSON.parse; re-auth on `'[]'`; sort publishTime desc, then id desc |
| assignments | + pendingAssignmentData:{data,mimeType}\|null | `getAssignmentsForCourse`, `getAllAssignmentsForCourses`, `setFavAssignment`, `setArchiveAssignments`, `setPendingAssignmentData` | same native pipeline; order = upcoming deadlines then past; heavy `[Performance]` logging; pendingAssignmentData carries a share-intent payload |
| files | fetching, favorites[], archived[], items:File[], error | `getFilesForCourse`, `getAllFilesForCourses`, `setFavFile`, `setArchiveFiles` | same native pipeline; sort uploadTime desc, then id desc |
| settings | assignmentCalendarSync, calendarEventLength?, assignmentReminderSync, assignmentCalendarId?, assignmentReminderId?, courseCalendarId?, syncedCalendarAssignments{}, syncedReminderAssignments{}, tabFilterSelections{notice,assignment,file,course}, alarms{5 booleans + 3 offsets}, graduate, immersiveMode, immersiveAvoidFrontCamera, fileUseDocumentDir, fileOmitCourseName, newUpdate, courseInformationSharing, courseInformationSharingBadgeShown, lastShowChangelogVersion, openFileAfterDownload, courseEventOmitLocation | `setSetting(key,value)` (shallow-merges object values), `setEventIdForAssignment`, `removeEventIdForAssignment`, `clearEventIds` | none in-tree — calendar/reminder fields are only stored; no calendar API call exists here (UNKNOWN whether a native module consumes them) |
| root | — | `resetLoading()`, `clearStore()`, `setMockStore()` | clearStore = clear action + `persistor.purge()` + `persistor.persist()`; resetLoading zeroes all `fetching/error`; mock guard drops every action outside a fixed whitelist while `username === DUMMY_USERNAME` |

## 4. Persistence

| What | Store | Key / config |
|---|---|---|
| root | AsyncStorage | key `root`, blacklists every slice → only `_persist` is written |
| auth | `react-native-secure-key-store` (helpers/secureStorage.ts) | key `auth`, whitelist the 5 credential fields |
| settings | AsyncStorage | key `settings`, blacklist `newUpdate` |
| semesters | AsyncStorage | key `semesters`, whitelist items, current |
| courses | AsyncStorage | key `courses`, whitelist items, names, order, hidden |
| notices / assignments / files | AsyncStorage | keys `notices`/`assignments`/`files`, whitelist favorites, archived, items |
| user | AsyncStorage | key `user`, no whitelist |

No `keyPrefix` is configured, so redux-persist's default `persist:` prefix applies (`persist:settings`, `persist:courses`, …); SecureStorage is handed the same generated key string. `stateReconciler: autoMergeLevel2`; `PersistGate` shows `Splash` while rehydrating.

Files: root dir `{DocumentDirectoryPath | CachesDirectoryPath}/learnX-files` chosen by `settings.fileUseDocumentDir`; per-file `…/{courseName}/{fileId}`; name `{courseName}-{title}.{fileType}` or `{title}.{fileType}` when `fileOmitCourseName`; clear-cache = `fs.unlink` on the root dir. Cookies live in the platform cookie store: cleared via `clearAll(true)` plus an empty `JSESSIONID` on `id.tsinghua.edu.cn`. Download workaround: HarmonyOS returns `bytesWritten === 0`, so success is judged by `fs.stat` size, and files <5000 bytes containing `<html`/`location.href` are treated as expired-session pages and deleted.

## 5. Component inventory

| Role | Components | Underlying libs |
|---|---|---|
| List primitives | `FlatList` (RN FlatList + `useBottomTabBarHeight`), `ScrollView` | react-native, bottom-tabs |
| Layout helpers | `SafeArea`, `SplitView`, `HeaderTitle`, `CardWrapper` (swipe actions) | safe-area-context, paper `Divider`, **gesture-handler** `Swipeable`/`RectButton` |
| Cards | `NoticeCard`, `AssignmentCard`, `FileCard`, `CourseCard` | paper Text/Title/Subheading/Caption/useTheme, MaterialIcons + MaterialCommunityIcons, dayjs |
| List chrome | `FilterList` (generic filtered list; fav/archive/hide swipe actions), `Filter` (animated panel + `FilterSelection` union), `Skeleton`, `Empty`, `Splash` | **reanimated** `useSharedValue`/`useAnimatedStyle`/`withTiming`/`Easing` in Filter; RN `Animated` in Skeleton and CardWrapper |
| Inputs/buttons | `TableCell` (row: arrow/switch/none, icon, avatar, optional TextInput), `TextButton`, `IconButton`, `Touchable` | paper |
| Feedback | `Toast` (context + paper `Snackbar`), `Skeleton` | paper |
| Web/media | `AutoHeightWebView` | **react-native-webview** + cookie manager; **react-native-pdf** in FileDetail only |

## 6. Cross-cutting helpers

| File | Purpose | Platform capability |
|---|---|---|
| `helpers/fs.ts` (226) | formatSize, dir resolution, downloadFile (progress, cookie+CSRF header, HTML-page detection), openFile, shareFile, removeFileDir, getExtension/stripExtension | file IO, HTTP download, file viewer, share sheet, cookies |
| `helpers/html.ts` (136) | `removeTags` (he decode + tag strip), `getWebViewTemplate` (inlines KaTeX + DarkReader + a script rewriting `href`/`src` with CSRF), `canRenderInWebview`, `needWhiteBackground` | HTML entity parsing, WebView |
| `helpers/secureStorage.ts` (57) | redux-persist adapter over secure key store; 404/not-found → null | secure key store |
| `helpers/i18n.ts` (57) | `getLocale`, `isLocaleChinese`, synchronous `t(key)` from bundled en/zh maps, grade-level→key map | device locale; no i18n framework |
| `helpers/parse.ts` (31) | `getSemesterTextFromId` (`YYYY-YYYY-N` → 学年/学期 label), `serializeError` | none |
| `helpers/reorder.ts` (22) | `sortByOrder(items, orderIds)`; unknown ids appended | none |
| `helpers/retry.ts` (22) | Promise retry, exponential backoff + jitter | timers |
| `helpers/fingerprint.ts` (30) | UUID v4 from react-native-securerandom — **dead code, imported nowhere** | crypto RNG |
| `helpers/env.ts` (10) | build-time `.env` via `preval` + `dotenv` | build tooling |
| `helpers/preval/sso.js` (118) | injected SSO-page script: XHR intercept, field fill, jQuery submit hook, postMessage bridge | WebView JS injection |
| `hooks/useDetailNavigator.ts` (13) | detail-pane navigation ref from context | — |
| `hooks/useNavigationAnimation.ts` (20) | sets `animation:'none'` from route param `disableAnimation` | — |
| `hooks/useSearch.ts` (117) | fuse.js search over the three domains with weighted keys, plus a manual exact title/courseName merge | — |
| `hooks/useToast.ts` (12) | ToastContext accessor | — |

## 7. External interface

- `constants/Urls.ts`: `learn = https://learn.tsinghua.edu.cn`, `id = https://id.tsinghua.edu.cn` — the only base URLs.
- Hardcoded in SSO.tsx: login form `https://id.tsinghua.edu.cn/do/off/ui/auth/login/form/bb5df85216504820be7bba2b0ae1535b/0`; success sentinel `https://learn.tsinghua.edu.cn/f/j_spring_security_thauth_roaming_entry`.
- `data/source.ts`: submit `POST {learn}/b/wlxt/kczy/zy/student/tjzy` (`xszyid, zynr, isDeleted`) via native `LearnOHDataProcessor.post` (cookie+CSRF+file path+mime+requestId); upload progress via `DeviceEventEmitter` event `LearnOHUploadProgress`. Bulk fetch/parse uses native `react-native-learn-oh-data-processor`; `thu-learn-lib`'s `Learn2018Helper` handles login, CSRF, semester/course lists, user info and per-course scraping. Requests carry a desktop Chrome UA; `addCSRF` appends `_csrf` for `*.tsinghua.edu.cn`. A response equal to `'[]'` triggers one shared `loginWithFingerPrint()` (deduped) plus a retry.
- **SSO flow**: Login → confirm → `setSSOInProgress(true)` + `clearLoginCookies()` → `navigate('SSO',{username,password})`. The WebView loads the id form with `Cookie: ''` and injects `sso.js` with username, password, a per-mount `Math.random` UUID v4 `fingerPrint`, and `deviceName` = `HarmonyOS,learnOH/{version}`. The script fills `#i_user`/`#i_pass` read-only, forces `fingerPrint`/`singleLogin` on submit, intercepts the `saveFinger` XHR (fingerprint, deviceName, radioVal=是) and posts `JQUERY_SUBMIT` with the form body. From `formId === 'theform'` it stores fingerPrint/fingerGenPrint/fingerGenPrint3; on reaching the roaming URL it dispatches `login({...formData, reset:true})`, clears the flag, `goBack()`s and cancels the load. `reset:true` rebuilds the data source.
- **Mock mode** is a runtime credential path, not a build switch. `helpers/env.ts` bakes `.env` (`DUMMY_USERNAME=guest`, `DUMMY_PASSWORD=guest`). Login.tsx matches those exact strings and dispatches `setMockStore()`, whose reducer branch returns `data/mock.ts` (723 lines of `PersistAppState`: auth marked logged-in as guest, user 测试学生/电子系, plus sample courses/notices/assignments/files) as the whole state. Afterwards the root reducer ignores every action outside a whitelist (fav/archive/pending-data/hide-course/course-order/current-semester/setting), `getCoursesForSemester` no-ops, fs.ts skips re-login, and Settings hides the immersive entry.
- Other outbound URLs: privacy policy (Settings) `https://agreement-drcn.hispace.dbankcloud.cn/index.html?lang=zh&agreementId=1864655084378428992`; KaTeX font CDN `https://fastly.jsdelivr.net/npm/katex@{version}/dist/fonts/`. About/Help link targets: UNKNOWN (not read).

## 8. Top 10 porting risks

| # | Module | Reason |
|---|---|---|
| 1 | `data/source.ts` + native `react-native-learn-oh-data-processor` | Bulk fetch, HTML/JSON parsing and multipart submit+progress live in a native TurboModule with no ArkTS equivalent; its JSON contract and re-auth-on-`'[]'` behaviour must be rebuilt |
| 2 | `screens/SSO.tsx` + `helpers/preval/sso.js` | Relies on WebView JS injection, jQuery-internal hooking, XHR monkey-patching and a URL sentinel; ArkUI Web differs substantially |
| 3 | `thu-learn-lib` (GitHub fork) | Third-party lib for login, CSRF, cookies and HTML scraping of semesters/courses/notices/homework/files; no ohpm package |
| 4 | `helpers/fs.ts` + `FileDetail.tsx` | Cookie+CSRF downloads, the `bytesWritten=0` stat workaround, login-page detection, viewer/share/open-with all need HarmonyOS file and HTTP APIs |
| 5 | `App.tsx` (978) | One file owns 12 navigators, theming, split-view bootstrap, the dual-NavigationContainer trick, re-auth, immersive and back-to-background |
| 6 | `SplitView.tsx` + `useDetailNavigator` + width/orientation logic | Cross-navigator route migration via timers and `goBack()` loops; must be redesigned for ArkUI navigation, not transliterated |
| 7 | `data/reducers/root.ts` + `data/mock.ts` | Full-state replacement plus a global mock action guard and cross-slice resets, tied to PersistPartial/autoMergeLevel2 assumptions |
| 8 | `data/store.ts` / `reducers/root.ts` / `helpers/secureStorage.ts` | Eight differing persist configs across three storage backends, default `persist:` prefix, purge-on-logout ordering |
| 9 | `helpers/html.ts` + `AutoHeightWebView.tsx` | Inlined DarkReader/KaTeX bundles, CSS font-face rewriting, CSRF rewriting of links, cookie mirroring, postMessage height measurement |
| 10 | `AssignmentSubmission.tsx` (475) + `submitAssignment` | Document picker, image library, custom filename, remove-attachment, progress and native POST — largest interaction surface, fewest ArkTS analogues |

Secondary risk: `AssignmentDetail.tsx` (401 dense read-only lines), `hooks/useSearch.ts` (fuse.js scoring + manual merge hack), `constants/DeviceInfo.ts` (react-native-device-info), calendar/reminder settings fields with no in-tree implementation.