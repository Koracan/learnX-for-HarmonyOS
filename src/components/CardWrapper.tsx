import React, { useCallback, useRef } from 'react';
import { StyleSheet, View, Animated, type ViewStyle, type StyleProp } from 'react-native';
import { useTheme } from 'react-native-paper';
import Swipeable from 'react-native-gesture-handler/Swipeable';
import { RectButton } from 'react-native-gesture-handler';
import MaterialIcons from 'react-native-vector-icons/MaterialIcons';
import Colors from 'constants/Colors';
import Touchable from './Touchable';

const buttonWidth = 80;

const SwipeActions: React.FC<{
  position: 'left' | 'right';
  dragX: Animated.AnimatedInterpolation<number>;
  swipeable: Swipeable;
  hidden?: boolean;
  onHide?: (hide: boolean) => void;
}> = ({
  dragX,
  swipeable,
  onHide,
  hidden,
}) => {
  const totalButtonWidth = buttonWidth;

  const trans = dragX.interpolate({
    inputRange: [-totalButtonWidth, 0],
    outputRange: [0, totalButtonWidth],
    extrapolate: 'clamp',
  });

  const handleHide = () => {
    onHide?.(!hidden);
    swipeable.close();
  };

  return (
    <View style={{ width: totalButtonWidth, flexDirection: 'row' }}>
      <Animated.View style={{ flex: 1, transform: [{ translateX: trans }] }}>
        <Touchable
          type="opacity"
          style={[
            styles.button,
            {
              backgroundColor: 'rgba(255,204,0,0.2)',
            },
          ]}
          onPress={handleHide}
        >
          <MaterialIcons
            name={hidden ? 'visibility' : 'visibility-off'}
            size={32}
            color={Colors.yellow500}
          />
        </Touchable>
      </Animated.View>
    </View>
  );
};

export interface CardWrapperProps {
  style?: StyleProp<ViewStyle>;
  onPress?: () => void;
  onLongPress?: () => void;
  hidden?: boolean;
  onHide?: (hide: boolean) => void;
  disableSwipe?: boolean;
}

const CardWrapper: React.FC<React.PropsWithChildren<CardWrapperProps>> = ({
  children,
  style,
  onPress,
  onLongPress,
  hidden,
  onHide,
  disableSwipe,
}) => {
  const theme = useTheme();
  const swipeableRef = useRef<Swipeable>(null);

  const resetSnap = () => {
    swipeableRef.current?.close();
  };

  const handlePress = () => {
    resetSnap();
    onPress?.();
  };

  const handleLongPress = () => {
    if (onHide && !disableSwipe) {
      swipeableRef.current?.openRight();
    }
    onLongPress?.();
  };

  const renderRightActions = useCallback(
    (
      _progress: Animated.AnimatedInterpolation<number>,
      dragX: Animated.AnimatedInterpolation<number>,
      swipeable: Swipeable,
    ) => {
      if (!onHide) {
        return null;
      }
      return (
        <SwipeActions
          position="right"
          dragX={dragX}
          swipeable={swipeable}
          hidden={hidden}
          onHide={onHide}
        />
      );
    },
    [hidden, onHide],
  );

  const content = (
    <RectButton
      onPress={handlePress}
      onLongPress={handleLongPress}
      underlayColor={
        theme.dark
          ? 'rgba(255,255,255,0.125)'
          : 'rgba(0,0,0,0.125)'
      }
      activeOpacity={0.1}
      style={{ backgroundColor: theme.colors.surface }}
    >
      <View style={styles.inner}>{children}</View>
    </RectButton>
  );

  if (disableSwipe || !onHide) {
    return (
      <View style={[styles.root, style]}>
        {content}
      </View>
    );
  }

  return (
    <View style={[styles.root, style]}>
      <Swipeable
        ref={swipeableRef}
        friction={1}
        overshootFriction={8}
        enableTrackpadTwoFingerGesture
        rightThreshold={40}
        renderRightActions={renderRightActions}
        enabled={!disableSwipe}
      >
        {content}
      </Swipeable>
    </View>
  );
};

const styles = StyleSheet.create({
  root: {
    marginVertical: 4,
    marginHorizontal: 8,
    borderRadius: 12,
    overflow: 'hidden',
    elevation: 1,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.2,
    shadowRadius: 1,
  },
  inner: {
    paddingHorizontal: 16,
    paddingVertical: 12,
    flexDirection: 'row',
    alignItems: 'center',
  },
  drawer: {
    flexDirection: 'row',
  },
  button: {
    width: buttonWidth,
    height: '100%',
    justifyContent: 'center',
    alignItems: 'center',
  },
});

export default CardWrapper;

