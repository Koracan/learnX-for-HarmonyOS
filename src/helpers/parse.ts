import { type ApiError, FailReason } from 'thu-learn-lib';

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
