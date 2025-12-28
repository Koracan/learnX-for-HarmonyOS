import React from 'react';
import { StyleSheet, View, type ViewStyle, type StyleProp } from 'react-native';
import { useTheme } from 'react-native-paper';
import Touchable from './Touchable';

export interface CardWrapperProps {
  style?: StyleProp<ViewStyle>;
  onPress?: () => void;
  onLongPress?: () => void;
}

const CardWrapper: React.FC<React.PropsWithChildren<CardWrapperProps>> = ({
  children,
  style,
  onPress,
  onLongPress,
}) => {
  const theme = useTheme();

  return (
    <Touchable
      style={[
        styles.root,
        { backgroundColor: theme.colors.surface },
        style,
      ]}
      onPress={onPress}
      onLongPress={onLongPress}
    >
      <View style={styles.inner}>
        {children}
      </View>
    </Touchable>
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
});

export default CardWrapper;
