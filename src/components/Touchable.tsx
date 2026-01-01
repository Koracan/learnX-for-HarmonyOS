import React from 'react';
import {
  TouchableHighlight,
  type TouchableHighlightProps,
  TouchableOpacity,
} from 'react-native';
import { useTheme } from 'react-native-paper';

const Touchable: React.FC<
  TouchableHighlightProps & {
    type?: 'opacity' | 'highlight';
    highlightColorOpacity?: number;
  }
> = ({ type, highlightColorOpacity, ...props }) => {
  const theme = useTheme();

  return type === 'opacity' ? (
    <TouchableOpacity activeOpacity={0.5} {...props} />
  ) : (
    <TouchableHighlight
      activeOpacity={1}
      underlayColor={
        theme.dark
          ? `rgba(255,255,255,${highlightColorOpacity ?? 0.2})`
          : 'rgba(0,0,0,0.125)'
      }
      {...props}
    />
  );
};

export default Touchable;
