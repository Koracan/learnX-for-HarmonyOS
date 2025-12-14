import { ApiError, FailReason } from 'thu-learn-lib';

// Minimal error serializer used by auth flows
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
