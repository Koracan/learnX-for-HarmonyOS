import { Platform, Dimensions } from 'react-native';

const { width, height } = Dimensions.get('window');
const isTablet = () => {
  if (Platform.OS === 'ios') {
    return Platform.isPad;
  }
  // Simple heuristic for Android tablets
  return Math.min(width, height) >= 600;
  
};

export default {
  isTablet,
  isMac: () => false,
  model: () => 'Unknown',
};