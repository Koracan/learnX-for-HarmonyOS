import CookieManager from '@react-native-cookies/cookies';
import { Learn2018Helper } from 'thu-learn-lib';
import { store } from 'data/store';
import Urls from 'constants/Urls';

export let dataSource: Learn2018Helper;

export const clearLoginCookies = async () => {
	try {
		// HarmonyOS cookies may persist unexpectedly; clear all for safety
		await CookieManager.clearAll(true);
	} catch {}
	try {
		await CookieManager.set(Urls.id, {
			httpOnly: true,
			name: 'JSESSIONID',
			path: '/',
			value: '',
		});
	} catch {}
	try {
		await CookieManager.set(Urls.learn, {
			httpOnly: true,
			name: 'JSESSIONID',
			path: '/',
			value: '',
		});
	} catch {}
};

export const loginWithFingerPrint = async (
	username?: string,
	password?: string,
	fingerPrint?: string,
	fingerGenPrint?: string,
	fingerGenPrint3?: string,
) => {
	await clearLoginCookies();
	await dataSource.login(
		username,
		password,
		fingerPrint,
		fingerGenPrint,
		fingerGenPrint3,
	);
};

export const resetDataSource = () => {
	dataSource = new Learn2018Helper({
		provider: () => {
			const state = store.getState();
			const creds = {
				username: state.auth.username || undefined,
				password: state.auth.password || undefined,
				fingerPrint: state.auth.fingerPrint || '',
				fingerGenPrint: state.auth.fingerGenPrint || '',
				fingerGenPrint3: state.auth.fingerGenPrint3 || '',
			};
			console.log('[dataSource provider] Providing credentials:', {
				hasUsername: !!creds.username,
				hasPassword: !!creds.password,
				hasFingerprint: !!creds.fingerPrint,
			});
			return creds;
		},
	});
};

resetDataSource();
