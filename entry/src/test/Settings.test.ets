/*
 * 设置与 Mock 模式的**纯逻辑**单测。
 *
 * 覆盖四块（都是可以在 host 上离线断言的部分；界面组件与平台窗口调用不在单测里）：
 *   1. 沉浸式设置的值 / 语义：默认值、开关的写入口（参考实现 ImmersiveSettings.tsx 的
 *      `setSetting('immersiveMode', v)`；第二行开关已移除，连带它的显示值与联动语义）；
 *   2. 持久化：写进注入端口、换一个 store 实例读回来（"重启后保持"的**离线机制证据**），
 *      并钉住落盘载荷里不再有被移除的那个字段；
 *   3. Mock 模式：guest/guest 的判据（逐字对齐 .env）、开关的默认值与进出；
 *   4. 样例数据：三个内容域 + 课程都非空、课程归属自洽、**样例仓储不产生任何网络请求**
 *      （`data/remote/NetworkAudit` 计数为 0 —— 离线那一半）。
 */

import { describe, it, expect } from '@ohos/hypium';
import { Assignment, CourseFile } from '../main/ets/domain/model/ContentItem';
import { NoticeRecord } from '../main/ets/data/notices/NoticeRepository';
import { CourseRecord } from '../main/ets/data/courses/CourseRepository';
import {
  DEFAULT_IMMERSIVE_SETTINGS, ImmersiveSettings, ImmersiveSettingsStore,
  InMemoryImmersiveSettingsPort, describeImmersiveSettings
} from '../main/ets/data/settings/ImmersiveSettings';
import { MockCourseRepository } from '../main/ets/data/mock/MockCourseRepository';
import { MockFileRepository } from '../main/ets/data/mock/MockFileRepository';
import { MockNoticeRepository } from '../main/ets/data/mock/MockNoticeRepository';
import {
  MOCK_CURRENT_SEMESTER, MOCK_SEMESTERS, MOCK_USER_DEPARTMENT, MOCK_USER_NAME,
  mockAssignments, mockCourses, mockFiles, mockNotices
} from '../main/ets/data/mock/MockData';
import { networkAttemptCount, resetNetworkAudit } from '../main/ets/data/remote/NetworkAudit';
import { parseTimestamp } from '../main/ets/domain/parse/Text';
import {
  ClearCacheResult, DownloadProgressSink, FileDownloadRequest
} from '../main/ets/data/files/FileDownloader';
import { FileDownloadReport, FileRepository, FileSnapshot } from '../main/ets/data/files/FileRepository';
import {
  MOCK_PASSWORD, MOCK_USERNAME, enterMockMode, exitMockMode, isMockCredentials, isMockMode
} from '../main/ets/features/mock/MockMode';

/** 只服务委托断言的替身（文件系统那三件事在 mock 模式下被转发给它）。 */
class FakeFileSystem implements FileRepository {
  async refresh(): Promise<FileSnapshot> {
    return { files: [], semesterId: 'fake', fetchedAtMillis: 0 };
  }

  async download(request: FileDownloadRequest, onProgress?: DownloadProgressSink): Promise<FileDownloadReport> {
    return {
      outcome: { ok: true, path: '/fake', bytes: 1, fromCache: false, rejectedReason: '', error: '' },
      requiresEnrollment: false,
      diagnostic: 'fake'
    };
  }

  targetPath(request: FileDownloadRequest): string {
    return '/fake/' + request.cacheKey;
  }

  cacheRoot(): string {
    return '/fake-root';
  }

  clearCache(): ClearCacheResult {
    return { ok: true, root: '/fake-root', error: '' };
  }
}

/** 只钉"值 → 值"的构造器（第二行开关移除后只剩一个字段）。 */
function settings(immersive: boolean): ImmersiveSettings {
  return { immersiveMode: immersive };
}

export default function settingsTest() {
  describe('data.settings.ImmersiveSettings', () => {
    it('defaults to the reference reducer value', 0, () => {
      // reference/learnOH-old/src/data/reducers/settings.ts:20 默认 false。
      expect(DEFAULT_IMMERSIVE_SETTINGS.immersiveMode).assertFalse();
      const store: ImmersiveSettingsStore = new ImmersiveSettingsStore(new InMemoryImmersiveSettingsPort());
      expect(store.current().immersiveMode).assertFalse();
    });

    it('persists immersive mode without the removed avoid-front-camera field', 0, () => {
      const port: InMemoryImmersiveSettingsPort = new InMemoryImmersiveSettingsPort();
      const first: ImmersiveSettingsStore = new ImmersiveSettingsStore(port);
      return first.setImmersiveMode(true).then((persisted: boolean) => {
        expect(persisted).assertTrue();
        // 写出去的载荷形状：只有 immersiveMode 一个字段（被移除的字段不再被读写）。
        return port.load().then((written: ImmersiveSettings | null) => {
          expect(written !== null).assertTrue();
          const payload: string = JSON.stringify(written);
          expect(payload.indexOf('immersiveMode') >= 0).assertTrue();
          expect(payload.indexOf('immersiveAvoidFrontCamera') >= 0).assertFalse();
          // "重启后保持"的离线机制证据：同一个端口被第二个 store 实例读回。
          const second: ImmersiveSettingsStore = new ImmersiveSettingsStore(port);
          return second.load().then(() => {
            expect(second.stored().immersiveMode).assertTrue();
            expect(second.current().immersiveMode).assertTrue();
          });
        });
      });
    });

    it('writes the off value through the port too, and a reload keeps it', 0, () => {
      const port: InMemoryImmersiveSettingsPort = new InMemoryImmersiveSettingsPort();
      const store: ImmersiveSettingsStore = new ImmersiveSettingsStore(port);
      return store.setImmersiveMode(true).then(() => {
        return store.setImmersiveMode(false).then((persisted: boolean) => {
          expect(persisted).assertTrue();
          const reloaded: ImmersiveSettingsStore = new ImmersiveSettingsStore(port);
          return reloaded.load().then(() => {
            expect(reloaded.stored().immersiveMode).assertFalse();
            expect(reloaded.current().immersiveMode).assertFalse();
          });
        });
      });
    });

    it('describes the effective value in one line', 0, () => {
      // 自证串必须含"持久化值"——取证时它是"开关真的到达了 store"的判据。
      const line: string = describeImmersiveSettings(settings(true));
      expect(line.indexOf('immersiveMode=true') >= 0).assertTrue();
      expect(line.indexOf('immersiveAvoidFrontCamera') >= 0).assertFalse();
    });
  });

  describe('features.mock.MockMode', () => {
    it('matches the reference .env guest credentials exactly', 0, () => {
      // reference/learnOH-old/.env: DUMMY_USERNAME=guest / DUMMY_PASSWORD=guest。
      expect(MOCK_USERNAME).assertEqual('guest');
      expect(MOCK_PASSWORD).assertEqual('guest');
      expect(isMockCredentials('guest', 'guest')).assertTrue();
      expect(isMockCredentials('guest', '')).assertFalse();
      expect(isMockCredentials('', 'guest')).assertFalse();
      expect(isMockCredentials('Guest', 'guest')).assertFalse();
      expect(isMockCredentials('guest', 'Guest')).assertFalse();
    });

    it('is off until entered and off again after exit', 0, () => {
      exitMockMode();
      expect(isMockMode()).assertFalse();
      enterMockMode();
      expect(isMockMode()).assertTrue();
      exitMockMode();
      expect(isMockMode()).assertFalse();
    });
  });

  describe('data.mock.MockData', () => {
    it('covers courses plus all three content domains', 0, () => {
      const courses = mockCourses();
      const notices = mockNotices();
      const assignments = mockAssignments();
      const files = mockFiles();
      expect(courses.length > 0).assertTrue();
      expect(notices.length > 0).assertTrue();
      expect(assignments.length > 0).assertTrue();
      expect(files.length > 0).assertTrue();
      // 每个内容项都归属到一门**存在的**课程（否则课程详情页的三个标签页会是空的）。
      const ids: string[] = courses.map((course: CourseRecord) => course.id);
      for (const notice of notices) {
        expect(ids.includes(notice.courseId)).assertTrue();
      }
      for (const assignment of assignments) {
        expect(ids.includes(assignment.courseId)).assertTrue();
      }
      for (const file of files) {
        expect(ids.includes(file.courseId)).assertTrue();
      }
      // 三类"可浏览"的状态都至少各有一条（未读 / 重要 / 带附件 / 未交 / 已交 / 已评分 / 新文件）。
      expect(notices.some((notice: NoticeRecord) => !notice.hasRead)).assertTrue();
      expect(notices.some((notice: NoticeRecord) => notice.markedImportant)).assertTrue();
      expect(notices.some((notice: NoticeRecord) => notice.attachment !== undefined)).assertTrue();
      expect(assignments.some((assignment: Assignment) => !assignment.submitted)).assertTrue();
      expect(assignments.some((assignment: Assignment) => assignment.submitted)).assertTrue();
      expect(assignments.some((assignment: Assignment) => assignment.grade !== undefined)).assertTrue();
      expect(files.some((file: CourseFile) => file.isNew)).assertTrue();
      expect(MOCK_USER_NAME.length > 0).assertTrue();
      expect(MOCK_USER_DEPARTMENT.length > 0).assertTrue();
    });

    it('keeps a deadline in the future so the unfinished counts stay meaningful', 0, () => {
      const now: number = Date.now();
      const open: number = mockAssignments().filter((assignment: Assignment) => !assignment.submitted
        && parseTimestamp(assignment.deadline) > now).length;
      expect(open > 0).assertTrue();
    });
  });

  describe('data.mock repositories', () => {
    it('echo the requested semester through the course snapshot', 0, () => {
      const repository: MockCourseRepository = new MockCourseRepository();
      expect(MOCK_SEMESTERS.includes(MOCK_CURRENT_SEMESTER)).assertTrue();
      return repository.refresh('2025-2026-2').then((snapshot) => {
        expect(snapshot.semesterId).assertEqual('2025-2026-2');
        expect(snapshot.semesterSource).assertEqual('mock-selection');
        expect(snapshot.semestersAvailable).assertTrue();
        return repository.refresh().then((fallback) => {
          expect(fallback.semesterId).assertEqual(MOCK_CURRENT_SEMESTER);
          expect(fallback.semesterSource).assertEqual('mock-site-current');
        });
      });
    });

    it('serves sample data without issuing a single network request', 0, () => {
      // **离线那一半**：NetworkAudit 的计数是进程级的，两个真实 http 出口
      // （HttpClient / HttpDownloadPort）都往它上面加；三个 mock 仓储一次都不该加。
      resetNetworkAudit();
      const notices: MockNoticeRepository = new MockNoticeRepository();
      const courses: MockCourseRepository = new MockCourseRepository();
      const files: MockFileRepository = new MockFileRepository(new FakeFileSystem());
      return notices.loadSnapshot().then((snapshot) => {
        expect(snapshot).assertNull();
        return notices.refresh().then((fresh) => {
          expect(fresh.items.length > 0).assertTrue();
          return courses.refresh().then((courseSnapshot) => {
            expect(courseSnapshot.courses.length > 0).assertTrue();
            return files.refresh().then((fileSnapshot) => {
              expect(fileSnapshot.files.length > 0).assertTrue();
              // 下载在 mock 模式下**直接短路**（返回显式失败），同样不发请求。
              const request: FileDownloadRequest = {
                downloadUrl: 'https://learn.tsinghua.edu.cn/b/wlxt/kc/wj_download?mock=1',
                cacheKey: 'mock-wjid-101', courseName: '数据结构', title: '课程大纲',
                fileType: 'pdf', refresh: false
              };
              return files.download(request).then((report) => {
                expect(report.outcome.ok).assertFalse();
                expect(report.requiresEnrollment).assertFalse();
                // 文件系统三件事仍然委托给真实实现（mock 模式下"文件设置"子页要显示真实根目录）。
                expect(files.cacheRoot()).assertEqual('/fake-root');
                expect(files.targetPath(request)).assertEqual('/fake/mock-wjid-101');
                expect(networkAttemptCount()).assertEqual(0);
              });
            });
          });
        });
      });
    });
  });
}
