import Info from 'react-native-device-info';

const cached: {
  buildNo: string;
  isTablet: boolean;
  systemVersion: string;
  model: string;
} = {
  buildNo: Info.getBuildNumber(),
  isTablet: Info.isTablet(),
  systemVersion: Info.getSystemVersion(),
  model: Info.getModel(),
};

export default {
  isTablet: () => cached.isTablet,
  model: () => cached.model,
  buildNo: () => cached.buildNo,
  systemVersion: () => cached.systemVersion,
};
