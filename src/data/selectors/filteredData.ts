import { createSelector } from '@reduxjs/toolkit';
import dayjs from 'dayjs';
import type { AppState } from 'data/types/state';

// Base Selectors
const selectNoticesItems = (state: AppState) => state.notices.items;
const selectNoticesFav = (state: AppState) => state.notices.favorites;
const selectNoticesArchived = (state: AppState) => state.notices.archived;

const selectAssignmentsItems = (state: AppState) => state.assignments.items;
const selectAssignmentsFav = (state: AppState) => state.assignments.favorites;
const selectAssignmentsArchived = (state: AppState) =>
  state.assignments.archived;

const selectFilesItems = (state: AppState) => state.files.items;
const selectFilesFav = (state: AppState) => state.files.favorites;
const selectFilesArchived = (state: AppState) => state.files.archived;

const selectCoursesItems = (state: AppState) => state.courses.items;
const selectHiddenCourseIds = (state: AppState) => state.courses.hidden;

// --- Courses Selectors ---

export const selectCoursesWithCounts = createSelector(
  [
    selectCoursesItems,
    selectNoticesItems,
    selectAssignmentsItems,
    selectFilesItems,
  ],
  (courses, notices, assignments, files) => {
    const now = dayjs();
    return courses.map(course => ({
      ...course,
      unreadNoticeCount: notices.filter(
        notice => notice.courseId === course.id && !notice.hasRead,
      ).length,
      unfinishedAssignmentCount: assignments.filter(
        assignment =>
          assignment.courseId === course.id &&
          !assignment.submitted &&
          dayjs(assignment.deadline).isAfter(now),
      ).length,
      unreadFileCount: files.filter(
        file => file.courseId === course.id && file.isNew,
      ).length,
    }));
  },
);

export const selectFilteredCourses = createSelector(
  [selectCoursesWithCounts, selectHiddenCourseIds],
  (items, hidden) => ({
    all: items.filter(i => !hidden.includes(i.id)),
    hidden: items.filter(i => hidden.includes(i.id)),
  }),
);

export const selectCoursesCounts = createSelector(
  [selectFilteredCourses],
  filtered => ({
    all: filtered.all.length,
    hidden: filtered.hidden.length,
  }),
);

// --- Notices Selectors ---

export const selectFilteredNotices = createSelector(
  [
    selectNoticesItems,
    selectNoticesFav,
    selectNoticesArchived,
    selectHiddenCourseIds,
  ],
  (items, fav, archived, hidden) => {
    const all = items.filter(
      i => !archived.includes(i.id) && !hidden.includes(i.courseId),
    );
    return {
      all,
      unread: all.filter(i => i.hasRead === false),
      fav: all.filter(i => fav.includes(i.id)),
      archived: items.filter(i => archived.includes(i.id)),
      hidden: items.filter(i => hidden.includes(i.courseId)),
    };
  },
);

export const selectNoticesCounts = createSelector(
  [selectFilteredNotices],
  filtered => ({
    all: filtered.all.length,
    unread: filtered.unread.length,
    fav: filtered.fav.length,
    archived: filtered.archived.length,
    hidden: filtered.hidden.length,
  }),
);

// --- Assignments Selectors ---

export const selectFilteredAssignments = createSelector(
  [
    selectAssignmentsItems,
    selectAssignmentsFav,
    selectAssignmentsArchived,
    selectHiddenCourseIds,
  ],
  (items, fav, archived, hidden) => {
    const all = items.filter(
      i => !archived.includes(i.id) && !hidden.includes(i.courseId),
    );
    return {
      all,
      unfinished: all.filter(i => !i.submitted),
      finished: all.filter(i => i.submitted),
      fav: all.filter(i => fav.includes(i.id)),
      archived: items.filter(i => archived.includes(i.id)),
      hidden: items.filter(i => hidden.includes(i.courseId)),
    };
  },
);

export const selectAssignmentsCounts = createSelector(
  [selectFilteredAssignments],
  filtered => ({
    all: filtered.all.length,
    unfinished: filtered.unfinished.length,
    finished: filtered.finished.length,
    fav: filtered.fav.length,
    archived: filtered.archived.length,
    hidden: filtered.hidden.length,
  }),
);

// --- Files Selectors ---

export const selectFilteredFiles = createSelector(
  [
    selectFilesItems,
    selectFilesFav,
    selectFilesArchived,
    selectHiddenCourseIds,
  ],
  (items, fav, archived, hidden) => {
    const all = items.filter(
      i => !archived.includes(i.id) && !hidden.includes(i.courseId),
    );
    return {
      all,
      unread: all.filter(i => i.isNew),
      fav: all.filter(i => fav.includes(i.id)),
      archived: items.filter(i => archived.includes(i.id)),
      hidden: items.filter(i => hidden.includes(i.courseId)),
    };
  },
);

export const selectFilesCounts = createSelector(
  [selectFilteredFiles],
  filtered => ({
    all: filtered.all.length,
    unread: filtered.unread.length,
    fav: filtered.fav.length,
    archived: filtered.archived.length,
    hidden: filtered.hidden.length,
  }),
);
