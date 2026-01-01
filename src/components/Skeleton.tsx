import { useEffect, useCallback, useRef } from 'react';
import { StyleSheet, View, Animated } from 'react-native';
import { useTheme } from 'react-native-paper';

const Skeleton: React.FC<React.PropsWithChildren<unknown>> = () => {
  const theme = useTheme();

  const opacity = useRef(new Animated.Value(1));

  const fadeAnimation = useCallback(() => {
    const newValue = 0.5;
    const oldValue = 1;
    const duration = 500;

    Animated.sequence([
      Animated.timing(opacity.current, {
        toValue: newValue,
        duration,
        useNativeDriver: true,
      }),
      Animated.timing(opacity.current, {
        toValue: oldValue,
        duration,
        useNativeDriver: true,
      }),
    ]).start(() => {
      fadeAnimation();
    });
  }, []);

  useEffect(() => {
    fadeAnimation();
  }, [fadeAnimation]);

  const skeletonColor = theme.dark ? 'rgba(255,255,255,0.1)' : 'rgba(0,0,0,0.1)';

  return (
    <View style={[styles.root, { backgroundColor: theme.colors.surface }]}>
      <Animated.View style={[styles.line1, { opacity: opacity.current, backgroundColor: skeletonColor }]} />
      <Animated.View style={[styles.line2, { opacity: opacity.current, backgroundColor: skeletonColor }]} />
      <Animated.View style={[styles.line3, { opacity: opacity.current, backgroundColor: skeletonColor }]} />
      <Animated.View style={[styles.line4, { opacity: opacity.current, backgroundColor: skeletonColor }]} />
    </View>
  );
};

const styles = StyleSheet.create({
  root: {
    paddingVertical: 12,
    paddingHorizontal: 16,
    zIndex: 0,
    marginVertical: 4,
    marginHorizontal: 8,
    borderRadius: 12,
  },
  line1: {
    height: 16,
    width: '30%',
    borderRadius: 4,
    marginVertical: 8,
  },
  line2: {
    height: 16,
    width: '100%',
    borderRadius: 4,
    marginVertical: 8,
  },
  line3: {
    height: 16,
    width: '80%',
    borderRadius: 4,
    marginVertical: 8,
  },
  line4: {
    height: 16,
    width: '20%',
    borderRadius: 4,
    marginVertical: 8,
  },
});

export default Skeleton;
