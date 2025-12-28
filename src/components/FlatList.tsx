import React from 'react';
import { FlatListProps, FlatList as RNFlatList } from 'react-native';
import { useBottomTabBarHeight } from '@react-navigation/bottom-tabs';

function FlatList<T>(props: FlatListProps<T>) {
  let tabBarHeight = 0;
  try {
    tabBarHeight = useBottomTabBarHeight();
  } catch (e) {
    // Not in a tab navigator
  }
  return (
    <RNFlatList
      {...props}
      contentContainerStyle={[
        { paddingBottom: tabBarHeight },
        props.contentContainerStyle,
      ]}
    />
  );
}

export default FlatList;
