import React from 'react';
import { Card } from 'react-native-paper';
import { ViewStyle, StyleProp } from 'react-native';

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
  return (
    <Card style={style} onPress={onPress} onLongPress={onLongPress}>
      {children}
    </Card>
  );
};

export default CardWrapper;
