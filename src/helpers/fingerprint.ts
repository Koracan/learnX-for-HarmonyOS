import { generateSecureRandom } from 'react-native-securerandom';

/**
 * 生成安全随机的 UUID v4 指纹（基于 react-native-securerandom）。
 *
 * @returns Promise<string> UUID v4 格式字符串
 */
export const generateFingerprint = async (): Promise<string> => {
  const bytes = await generateSecureRandom(16);

  // 构造 UUID v4: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
  // 版本位 (byte[6]) 设置为 0x4x
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  // 变体位 (byte[8]) 设置为 0b10xxxxxx
  bytes[8] = (bytes[8] & 0x3f) | 0x80;

  const hexBytes = Array.from(bytes, (byte: number) =>
    byte.toString(16).padStart(2, '0'),
  );

  return [
    hexBytes.slice(0, 4).join(''),
    hexBytes.slice(4, 6).join(''),
    hexBytes.slice(6, 8).join(''),
    hexBytes.slice(8, 10).join(''),
    hexBytes.slice(10, 16).join(''),
  ].join('-');
};

export default generateFingerprint;
