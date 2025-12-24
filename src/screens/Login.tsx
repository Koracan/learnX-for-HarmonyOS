import React, { useRef, useState } from 'react';
import {
  Alert,
  KeyboardAvoidingView,
  ScrollView,
  StyleSheet,
  View,
} from 'react-native';
import { Button, Switch, Text, TextInput } from 'react-native-paper';
import { useAppDispatch, useAppSelector } from 'data/store';
import { setSSOInProgress } from 'data/actions/auth';
import { setSetting } from 'data/actions/settings';
import { clearLoginCookies } from 'data/source';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import type { RootStackParams } from 'screens/types';

type Props = NativeStackScreenProps<RootStackParams, 'Login'>;

/**
 * 登录页：收集用户名/密码，跳转 SSO 完成统一认证。
 */
const Login: React.FC<Props> = ({ navigation }) => {
  const dispatch = useAppDispatch();
  const loggingIn = useAppSelector(state => state.auth.loggingIn);
  const graduate = useAppSelector(state => state.settings.graduate);

  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const passwordTextInputRef = useRef<any>(null);

  const handleNext = () => {
    passwordTextInputRef.current?.focus();
  };

  const handleLogin = async () => {
    if (!username || !password) {
      return;
    }
    Alert.alert(
      'Single Sign-On',
      '将跳转到统一认证页完成登录',
      [
        { text: '取消', style: 'cancel' },
        {
          text: '确定',
          onPress: async () => {
            dispatch(setSSOInProgress(true));
            await clearLoginCookies();
            navigation.navigate('SSO', { username, password });
          },
        },
      ],
      { cancelable: true },
    );
  };

  return (
    <ScrollView contentContainerStyle={styles.root}>
      <KeyboardAvoidingView
        style={styles.inputs}
        behavior={'height'}
      >
        <Text variant="headlineMedium" style={styles.title}>
          learnX mini
        </Text>
        <TextInput
          style={styles.textInput}
          label="Username"
          textContentType="username"
          autoComplete="username"
          returnKeyType="next"
          autoCapitalize="none"
          autoCorrect={false}
          onSubmitEditing={handleNext}
          value={username}
          onChangeText={v => setUsername(v.trim())}
        />
        <TextInput
          ref={passwordTextInputRef}
          style={styles.textInput}
          label="Password"
          textContentType="password"
          autoComplete="password"
          returnKeyType="done"
          autoCapitalize="none"
          autoCorrect={false}
          secureTextEntry
          value={password}
          onChangeText={v => setPassword(v.trim())}
        />
        <View style={styles.switchContainer}>
          <Switch
            value={graduate}
            onValueChange={checked => {
              dispatch(setSetting('graduate', checked));
            }}
          />
          <Text style={styles.switchLabel}>Graduate</Text>
        </View>
        <Button
          style={styles.button}
          mode="contained"
          loading={loggingIn}
          disabled={loggingIn}
          onPress={handleLogin}
        >
          Login
        </Button>
      </KeyboardAvoidingView>
    </ScrollView>
  );
};

const styles = StyleSheet.create({
  root: {
    flexGrow: 1,
    alignItems: 'center',
    justifyContent: 'center',
    padding: 24,
  },
  inputs: {
    width: '100%',
    maxWidth: 480,
  },
  textInput: {
    width: '100%',
    marginVertical: 12,
  },
  button: {
    marginTop: 16,
  },
  switchContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    marginVertical: 8,
  },
  switchLabel: {
    marginLeft: 8,
  },
  title: {
    textAlign: 'center',
    marginBottom: 8,
  },
});

export default Login;
