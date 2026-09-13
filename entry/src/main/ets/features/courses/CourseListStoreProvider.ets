/*
 * 课程状态的组装点（composition root，features/courses）。
 *
 * **必须是进程内单例**：学期选择与课程列表是同一份状态。参考实现把它们放在同一棵
 * redux state 里（`semesters.current` 是全局的，不是某个页面自己的），课程 tab、
 * 作业 tab、搜索页、设置页里的学期切换读的都是它——所以一处选择，处处生效。
 *
 * 四个页面各 `new` 一份就做不到：在设置里选中的学期只有设置页那一份知道，
 * 课程 tab 会拿它自己的空选择去按站点当前学期取数，画面上就是"切了不生效"。
 *
 * 与 `collectionFlagsStore` 同一模式：界面只依赖 `CourseListStore` 的接口，
 * 取数实现（真实 / mock）只在这里被选定一次。
 */

import { Logger } from '../../core/log/Logger';
import { CourseListStore } from './CourseListStore';
import { createCourseRepository } from './repository/CourseRepositoryProvider';

const logger: Logger = new Logger('features.courses.provider');

let store: CourseListStore | null = null;

/** 当前生效的课程状态 store（进程内单例）。 */
export function courseListStore(): CourseListStore {
  if (store === null) {
    store = new CourseListStore(createCourseRepository());
    logger.info('course list store wired: process singleton (semester selection is global)');
  }
  return store;
}
