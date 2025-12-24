import RNSecureKeyStore from 'react-native-secure-key-store';

/**
 * Secure storage 适配器，封装 react-native-secure-key-store 为 redux-persist 兼容接口。
 * 
 * 注意：secure key store 在某些环境（模拟器、无锁屏）可能不可用，需要捕获异常。
 */
const SecureStorage = {
  /**
   * 存储键值对到安全存储。
   */
  async setItem(key: string, value: string): Promise<void> {
    try {
      await RNSecureKeyStore.set(key, value);
    } catch (error) {
      console.error('[SecureStorage] setItem failed:', error);
      throw error;
    }
  },

  /**
   * 从安全存储读取值。
   */
  async getItem(key: string): Promise<string | null> {
    try {
      const value = await RNSecureKeyStore.get(key);
      return value || null;
    } catch (error) {
      // Key not found or storage unavailable
      if ((error as any)?.message?.includes('not found')) {
        return null;
      }
      console.error('[SecureStorage] getItem failed:', error);
      return null;
    }
  },

  /**
   * 从安全存储移除键。
   */
  async removeItem(key: string): Promise<void> {
    try {
      await RNSecureKeyStore.remove(key);
    } catch (error) {
      console.error('[SecureStorage] removeItem failed:', error);
      // Ignore removal errors (key may not exist)
    }
  },
};

export default SecureStorage;
