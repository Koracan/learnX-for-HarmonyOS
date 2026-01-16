import React from 'react';
import { StyleSheet, View, type ViewProps, TextInput } from 'react-native';
import {
  Avatar,
  Text,
  useTheme,
  Switch,
  Badge,
  ActivityIndicator,
} from 'react-native-paper';
import MaterialIcons from 'react-native-vector-icons/MaterialIcons';
import Touchable from './Touchable';

export interface TableCellProps extends ViewProps {
  type: 'none' | 'switch' | 'arrow' | 'input';
  onPress?: () => void;
  primaryText: string;
  secondaryText?: string;
  iconName?: string;
  imageSrc?: any;
  imageAlt?: string;
  switchDisabled?: boolean;
  switchValue?: boolean;
  onSwitchValueChange?: (value: boolean) => void;
  inputValue?: string;
  onInputValueChange?: (value: string) => void;
  loading?: boolean;
  badge?: boolean;
}

const TableCell: React.FC<React.PropsWithChildren<TableCellProps>> = ({
  type,
  onPress,
  primaryText,
  secondaryText,
  iconName,
  imageAlt,
  imageSrc,
  switchDisabled,
  switchValue,
  onSwitchValueChange,
  inputValue,
  onInputValueChange,
  loading,
  badge,
  children,
  ...restProps
}) => {
  const theme = useTheme();

  return (
    <Touchable
      style={[{ backgroundColor: theme.colors.surface }, restProps.style]}
      onPress={onPress}
    >
      <View
        {...restProps}
        style={[
          styles.root,
          {
            paddingVertical: imageAlt ? 16 : 2,
          },
        ]}
      >
        {imageAlt && imageSrc ? (
          <Avatar.Image
            size={48}
            style={[styles.avatar, styles.icon]}
            source={imageSrc}
          />
        ) : imageAlt ? (
          <Avatar.Icon
            style={styles.icon}
            size={48}
            icon="account"
            color={theme.colors.background}
          />
        ) : null}
        {iconName ? (
          <View style={styles.iconContainer}>
            <MaterialIcons
              style={styles.icon}
              name={iconName}
              size={21}
              color={theme.colors.onSurface}
            />
            {badge && (
              <Badge
                style={styles.badge}
                visible
                size={10}
              />
            )}
          </View>
        ) : null}
        <View style={styles.textContainer}>
          <Text
            style={[styles.primaryText, imageAlt ? styles.bigText : undefined]}
          >
            {primaryText}
          </Text>
          {secondaryText ? (
            <Text style={styles.secondaryText}>{secondaryText}</Text>
          ) : null}
        </View>
        {type === 'switch' && !loading ? (
          <View>
            <Switch
              disabled={switchDisabled}
              value={switchValue}
              onValueChange={onSwitchValueChange}
            />
          </View>
        ) : null}
        {type === 'arrow' ? (
          <MaterialIcons name="keyboard-arrow-right" size={21} color="grey" />
        ) : null}
        {type === 'input' ? (
          <TextInput
            keyboardType="number-pad"
            style={[styles.input, { color: theme.colors.onSurface }]}
            value={inputValue}
            onChangeText={onInputValueChange}
          />
        ) : null}
        {loading ? <ActivityIndicator size="small" /> : null}
        {children}
      </View>
    </Touchable>
  );
};

const styles = StyleSheet.create({
  root: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 2,
    minHeight: 52,
  },
  iconContainer: {
    position: 'relative',
    marginRight: 8,
  },
  icon: {
    marginRight: 0,
  },
  badge: {
    position: 'absolute',
    top: -2,
    right: -2,
    backgroundColor: 'red',
  },
  textContainer: {
    flex: 1,
    marginHorizontal: 8,
  },
  primaryText: {
    fontSize: 17,
  },
  bigText: {
    fontSize: 19,
    fontWeight: '600',
  },
  secondaryText: {
    fontSize: 14,
    color: 'grey',
    marginTop: 2,
  },
  avatar: {
    backgroundColor: 'transparent',
  },
  input: {
    fontSize: 17,
    minWidth: 24,
    textAlign: 'right',
  },
});

export default TableCell;
