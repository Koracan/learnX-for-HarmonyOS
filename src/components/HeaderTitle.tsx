import React from 'react';
import { StyleSheet, View } from 'react-native';
import { Text } from 'react-native-paper';

export interface HeaderTitleProps {
  title: string;
  subtitle?: string;
}

const HeaderTitle: React.FC<React.PropsWithChildren<HeaderTitleProps>> = ({
  title,
  subtitle,
}) => {
  return (
    <View
      style={{
        flexDirection: 'row',
        alignItems: 'baseline',
        justifyContent: 'center',
      }}
    >
      <Text
        style={[styles.title, subtitle ? { flexShrink: 1 } : {}]}
        numberOfLines={1}
        ellipsizeMode="middle"
      >
        {title}
      </Text>
      {subtitle ? (
        <Text style={styles.subtitle} numberOfLines={1} ellipsizeMode="middle">
          {subtitle}
        </Text>
      ) : null}
    </View>
  );
};

const styles = StyleSheet.create({
  title: {
    fontSize: 20,
    fontWeight: 'bold',
  },
  subtitle: {
    fontSize: 12,
    marginLeft: 8,
    opacity: 0.6,
  },
});

export default HeaderTitle;
