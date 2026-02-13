import React, { useCallback, useRef } from 'react';
import { StyleSheet, View, Animated, type ViewStyle, type StyleProp } from 'react-native';
import { useTheme } from 'react-native-paper';
import Swipeable from 'react-native-gesture-handler/Swipeable';
import { RectButton } from 'react-native-gesture-handler';
import MaterialIcons from 'react-native-vector-icons/MaterialIcons';
import MaterialCommunityIcons from 'react-native-vector-icons/MaterialCommunityIcons';
import Colors from 'constants/Colors';
import Touchable from './Touchable';

const buttonWidth = 80;

const SwipeActions: React.FC<{
  position: 'left' | 'right';
  dragX: Animated.AnimatedInterpolation<number>;
  swipeable: Swipeable;
  fav?: boolean;
  onFav?: (fav: boolean) => void;
  archived?: boolean;
  onArchive?: (archived: boolean) => void;
  hidden?: boolean;
  onHide?: (hide: boolean) => void;
}> = ({
  dragX,
  swipeable,
  onHide,
  hidden,
  onArchive,
  archived,
  onFav,
  fav,
}) => {
  const totalButtonWidth = onHide ? buttonWidth : buttonWidth * (archived ? 1 : 2);

  const trans = dragX.interpolate({
    inputRange: [-totalButtonWidth, 0],
    outputRange: [0, totalButtonWidth],
    extrapolate: 'clamp',
  });

  const resetSnap = () => {
    swipeable.close();
  };

  const handleFav = () => {
    onFav?.(!fav);
    resetSnap();
  };

  const handleArchive = () => {
    onArchive?.(!archived);
    resetSnap();
  };

  const handleHide = () => {
    onHide?.(!hidden);
    resetSnap();
  };

  return (
    <View style={{ width: totalButtonWidth, flexDirection: 'row' }}>
      <Animated.View style={{ flex: 1, flexDirection: 'row', transform: [{ translateX: trans }] }}>
        {onHide ? (
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
        ) : (
          <>
            {archived ? null : (
              <Touchable
                type="opacity"
                style={[
                  styles.button,
                  {
                    backgroundColor: 'rgba(255,59,48,0.2)',
                  },
                ]}
                onPress={handleFav}
              >
                <MaterialCommunityIcons
                  name={fav ? 'heart-off' : 'heart'}
                  size={32}
                  color={Colors.red500}
                />
              </Touchable>
            )}
            <Touchable
              type="opacity"
              style={[
                styles.button,
                {
                  backgroundColor: 'rgba(33,150,243,0.2)',
                },
              ]}
              onPress={handleArchive}
            >
              <MaterialCommunityIcons
                name={archived ? 'archive-arrow-up' : 'archive-arrow-down'}
                size={32}
                color={Colors.blue500}
              />
            </Touchable>
          </>
        )}
      </Animated.View>
    </View>
  );
};

export interface CardWrapperProps {
  style?: StyleProp<ViewStyle>;
  onPress?: () => void;
  onLongPress?: () => void;
  fav?: boolean;
  onFav?: (fav: boolean) => void;
  archived?: boolean;
  onArchive?: (archived: boolean) => void;
  hidden?: boolean;
  onHide?: (hide: boolean) => void;
  disableSwipe?: boolean;
}

const CardWrapper: React.FC<React.PropsWithChildren<CardWrapperProps>> = ({
  children,
  style,
  onPress,
  onLongPress,
  fav,
  onFav,
  archived,
  onArchive,
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
    if ((onHide || onFav || onArchive) && !disableSwipe) {
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
      if (!onHide && !onFav && !onArchive) {
        return null;
      }
      return (
        <SwipeActions
          position="right"
          dragX={dragX}
          swipeable={swipeable}
          fav={fav}
          onFav={onFav}
          archived={archived}
          onArchive={onArchive}
          hidden={hidden}
          onHide={onHide}
        />
      );
    },
    [fav, onFav, archived, onArchive, hidden, onHide],
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

  if (disableSwipe || (!onHide && !onFav && !onArchive)) {
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

