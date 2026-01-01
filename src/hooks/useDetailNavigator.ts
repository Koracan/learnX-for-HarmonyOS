import { useContext } from 'react';
import { SplitViewContext } from 'components/SplitView';
import { type NavigationContainerRef } from '@react-navigation/native';
import { type DetailStackParams } from 'screens/types';

const useDetailNavigator = () => {
  const context = useContext(SplitViewContext);

  return context.detailNavigationContainerRef
    ?.current as NavigationContainerRef<DetailStackParams> | null;
};

export default useDetailNavigator;
