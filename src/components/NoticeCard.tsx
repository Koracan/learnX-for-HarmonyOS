import React, { memo } from 'react';
import { StyleSheet, View } from 'react-native';
import { Text } from 'react-native-paper';
import Icon from 'react-native-vector-icons/MaterialCommunityIcons';
import dayjs from 'dayjs';
import Styles from '../constants/Styles';
import Colors from '../constants/Colors';
import type { Notice } from '../data/types/state';
import { removeTags } from '../helpers/html';
import CardWrapper, { type CardWrapperProps } from './CardWrapper';

export interface NoticeCardProps extends CardWrapperProps {
  data: Notice;
  hideCourseName?: boolean;
}

const NoticeCard: React.FC<React.PropsWithChildren<NoticeCardProps>> = ({
  data: {
    title,
    content,
    courseName,
    publisher,
    publishTime,
    markedImportant,
    hasRead,
    attachment,
  },
  hideCourseName,
  ...restProps
}) => {
  return (
    <CardWrapper {...restProps}>
      <View style={Styles.flex1}>
        <View style={Styles.flexRowCenter}>
          <View style={styles.title}>
            {hideCourseName ? null : (
              <Text variant="labelMedium" numberOfLines={1}>
                {courseName}
              </Text>
            )}
            <Text variant="titleMedium" numberOfLines={1}>
              {title}
            </Text>
          </View>
          <View style={[Styles.flexRowCenter, styles.icons]}>
            {attachment && (
              <Icon
                style={styles.icon}
                name="attachment"
                color={Colors.orange500}
                size={20}
              />
            )}
            {markedImportant && (
              <Icon
                style={styles.icon}
                name="flag"
                color={Colors.red500}
                size={20}
              />
            )}
            {!hasRead && (
              <Icon
                style={styles.icon}
                name="checkbox-blank-circle"
                color={Colors.blue500}
              />
            )}
          </View>
        </View>
        {removeTags(content) ? (
          <Text variant="bodyMedium" numberOfLines={2}>
            {removeTags(content)}
          </Text>
        ) : null}
        <View style={Styles.flexRowCenter}>
          <Text variant="labelSmall">{publisher}</Text>
          <Text variant="labelSmall" style={styles.time}>
            {dayjs(publishTime).fromNow()}
          </Text>
        </View>
      </View>
    </CardWrapper>
  );
};

const styles = StyleSheet.create({
  title: {
    flex: 10,
  },
  icons: {
    flex: 2,
    justifyContent: 'flex-end',
  },
  icon: {
    marginLeft: 6,
  },
  time: {
    marginLeft: 8,
  },
});

export default memo(NoticeCard);
