# i18n 键名映射表

**由 `scripts/generate-i18n-resources.mjs` 自动生成，不要手工编辑。**

来源（只读）：`reference/learnOH-old/src/assets/translations/{zh,en}.ts`。

## 规则

- 参考键（camelCase）→ 资源名 = `loh_` + camelCase→snake_case。
- 资源值插值：参考字典若用 `{N}`，资源里写成 HarmonyOS 位置占位符 `%(N+1)$s`。
- `base` 与 `zh_CN` 内容相同（中文是默认回退），`en_US` 是英文。
- 取串：UI 用 `$r('app.string.<资源名>')`；逻辑层用 `core/i18n` 的 `t()`（`ResourceManager.getStringByNameSync`）。

## 统计

| 类别 | 数量 | 命名空间 |
| --- | --- | --- |
| 参考实现迁入 | 180 | `loh_` |
| 本工程新增（学期季节词） | 8 | `loh_` |
| 本工程新增（原生重写 UI 文案） | 119 | `ui_` |
| 合计 | 307 | |

## 参考实现迁入键（180）

| # | 参考键 | 资源名 | 占位符 | 中文 | 英文 |
| --- | --- | --- | --- | --- | --- |
| 1 | `back` | `loh_back` | - | 返回 | Back |
| 2 | `notices` | `loh_notices` | - | 通知 | Notices |
| 3 | `assignments` | `loh_assignments` | - | 作业 | Assignments |
| 4 | `files` | `loh_files` | - | 文件 | Files |
| 5 | `courses` | `loh_courses` | - | 课程 | Courses |
| 6 | `calendarsAndReminders` | `loh_calendars_and_reminders` | - | 日历与提醒事项 | Calendars & Reminders |
| 7 | `semesterSelection` | `loh_semester_selection` | - | 学期切换 | Semester Selection |
| 8 | `fileSettings` | `loh_file_settings` | - | 文件 | Files |
| 9 | `privacyPolicy` | `loh_privacy_policy` | - | 隐私政策 | Privacy Policy |
| 10 | `helpAndFeedback` | `loh_help_and_feedback` | - | 帮助与反馈 | Help & Feedbacks |
| 11 | `about` | `loh_about` | - | 关于 | About |
| 12 | `changelog` | `loh_changelog` | - | 更新日志 | Changelog |
| 13 | `settings` | `loh_settings` | - | 设置 | Settings |
| 14 | `search` | `loh_search` | - | 搜索 | Search |
| 15 | `submit` | `loh_submit` | - | 提交 | Submit |
| 16 | `submitted` | `loh_submitted` | - | 已提交 | Submitted |
| 17 | `assignmentSubmission` | `loh_assignment_submission` | - | 作业提交 | Assignment Submission |
| 18 | `loginFailed` | `loh_login_failed` | - | 登录失败，请检查网络连接并确保用户电子身份服务系统的登录依旧有效 | Login failed. Please check your network and ensure that the login to the Electronic ID Service System is still valid |
| 19 | `versionInformation` | `loh_version_information` | - | 版本信息 | Version |
| 20 | `opensourceAt` | `loh_opensource_at` | - | 本项目开源于 | Opensource at |
| 21 | `specialThanks` | `loh_special_thanks` | - | 特别感谢 | Special Thanks |
| 22 | `harryChen` | `loh_harry_chen` | - | Harry Chen 的 | Harry Chen's |
| 23 | `ruiYing` | `loh_rui_ying` | - | Rui Ying 的 | Rui Ying's |
| 24 | `yayuXiao` | `loh_yayu_xiao` | - | Yayu Xiao 制作的 App icon | Yayu Xiao's App icon |
| 25 | `opensourceDependencies` | `loh_opensource_dependencies` | - | 开源依赖 | Opensource Dependencies |
| 26 | `noAssignmentDescription` | `loh_no_assignment_description` | - | 无作业描述 | No assignment description |
| 27 | `assignmentSyncNoCalendarPermission` | `loh_assignment_sync_no_calendar_permission` | - | 作业同步失败：请给予 App 日历的完全访问权限；如果您已经授予该权限，请尝试重启 App | Assignment Sync failed. Please grant the App full access to calendars, or try restarting the App if you have already done so. |
| 28 | `assignmentSyncNoReminderPermission` | `loh_assignment_sync_no_reminder_permission` | - | 作业同步失败：请给予 App 提醒事项访问权限；如果您已经授予该权限，请尝试重启 App | Assignment Sync failed. Please grant the App access to reminders, or try restarting the App if you have already done so. |
| 29 | `assignmentSyncFailed` | `loh_assignment_sync_failed` | - | 作业同步失败： | Assignment Sync failed:  |
| 30 | `filePickFailed` | `loh_file_pick_failed` | - | 选取文件失败 | Failed to pick the file |
| 31 | `assignmentSubmissionSucceeded` | `loh_assignment_submission_succeeded` | - | 作业提交成功 | Successfully submitted the assignment |
| 32 | `assignmentSubmissionFailed` | `loh_assignment_submission_failed` | - | 作业提交失败 | Failed to submit the assignment |
| 33 | `assignmentPastDeadline` | `loh_assignment_past_deadline` | - | 作业已截止 | Assignment has passed the deadline |
| 34 | `submitAssignment` | `loh_submit_assignment` | - | 提交作业 | Submit Assignment |
| 35 | `submitAssignmentConfirmation` | `loh_submit_assignment_confirmation` | - | 确定提交作业？ | Do you want to submit the assignment? |
| 36 | `cancel` | `loh_cancel` | - | 取消 | Cancel |
| 37 | `ok` | `loh_ok` | - | 确定 | Ok |
| 38 | `assignmentSubmissionFilenamePlaceholder` | `loh_assignment_submission_filename_placeholder` | - | 自定义附件名（可选） | (Optional) Change attachment name... |
| 39 | `assignmentSubmissionContentPlaceholder` | `loh_assignment_submission_content_placeholder` | - | 作业内容（可选） | (Optional) Enter assignment content... |
| 40 | `undoRemoveUploadedAttachment` | `loh_undo_remove_uploaded_attachment` | - | 撤销移除 | Undo removal |
| 41 | `removeUploadedAttachment` | `loh_remove_uploaded_attachment` | - | 移除已上传的附件 | Remove uploaded attachment |
| 42 | `removePickedAttachment` | `loh_remove_picked_attachment` | - | 移除已选择的附件 | Remove picked attachment |
| 43 | `reUploadAttachment` | `loh_re_upload_attachment` | - | 选择新附件 | Pick new attachment |
| 44 | `overwriteAttachment` | `loh_overwrite_attachment` | - | 覆盖已上传的附件 | Overwrite uploaded attachment |
| 45 | `pickAttachment` | `loh_pick_attachment` | - | 选择附件 | Pick attachment |
| 46 | `courseScheduleSyncSucceeded` | `loh_course_schedule_sync_succeeded` | - | 课表同步成功 | Successfully synced course schedule |
| 47 | `courseScheduleSyncNoCalendarPermission` | `loh_course_schedule_sync_no_calendar_permission` | - | 课表同步失败：请给予 App 日历的完全访问权限；如果您已经授予该权限，请尝试重启 App | Course Schedule Sync failed. Please grant the App full access to calendars, or try restarting the App if you have already done so. |
| 48 | `courseScheduleSyncNoReminderPermission` | `loh_course_schedule_sync_no_reminder_permission` | - | 课表同步失败：请给予 App 提醒事项访问权限；如果您已经授予该权限，请尝试重启 App | Course Schedule Sync failed. Please grant the App access to reminders, or try restarting the App if you have already done so. |
| 49 | `courseScheduleSyncRepetitiveError` | `loh_course_schedule_sync_repetitive_error` | - | 课表同步失败，请重试。请确保已连接至校园网；如果问题持续存在，请尝试缩小或更改同步的日期范围 | Course Schedule Sync failed. Please try again. Make sure you are connected to the campus network. Try narrowing down or change the sync date range if the issue persists. |
| 50 | `courseScheduleSyncNoCourse` | `loh_course_schedule_sync_no_course` | - | 无课表可供同步，请检查网络学堂网页版在此日期范围内是否存在上课日程 | No course schedule to sync. Check Web Learning to see if there exists any schedule in the selected range. |
| 51 | `configureCalendarAndReminder` | `loh_configure_calendar_and_reminder` | - | 日历与提醒事项权限设置 | Calendars & Reminders Permission Settings |
| 52 | `deleteSyncedCalendarsAndReminders` | `loh_delete_synced_calendars_and_reminders` | - | 删除已同步的日历与提醒事项 | Delete Synced Calendars & Reminders |
| 53 | `deleteSyncedCalendarsAndRemindersConfirmation` | `loh_delete_synced_calendars_and_reminders_confirmation` | - | 确定删除已同步的日历与提醒事项？该操作不可撤销。 | Do you want to delete synced calendars and reminders? This cannot be undone. |
| 54 | `deleteSucceeded` | `loh_delete_succeeded` | - | 删除成功 | Successfully deleted |
| 55 | `deleteFailedNoCalendarPermission` | `loh_delete_failed_no_calendar_permission` | - | 删除失败：请给予 App 日历的完全访问权限；如果您已经授予该权限，请尝试重启 App | Failed to delete. Please grant the App full access to calendars, or try restarting the App if you have already done so. |
| 56 | `deleteFailedNoReminderPermission` | `loh_delete_failed_no_reminder_permission` | - | 删除失败：请给予 App 提醒事项访问权限；如果您已经授予该权限，请尝试重启 App | Failed to delete. Please grant the App access to reminders, or try restarting the App if you have already done so. |
| 57 | `deleteFailed` | `loh_delete_failed` | - | 删除失败： | Failed to delete:  |
| 58 | `graduate` | `loh_graduate` | - | 研究生 | Graduate |
| 59 | `syncCourseSchedule` | `loh_sync_course_schedule` | - | 同步课表 | Sync Course Schedule |
| 60 | `classAlarm` | `loh_class_alarm` | - | 上课提醒 | Class Alert |
| 61 | `classAlarmBefore` | `loh_class_alarm_before` | - | 提前提醒（分钟） | Before Class (in mins) |
| 62 | `assignmentCalendarSync` | `loh_assignment_calendar_sync` | - | 作业日历同步 | Assignment Calendar Sync |
| 63 | `calendarEventLength` | `loh_calendar_event_length` | - | 日程长度（分钟） | Event Length (in mins) |
| 64 | `assignmentCalendarAlarm` | `loh_assignment_calendar_alarm` | - | 日历提醒 | Calendar Alert |
| 65 | `assignmentCalendarAlarmOffset` | `loh_assignment_calendar_alarm_offset` | - | 提前提醒（分钟） | Alert Before Deadline (in mins) |
| 66 | `assignmentCalendarSecondAlarm` | `loh_assignment_calendar_second_alarm` | - | 日历第二次提醒 | Second Calendar Alert |
| 67 | `assignmentCalendarSecondAlarmOffset` | `loh_assignment_calendar_second_alarm_offset` | - | 第二次提前提醒（分钟） | Second Alert Before Deadline (in mins) |
| 68 | `assignmentCalendarNoAlarmIfComplete` | `loh_assignment_calendar_no_alarm_if_complete` | - | 已完成的作业不提醒 | Disable Alerts for Completed Assignments |
| 69 | `assignmentReminderSync` | `loh_assignment_reminder_sync` | - | 作业提醒事项同步 | Assignment Reminder Sync |
| 70 | `assignmentReminderAlarm` | `loh_assignment_reminder_alarm` | - | 提醒事项截止时间提前 | Reminder Early Deadline |
| 71 | `assignmentReminderAlarmOffset` | `loh_assignment_reminder_alarm_offset` | - | 截止时间提前（分钟） | Move Deadline Forward (in mins) |
| 72 | `assignmentSyncDescription` | `loh_assignment_sync_description` | - | 启用后，作业会在刷新时自动同步；已屏蔽课程的作业或已归档、已过期的作业不会被同步；请在更改设置后刷新作业以应用更改。 | If enabled, assignments will be synced automatically when refreshed. Assignments that are hidden, archived or have passed the due date will not be synced. Please refresh assignments after any setting change. |
| 73 | `clearFileCache` | `loh_clear_file_cache` | - | 清空文件缓存 | Clear File Cache |
| 74 | `clearFileCacheConfirmation` | `loh_clear_file_cache_confirmation` | - | 确定清空文件缓存？该操作不可撤销。 | Do you want to clear file cache? This cannot be undone. |
| 75 | `clearFileCacheSucceeded` | `loh_clear_file_cache_succeeded` | - | 清空文件缓存成功 | Successfully cleared file cache |
| 76 | `clearFileCacheFailed` | `loh_clear_file_cache_failed` | - | 清空文件缓存失败： | Failed to clear file cache |
| 77 | `fileUseDocumentDir` | `loh_file_use_document_dir` | - | 保存打开的文件到“文档” | Save Downloaded Files to Documents |
| 78 | `fileOmitCourseName` | `loh_file_omit_course_name` | - | 文件名不包含课程名 | Omit Course Name in Filenames |
| 79 | `fileDownloadFailed` | `loh_file_download_failed` | - | 文件下载失败，请重试。 | Failed to download the file. Please retry. |
| 80 | `openFileFailed` | `loh_open_file_failed` | - | 文件打开失败。请重新下载文件或确保存在可打开此文件类型的应用。 | Failed to open the file. Re-download the file or make sure there is some app on system that can handle the file type. |
| 81 | `share` | `loh_share` | - | 分享 | Share |
| 82 | `open` | `loh_open` | - | 打开 | Open |
| 83 | `email` | `loh_email` | - | 邮件 | Email |
| 84 | `missingUsername` | `loh_missing_username` | - | 请输入用户名或学号 | Please enter your username or ID |
| 85 | `missingPassword` | `loh_missing_password` | - | 请输入密码 | Please enter your password |
| 86 | `unknownError` | `loh_unknown_error` | - | 未知错误： | Unknown error:  |
| 87 | `usernameOrId` | `loh_username_or_id` | - | 用户名 / 学号 | Username / ID |
| 88 | `password` | `loh_password` | - | 密码 | Password |
| 89 | `securityNote` | `loh_security_note` | - | 您的用户信息仅会被保存在本地，并由操作系统安全地加密 | Your credential will only be stored locally and secured by the system |
| 90 | `login` | `loh_login` | - | 登录 | Login |
| 91 | `noNoticeContent` | `loh_no_notice_content` | - | 无通知内容 | No notice content |
| 92 | `searchPlaceholder` | `loh_search_placeholder` | - | 搜索通知、作业、文件…… | Notices, assignments & files... |
| 93 | `logout` | `loh_logout` | - | 退出登录 | Logout |
| 94 | `logoutConfirmation` | `loh_logout_confirmation` | - | 确定退出登录？该操作会清除你当前的所有设置。 | Are you sure to logout? This will clear all of your settings. |
| 95 | `foundNewVersion` | `loh_found_new_version` | - | 检测到新版本 | Found New Version |
| 96 | `unfinished` | `loh_unfinished` | - | 未完成 | unfinished |
| 97 | `finished` | `loh_finished` | - | 已完成 | finished |
| 98 | `all` | `loh_all` | - | 全部 | all |
| 99 | `unread` | `loh_unread` | - | 未读 | unread |
| 100 | `fav` | `loh_fav` | - | 收藏 | favorite |
| 101 | `archived` | `loh_archived` | - | 归档 | archived |
| 102 | `hidden` | `loh_hidden` | - | 屏蔽 | hidden |
| 103 | `empty` | `loh_empty` | - | 无内容 | No Content |
| 104 | `removeFromFav` | `loh_remove_from_fav` | - | 已从收藏移除 | Removed from Favorites |
| 105 | `addToFav` | `loh_add_to_fav` | - | 已添加到收藏 | Added to Favorites |
| 106 | `undoArchive` | `loh_undo_archive` | - | 已撤销归档 | Undo archiving |
| 107 | `archiveSucceeded` | `loh_archive_succeeded` | - | 已归档 | Archived |
| 108 | `undoHide` | `loh_undo_hide` | - | 已撤销屏蔽 | Undo hiding |
| 109 | `hideSucceeded` | `loh_hide_succeeded` | - | 已屏蔽 | Hidden |
| 110 | `courseInformationSharing` | `loh_course_information_sharing` | - | 课程信息共享计划 | Course Information Sharing |
| 111 | `joinCourseInformationSharing` | `loh_join_course_information_sharing` | - | 加入课程信息共享计划 | Enable Course Information Sharing |
| 112 | `joinCourseInformationSharingConfirmation` | `loh_join_course_information_sharing_confirmation` | - | 确定加入课程信息共享计划？当前学期的课程信息将会被自动上传；上传内容不包含任何个人信息。 | Do you want to enable Course Information Sharing? Information of courses of the current semester will be uploaded. Personal information will never be uploaded or shared. |
| 113 | `courseX` | `loh_course_x` | - | 课程信息共享计划 courseX | courseX |
| 114 | `courseInformation` | `loh_course_information` | - | 课程信息 | Course Information |
| 115 | `missingCalendarSource` | `loh_missing_calendar_source` | - | 不存在可写入的日历：请确保“日历”应用内存在 iCloud 日历目录或至少一个本地日历目录。 | Missing calendar source. Make sure you have an iCloud enabled calendar category or at least one local calendar category set up in the Calendar app. |
| 116 | `pushNotifications` | `loh_push_notifications` | - | 推送通知 | Push Notifications |
| 117 | `copyPushNotificationToken` | `loh_copy_push_notification_token` | - | 复制设备标识符 | Copy Device Token |
| 118 | `pushNotificationTokenDescription` | `loh_push_notification_token_description` | - | 使用此标识符，配合 learnX Companion 应用，您可以在此设备上接收推送通知。请勿分享此标识符给其他人。 | Use this token with the learnX Companion app to receive push notifications on this device. Don't share it with others. |
| 119 | `copied` | `loh_copied` | - | 已复制 | Copied |
| 120 | `configurePushNotifications` | `loh_configure_push_notifications` | - | 推送通知权限设置 | Push Notifications Permission Settings |
| 121 | `noPushNotificationsPermission` | `loh_no_push_notifications_permission` | - | 未授予推送通知权限 | No Push Notifications Permission |
| 122 | `learnXCompanionUsageGuide` | `loh_learn_xcompanion_usage_guide` | - | learnX Companion 使用指南 | learnX Companion Usage Guide |
| 123 | `noFileDescription` | `loh_no_file_description` | - | 无文件描述 | No file description |
| 124 | `githubRecommended` | `loh_github_recommended` | - | GitHub（推荐） | GitHub (Recommended) |
| 125 | `createNewGitHubIssue` | `loh_create_new_git_hub_issue` | - | 创建新的 GitHub Issue | Create New GitHub Issue |
| 126 | `emailNotRecommended` | `loh_email_not_recommended` | - | 邮箱 | Email |
| 127 | `issueTemplate` | `loh_issue_template` | - | 问题反馈与帮助 | Issue Template |
| 128 | `issueTemplateDescription` | `loh_issue_template_description` | - | 如通过邮件提交问题反馈或寻求帮助，请务必使用以下模板： | If you are submitting an issue or asking for help via email, please use the following template: |
| 129 | `issueTemplateContent` | `loh_issue_template_content` | - | \n    - 问题描述\n    - 复现步骤\n    - 已尝试的解决方案\n    - 截图\n    - App 版本\n    - 设备型号\n    - 系统版本\n    - 其他补充信息\n   | \n    - Issue Description\n    - Reproduction Steps\n    - Attempts to Fix\n    - Screenshots\n    - App Version\n    - Device Model\n    - OS Version\n    - Other Information\n   |
| 130 | `shareReceived` | `loh_share_received` | - | 您刚分享的内容已被接收，将在下次作业提交时自动选中 | The content you just shared has been received. It will be automatically chosen during the next assignment submission. |
| 131 | `shareError` | `loh_share_error` | - | 分享的内容接收失败，文件可能过大 | Failed to receive the shared content. The file size may be too large. |
| 132 | `sharedContentSelected` | `loh_shared_content_selected` | - | 您之前分享的内容已被自动选中作为作业附件 | The previously shared content has been automatically chosen as the attachment. |
| 133 | `noFileSize` | `loh_no_file_size` | - | 未知文件大小 | Unknown file size |
| 134 | `datePickerStartLabel` | `loh_date_picker_start_label` | - | 开始 | Start |
| 135 | `datePickerEndLabel` | `loh_date_picker_end_label` | - | 结束 | End |
| 136 | `datePickerSaveLabel` | `loh_date_picker_save_label` | - | 同步 | Sync |
| 137 | `datePickerLabel` | `loh_date_picker_label` | - | 选择同步范围 | Select Sync Range |
| 138 | `reviewed` | `loh_reviewed` | - | 已阅 | Reviewed |
| 139 | `good` | `loh_good` | - | 优秀 | Good |
| 140 | `exemptedCourse` | `loh_exempted_course` | - | 免课 | Exempted Course |
| 141 | `exempted` | `loh_exempted` | - | 免修 | Exempted |
| 142 | `pass` | `loh_pass` | - | 通过 | Pass |
| 143 | `fail` | `loh_fail` | - | 不通过 | Fail |
| 144 | `incomplete` | `loh_incomplete` | - | 缓考 | Incomplete |
| 145 | `openFileAfterDownload` | `loh_open_file_after_download` | - | 自动打开已下载的文件 | Open downloaded files automatically |
| 146 | `loggingIn` | `loh_logging_in` | - | 登录中…… | Logging in... |
| 147 | `archive` | `loh_archive` | - | 归档 | Archive |
| 148 | `restore` | `loh_restore` | - | 恢复 | Restore |
| 149 | `undo` | `loh_undo` | - | 撤销 | Undo |
| 150 | `reorder` | `loh_reorder` | - | 排序 | Reorder |
| 151 | `select` | `loh_select` | - | 选择 | Select |
| 152 | `checkAll` | `loh_check_all` | - | 全选/取消全选 | Check All Or None |
| 153 | `filter` | `loh_filter` | - | 过滤 | Filter |
| 154 | `refresh` | `loh_refresh` | - | 刷新 | Refresh |
| 155 | `dragToReorder` | `loh_drag_to_reorder` | - | 长按并拖动以排序 | Long press and drag to reorder |
| 156 | `documents` | `loh_documents` | - | 文件 | Files |
| 157 | `photos` | `loh_photos` | - | 照片 | Photos |
| 158 | `assignmentIndividualCompletion` | `loh_assignment_individual_completion` | - | 独立完成 | Complete Individually |
| 159 | `assignmentGroupCompletion` | `loh_assignment_group_completion` | - | 小组完成 | Complete as a Group |
| 160 | `assignmentOnlineSubmission` | `loh_assignment_online_submission` | - | 在线提交 | Submit Online |
| 161 | `assignmentOfflineSubmission` | `loh_assignment_offline_submission` | - | 线下提交 | Submit Offline |
| 162 | `becomeMaintainer` | `loh_become_maintainer` | - | 成为维护者 | Become a Maintainer |
| 163 | `maintainerDescription` | `loh_maintainer_description` | - | 你想成为 learnX 的维护者吗？让我们聊聊吧！要求有前端开发经验，最好是 React.js；有 React Native 经验者优先。请发送邮件至 | Do you want to become a maintainer of learnX? Let's talk! Experience in frontend development is required, preferably with React.js; experience with React Native is a plus. Send an email to |
| 164 | `anonymous` | `loh_anonymous` | - | 匿名 | Anonymous |
| 165 | `maintainers` | `loh_maintainers` | - | 维护者 | Maintainers |
| 166 | `offlineMode` | `loh_offline_mode` | - | 离线模式 | Offline Mode |
| 167 | `openFileDownloadDirectory` | `loh_open_file_download_directory` | - | 打开文件保存目录 | Open File Save Folder |
| 168 | `download` | `loh_download` | - | 下载 | Download |
| 169 | `downloadToDownloadsSucceeded` | `loh_download_to_downloads_succeeded` | - | 成功下载文件到“下载”文件夹 | Successfully downloaded the file to Downloads |
| 170 | `downloadToDownloadsFailed` | `loh_download_to_downloads_failed` | - | 下载文件到“下载”文件夹失败 | Failed to download the file to Downloads |
| 171 | `sso` | `loh_sso` | - | 清华大学用户电子身份服务系统 | Electronic ID Service System of Tsinghua University |
| 172 | `ssoNote` | `loh_sso_note` | - | 请在即将打开的网页中完成登录。如需更改网页中预填的账号或密码，请关闭网页，再在 learnX 登录界面重新输入正确的账号及密码。\n\n如果提示“信任浏览器数量已达到上限”，请在浏览器登录 https://id.tsinghua.edu.cn，前往账号设置-多因子认证-信任浏览器数量-维护，选择并删除其他设备。 | Please complete the login on the webpage that will open. If you need to change the pre-filled username or password, please close the webpage and re-enter the correct username and password on the learnX login screen.\n\nIf seeing an error on trusted browser limit, please log in to https://id.tsinghua.edu.cn in your browser, go to Settings - Two-factor Authentication - Number of trusted device browsers - Manage, and delete other devices. |
| 173 | `ssoFailed` | `loh_sso_failed` | - | 登录失败，请重试。 | Failed to complete the login process. Please try again. |
| 174 | `courseEventOmitLocation` | `loh_course_event_omit_location` | - | 不写入位置信息 | Omit Location |
| 175 | `restartRequired` | `loh_restart_required` | - | 需要重启 | Restart Required |
| 176 | `immersiveMode` | `loh_immersive_mode` | - | 沉浸式模式 | Immersive Mode |
| 177 | `avoidFrontCamera` | `loh_avoid_front_camera` | - | 避让前置摄像头 | Avoid Front Camera |
| 178 | `immersiveModeDescription` | `loh_immersive_mode_description` | - | 隐藏导航栏和状态栏，需要重启应用 | Hide the navigation bar and status bar. App restart required. |
| 179 | `avoidFrontCameraDescription` | `loh_avoid_front_camera_description` | - | 在上部留出空间以避让挖孔区域，需要重启应用 | Leave top space to avoid the front camera cutout. App restart required. |
| 180 | `pleaseRestartAppToApplyImmersive` | `loh_please_restart_app_to_apply_immersive` | - | 请重启应用以应用沉浸式模式设置。 | Please restart the app to apply immersive mode setting. |

## 本工程新增键（127）

| # | 类别 | 资源名 | 占位符 | 中文 | 英文 |
| --- | --- | --- | --- | --- | --- |
| 1 | local | `loh_fall` | - | 秋季学期 | Fall |
| 2 | local | `loh_spring` | - | 春季学期 | Spring |
| 3 | local | `loh_summer` | - | 夏季学期 | Summer |
| 4 | local | `loh_session_expired` | - | 登录状态已失效，需要重新验证。 | Your session has expired. Please sign in again to verify. |
| 5 | local | `loh_network_unavailable` | - | 网络不可用，请检查网络后重试。 | Network unavailable. Check your connection and try again. |
| 6 | local | `loh_retry` | - | 重试 | Retry |
| 7 | local | `loh_fullscreen` | - | 全屏 | Full screen |
| 8 | local | `loh_exit_fullscreen` | - | 退出全屏 | Exit full screen |
| 9 | ui | `ui_app_name` | - | learnOH | learnOH |
| 10 | ui | `ui_app_tagline` | - | HarmonyOS 原生重写 · foundation / 01 分层 + 日志 + 主题令牌 | Native HarmonyOS rewrite · foundation / 01 layering + logging + theme tokens |
| 11 | ui | `ui_self_check_card_title` | - | 自检 | Self-check |
| 12 | ui | `ui_system_color_mode` | - | 系统配色 | System color mode |
| 13 | ui | `ui_dark` | - | 深色 | Dark |
| 14 | ui | `ui_light` | - | 浅色 | Light |
| 15 | ui | `ui_color_tokens` | - | 颜色令牌 | Color tokens |
| 16 | ui | `ui_recent_log_count` | - | 最近日志条数 | Recent log records |
| 17 | ui | `ui_semester_parse_failed` | - | 解析失败 | Parse failed |
| 18 | ui | `ui_semester_parse` | - | domain.Semester 解析 | domain.Semester parse |
| 19 | ui | `ui_semester_compare` | - | domain.Semester 比较 | domain.Semester compare |
| 20 | ui | `ui_semester_later` | {0} | 较晚 = %1$s | later = %1$s |
| 21 | ui | `ui_reference_palette` | - | 参考实现调色板（Colors.ts） | Reference palette (Colors.ts) |
| 22 | ui | `ui_export_logs` | - | 导出日志为文本文件 | Export logs to a text file |
| 23 | ui | `ui_exported` | {0},{1} | 已导出 %1$s 条 / %2$s 字节 | Exported %1$s records / %2$s bytes |
| 24 | ui | `ui_export_failed` | {0} | 导出失败：%1$s | Export failed: %1$s |
| 25 | ui | `ui_locale_live_demo` | - | 语言切换（无需重启） | Language switch (no restart) |
| 26 | ui | `ui_switch_chinese` | - | 切到中文 | Switch to Chinese |
| 27 | ui | `ui_switch_english` | - | 切到英文 | Switch to English |
| 28 | ui | `ui_current_locale` | - | 当前语言 | Current locale |
| 29 | ui | `ui_relative_time_sample` | - | 相对时间示例 | Relative time sample |
| 30 | ui | `ui_date_time_sample` | - | 日期时间示例 | Date/time sample |
| 31 | ui | `ui_semester_sample` | - | 学期文案示例 | Semester text sample |
| 32 | ui | `ui_language` | - | 语言 | Language |
| 33 | ui | `ui_tab_notices` | - | 公告 | Notices |
| 34 | ui | `ui_tab_placeholder` | - | 该页面将在后续迭代中实现 | This page will be implemented in a later iteration |
| 35 | ui | `ui_empty_notices` | - | 暂无公告 | No notices |
| 36 | ui | `ui_refreshed_at` | {0} | 更新于 %1$s | Updated %1$s |
| 37 | ui | `ui_notice_publish_time` | - | YYYY 年 M 月 D 日 dddd HH:mm | MMM D, YYYY HH:mm |
| 38 | ui | `ui_weekday_sunday` | - | 星期日 | Sun |
| 39 | ui | `ui_weekday_monday` | - | 星期一 | Mon |
| 40 | ui | `ui_weekday_tuesday` | - | 星期二 | Tue |
| 41 | ui | `ui_weekday_wednesday` | - | 星期三 | Wed |
| 42 | ui | `ui_weekday_thursday` | - | 星期四 | Thu |
| 43 | ui | `ui_weekday_friday` | - | 星期五 | Fri |
| 44 | ui | `ui_weekday_saturday` | - | 星期六 | Sat |
| 45 | ui | `ui_month_jan` | - | 1 月 | Jan |
| 46 | ui | `ui_month_feb` | - | 2 月 | Feb |
| 47 | ui | `ui_month_mar` | - | 3 月 | Mar |
| 48 | ui | `ui_month_apr` | - | 4 月 | Apr |
| 49 | ui | `ui_month_may` | - | 5 月 | May |
| 50 | ui | `ui_month_jun` | - | 6 月 | Jun |
| 51 | ui | `ui_month_jul` | - | 7 月 | Jul |
| 52 | ui | `ui_month_aug` | - | 8 月 | Aug |
| 53 | ui | `ui_month_sep` | - | 9 月 | Sep |
| 54 | ui | `ui_month_oct` | - | 10 月 | Oct |
| 55 | ui | `ui_month_nov` | - | 11 月 | Nov |
| 56 | ui | `ui_month_dec` | - | 12 月 | Dec |
| 57 | ui | `ui_attachment_label` | - | 含附件 | Has attachment |
| 58 | ui | `ui_marked_important_label` | - | 重要公告 | Marked important |
| 59 | ui | `ui_course_unread_notices_label` | - | 未读公告 | Unread notices |
| 60 | ui | `ui_course_unfinished_assignments_label` | - | 未完成作业 | Unfinished assignments |
| 61 | ui | `ui_course_new_files_label` | - | 新文件 | New files |
| 62 | ui | `ui_courses_semester_label` | - | 当前学期 | Current semester |
| 63 | ui | `ui_courses_empty` | - | 暂无课程 | No courses |
| 64 | ui | `ui_course_semester_list_unavailable` | - | 学期列表暂不可用，仅列出当前学期与已生效的学期。 | The semester list is unavailable; only the current and the active semester are listed. |
| 65 | ui | `ui_courses_load_failed` | {0} | 课程加载失败：%1$s | Failed to load courses: %1$s |
| 66 | ui | `ui_courses_override_badge` | - | 取证覆盖生效 | Evidence override active |
| 67 | ui | `ui_assignments_empty` | - | 暂无作业 | No assignments |
| 68 | ui | `ui_assignments_none_unfinished` | - | 没有未完成的作业 | No unfinished assignments |
| 69 | ui | `ui_assignments_none_finished` | - | 没有已完成的作业 | No finished assignments |
| 70 | ui | `ui_assignments_load_failed` | {0} | 作业加载失败：%1$s | Failed to load assignments: %1$s |
| 71 | ui | `ui_assignment_upcoming` | - | 未到期 | Not due |
| 72 | ui | `ui_assignment_past_due` | - | 已截止 | Past due |
| 73 | ui | `ui_assignment_deadline` | - | 截止时间 | Deadline |
| 74 | ui | `ui_assignment_late_deadline` | - | 补交截止 | Late submission due |
| 75 | ui | `ui_assignment_description` | - | 作业内容 | Description |
| 76 | ui | `ui_assignment_grade` | - | 成绩 | Grade |
| 77 | ui | `ui_assignment_answer` | - | 参考答案 | Answer |
| 78 | ui | `ui_assignment_submitted_at` | {0} | 提交于 %1$s | Submitted at %1$s |
| 79 | ui | `ui_assignment_submitted_late_at` | {0} | 补交于 %1$s | Submitted late at %1$s |
| 80 | ui | `ui_assignment_graded_at` | {0} | 批改于 %1$s | Graded at %1$s |
| 81 | ui | `ui_assignment_graded_by_at` | {0},{1} | %1$s 批改于 %2$s | Graded by %1$s at %2$s |
| 82 | ui | `ui_assignment_attachment_label` | - | 作业附件 | Assignment attachment |
| 83 | ui | `ui_assignment_submitted_attachment_label` | - | 我的提交附件 | Submitted attachment |
| 84 | ui | `ui_assignment_grade_attachment_label` | - | 批改附件 | Grade attachment |
| 85 | ui | `ui_assignment_answer_attachment_label` | - | 答案附件 | Answer attachment |
| 86 | ui | `ui_assignment_submitted_mark_label` | - | 已提交 | Submitted |
| 87 | ui | `ui_assignment_graded_mark_label` | - | 已评分 | Graded |
| 88 | ui | `ui_assignment_answer_mark_label` | - | 含答案 | Has answer |
| 89 | ui | `ui_assignment_excellent` | - | 优秀作业 | Excellent homework |
| 90 | ui | `ui_assignment_excellent_by` | {0} | %1$s的优秀作业 | Excellent homework by %1$s |
| 91 | ui | `ui_assignment_excellent_mark_label` | - | 含优秀作业 | Has excellent homework |
| 92 | ui | `ui_enrollment_fingerprint_not_ready` | - | 浏览器指纹尚未就绪，此刻提交不会把该浏览器记为可信（服务端会提示"隐私或匿名模式"）。请稍等几秒后再次点击登录；若反复出现，请关闭本页重新登录。 | The browser fingerprint is not ready yet, so signing in now would not register this browser as trusted (the server would report a private/anonymous browser). Wait a few seconds and tap sign in again; if it keeps happening, close this page and sign in again. |
| 93 | ui | `ui_files_empty` | - | 暂无文件 | No files |
| 94 | ui | `ui_files_load_failed` | {0} | 文件加载失败：%1$s | Failed to load files: %1$s |
| 95 | ui | `ui_file_type_label` | - | 类型 | Type |
| 96 | ui | `ui_file_size_label` | - | 大小 | Size |
| 97 | ui | `ui_file_upload_time_label` | - | 上传时间 | Uploaded at |
| 98 | ui | `ui_file_downloading` | - | 下载中 | Downloading |
| 99 | ui | `ui_file_download_progress` | {0},{1} | %1$s / %2$s | %1$s / %2$s |
| 100 | ui | `ui_file_download_received` | {0} | 已接收 %1$s | Received %1$s |
| 101 | ui | `ui_file_download_rejected` | {0} | 下载被拒绝：%1$s | Download rejected: %1$s |
| 102 | ui | `ui_file_download_empty` | - | 服务端返回了空文件 | The server returned an empty file |
| 103 | ui | `ui_file_preview_failed` | {0} | 预览失败：%1$s | Preview failed: %1$s |
| 104 | ui | `ui_file_preview_unavailable` | - | 该文件类型不支持应用内预览，可下载后分享给其他应用。 | This file type cannot be previewed in the app; download it and share it with another app. |
| 105 | ui | `ui_file_share_failed` | {0} | 分享失败：%1$s | Share failed: %1$s |
| 106 | ui | `ui_file_saved_at` | {0} | 保存位置：%1$s | Saved at: %1$s |
| 107 | ui | `ui_file_view_info` | - | 详情 | Info |
| 108 | ui | `ui_file_view_preview` | - | 预览 | Preview |
| 109 | ui | `ui_file_settings_title` | - | 文件设置 | File settings |
| 110 | ui | `ui_file_use_document_dir_on` | - | 文件保存在 App 的"文档"中，只会随 App 卸载而被删除。 | Files are saved in the App Document folder and are deleted only when the app is uninstalled. |
| 111 | ui | `ui_file_use_document_dir_off` | - | 文件保存在 App 的"缓存"中，会在设备空间不足或其他系统预设情况下被自动清除以节约空间。 | Files are saved in the App cache folder; the system may clear it when space is low. |
| 112 | ui | `ui_file_omit_course_name_on` | - | 文件以"文件名"形式保存。 | Files are saved as "filename". |
| 113 | ui | `ui_file_omit_course_name_off` | - | 文件以"课程名-文件名"形式保存。 | Files are saved as "coursename-filename". |
| 114 | ui | `ui_file_settings_root` | {0} | 当前保存位置：%1$s | Current save location: %1$s |
| 115 | ui | `ui_file_settings_open` | - | 文件设置 | File settings |
| 116 | ui | `ui_file_prev_page` | - | 上一页 | Previous page |
| 117 | ui | `ui_file_next_page` | - | 下一页 | Next page |
| 118 | ui | `ui_file_page_of` | {0},{1} | 第 %1$s / %2$s 页 | Page %1$s of %2$s |
| 119 | ui | `ui_file_cache_already_empty` | - | 缓存目录已为空 | The cache folder is already empty |
| 120 | ui | `ui_updated_just_now` | - | 刚刚更新 | Updated just now |
| 121 | ui | `ui_updated_minutes_ago` | {0} | %1$s 分钟前更新 | Updated %1$s min ago |
| 122 | ui | `ui_updated_hours_ago` | {0} | %1$s 小时前更新 | Updated %1$s h ago |
| 123 | ui | `ui_updated_days_ago` | {0} | %1$s 天前更新 | Updated %1$s d ago |
| 124 | ui | `ui_assignment_submission_time` | - | 上次提交于 YYYY 年 M 月 D 日 dddd HH:mm | [last submitted at] HH:mm, MMM D, YYYY |
| 125 | ui | `ui_remove_favorite` | - | 取消收藏 | Remove from favorites |
| 126 | ui | `ui_unarchive` | - | 取消归档 | Unarchive |
| 127 | ui | `ui_unhide_course` | - | 取消屏蔽 | Unhide course |

