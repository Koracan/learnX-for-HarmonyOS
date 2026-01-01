import { getLocales } from 'react-native-localize';
import { HomeworkGradeLevel } from 'thu-learn-lib';
import en from '../assets/translations/en';
import zh from '../assets/translations/zh';

/**
 * 获取系统首选语言。
 */
export const getLocale = () => {
  const preferredLocales = getLocales();
  return preferredLocales[0].languageTag;
};

/**
 * 判断当前语言是否为中文。
 */
export const isLocaleChinese = (): boolean => getLocale().startsWith('zh');

type TranslationKey = typeof en | typeof zh;

const translations = (isLocaleChinese() ? zh : en) as TranslationKey;

/**
 * 翻译函数：根据系统语言返回对应的文本。
 */
export function t<K extends keyof TranslationKey>(key: K): string {
  return translations[key];
}

const assignmentGradeLevelDescriptionMap: Partial<{
  [key in HomeworkGradeLevel]: keyof TranslationKey;
}> = {
  [HomeworkGradeLevel.CHECKED]: 'reviewed',
  [HomeworkGradeLevel.DISTINCTION]: 'good',
  [HomeworkGradeLevel.EXEMPTED_COURSE]: 'exemptedCourse',
  [HomeworkGradeLevel.EXEMPTION]: 'exempted',
  [HomeworkGradeLevel.PASS]: 'pass',
  [HomeworkGradeLevel.FAILURE]: 'fail',
  [HomeworkGradeLevel.INCOMPLETE]: 'incomplete',
};

export const getAssignmentGradeLevelDescription = (
  gradeLevel: HomeworkGradeLevel,
) => {
  const translationKey = assignmentGradeLevelDescriptionMap[gradeLevel];
  if (!translationKey) {
    return gradeLevel;
  }
  return t(translationKey);
};

export default {
  t,
  isLocaleChinese,
  getLocale,
  getAssignmentGradeLevelDescription,
};
