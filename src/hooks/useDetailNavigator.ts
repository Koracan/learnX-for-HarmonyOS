import { useContext, type RefObject } from 'react';
import { SplitViewContext } from 'components/SplitView';
import { type NavigationContainerRef } from '@react-navigation/native';
import { type DetailStackParams } from 'screens/types';

const useDetailNavigator =
  (): RefObject<NavigationContainerRef<DetailStackParams> | null> | null => {
    const context = useContext(SplitViewContext);

    return context.detailNavigationContainerRef as RefObject<NavigationContainerRef<DetailStackParams> | null> | null;
  };

export default useDetailNavigator;
