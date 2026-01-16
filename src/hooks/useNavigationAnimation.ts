import { useLayoutEffect } from 'react';
import { type StackScreenProps } from '@react-navigation/stack';
import { type ParamListBase } from '@react-navigation/native';

const useNavigationAnimation = <T extends keyof ParamListBase>({
  navigation,
  route,
}: StackScreenProps<ParamListBase, T>) => {
  const disableAnimation = (route.params as any)?.disableAnimation;

  useLayoutEffect(() => {
    if (disableAnimation && navigation) {
      navigation.setOptions({
        animationEnabled: false,
      });
    }
  }, [navigation, disableAnimation, route.name]);
};

export default useNavigationAnimation;
