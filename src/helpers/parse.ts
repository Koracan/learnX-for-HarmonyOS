import { type ApiError, FailReason } from 'thu-learn-lib';
import { isLocaleChinese } from './i18n';

export const getSemesterTextFromId = (semesterId: string) => {
  const texts = semesterId.split('-');
  return isLocaleChinese()
    ? `${texts?.[0]}-${texts?.[1]} 学年${
        texts?.[2] === '1'
          ? '秋季学期'
          : texts?.[2] === '2'
          ? '春季学期'
          : '夏季学期'
      }`
    : `${
        texts?.[2] === '1' ? 'Fall' : texts?.[2] === '2' ? 'Spring' : 'Summer'
      } ${texts?.[0]}-${texts?.[1]}`;
};

/**
 * 将 thu-learn-lib 的错误序列化为可持久化对象。
 */
export const serializeError = (err: any): ApiError => {
  if ((err as ApiError).reason) {
    const returnedError = err as ApiError;
    returnedError.extra = JSON.stringify(returnedError.extra);
    return returnedError;
  }
  return {
    reason: FailReason.UNEXPECTED_STATUS,
  } as ApiError;
};
