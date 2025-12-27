import React from 'react';
import { StyleSheet, useColorScheme, View, Text } from 'react-native';

const Splash: React.FC = () => {
  const colorScheme = useColorScheme();

/**
 * 启动页：在数据持久化恢复期间显示。
 */
  return (
    <View
      style={[
        styles.center,
        {
          backgroundColor:
              colorScheme === 'dark'
                ? 'black'
                : 'white',
        },
      ]}
    >
      <Text style={styles.title}>learnOH</Text>
    </View>
  );
};

const styles = StyleSheet.create({
  center: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  title: {
    fontSize: 24,
    fontWeight: '600',
  },
});

export default Splash;
