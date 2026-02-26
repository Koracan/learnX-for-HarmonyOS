import React from 'react';
import { StyleSheet, View } from 'react-native';
import { useSafeAreaFrame } from 'react-native-safe-area-context';
import { Text } from 'react-native-paper';

export interface HeaderTitleProps {
  title: string;
  subtitle?: string;
  avoidWidth?: number;
}

const HeaderTitle: React.FC<React.PropsWithChildren<HeaderTitleProps>> = ({
  title,
  subtitle,
  avoidWidth = 0,
}) => {
  let pageWidth = useSafeAreaFrame().width;
  let pageHeight = useSafeAreaFrame().height;
  if (pageWidth >= 750 && pageWidth > pageHeight) { // 分屏模式
    pageWidth -= 450;
  }

  const availableWidth = pageWidth - avoidWidth;

  return (
    <View
      style={{
        flexDirection: 'row',
        alignItems: 'baseline',
        justifyContent: 'center',
        maxWidth: availableWidth,
      }}
    >
      <Text style={styles.title} numberOfLines={1} ellipsizeMode="middle">
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
