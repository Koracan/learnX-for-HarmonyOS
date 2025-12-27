import React, { memo } from 'react';
import { StyleSheet, View } from 'react-native';
import { Caption, Paragraph, Title, Subheading } from 'react-native-paper';
import MaterialCommunityIcons from 'react-native-vector-icons/MaterialCommunityIcons';
import dayjs from 'dayjs';
import Styles from 'constants/Styles';
import Colors from 'constants/Colors';
import type { File } from 'data/types/state';
import { removeTags } from 'helpers/html';
import CardWrapper, { type CardWrapperProps } from './CardWrapper';

export interface FileCardProps extends CardWrapperProps {
  data: File;
  hideCourseName?: boolean;
}

const FileCard: React.FC<React.PropsWithChildren<FileCardProps>> = ({
  data: {
    title,
    description,
    courseName,
    size,
    fileType,
    markedImportant,
    isNew,
    uploadTime,
    category,
  },
  hideCourseName,
  ...restProps
}) => {
  return (
    <CardWrapper {...restProps} style={[styles.card, restProps.style]}>
      <View style={styles.content}>
        <View style={Styles.flexRowCenter}>
          <View style={styles.titleContainer}>
            {hideCourseName ? null : (
              <Subheading numberOfLines={1} style={styles.courseName}>
                {courseName}
              </Subheading>
            )}
            <Title numberOfLines={1}>{title}</Title>
          </View>
          <View style={[Styles.flexRow, styles.icons]}>
            {markedImportant ? (
              <MaterialCommunityIcons
                style={styles.icon}
                name="flag"
                color={Colors.red500}
                size={20}
              />
            ) : null}
            {isNew ? (
              <MaterialCommunityIcons
                style={styles.icon}
                name="checkbox-blank-circle"
                color={Colors.blue500}
                size={12}
              />
            ) : null}
          </View>
        </View>
        {removeTags(description) ? (
          <Paragraph numberOfLines={2} style={styles.description}>
            {removeTags(description)}
          </Paragraph>
        ) : null}
        <View style={Styles.flexRowCenter}>
          <Caption>
            {`${category?.title ?? ''} ${fileType?.toUpperCase() ?? ''} ${size}`.trim()}
          </Caption>
          <Caption>{dayjs(uploadTime).fromNow()}</Caption>
        </View>
      </View>
    </CardWrapper>
  );
};

const styles = StyleSheet.create({
  card: {
    marginHorizontal: 12,
    marginVertical: 6,
    elevation: 2,
  },
  content: {
    padding: 12,
  },
  titleContainer: {
    flex: 1,
    marginRight: 8,
  },
  courseName: {
    fontSize: 12,
    lineHeight: 16,
    opacity: 0.7,
  },
  icons: {
    alignItems: 'center',
    justifyContent: 'flex-end',
  },
  icon: {
    marginLeft: 6,
  },
  description: {
    marginTop: 4,
    marginBottom: 8,
  },
});

export default memo(FileCard);
