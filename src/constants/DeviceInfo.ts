import { Dimensions } from 'react-native';

const { width, height } = Dimensions.get('window');

export default {
  isTablet: () => Math.min(width, height) >= 600,
  isMac: () => false,
  model: () => 'HarmonyOS Device',
};
