import React from 'react';
import { StatusBar, useColorScheme } from 'react-native';
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import {
  NavigationContainer,
  DefaultTheme as NavigationDefaultTheme,
  DarkTheme as NavigationDarkTheme,
} from '@react-navigation/native';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import {
  Provider as PaperProvider, 
  MD3DarkTheme,
  MD3LightTheme,
} from 'react-native-paper';
import { Provider as StoreProvider } from 'react-redux';
import { PersistGate } from 'redux-persist/integration/react';
import Login from 'screens/Login';
import SSO from 'screens/SSO';
import Notices from 'screens/Notices';
import NoticeDetail from 'screens/NoticeDetail';
import Splash from 'components/Splash';
import { ToastProvider } from 'components/Toast';
import { persistor, store, useAppSelector } from 'data/store';
import useToast from 'hooks/useToast';
import type { NoticeStackParams, RootStackParams } from './screens/types';

const RootStack = createNativeStackNavigator<RootStackParams>();
const NoticeStack = createNativeStackNavigator<NoticeStackParams>();

const NoticeStackScreens = () => (
  <NoticeStack.Navigator>
    <NoticeStack.Screen
      name="Notices"
      component={Notices}
      options={{ headerShown: false }}
    />
    <NoticeStack.Screen
      name="NoticeDetail"
      component={NoticeDetail as any}
      options={{ headerShown: true, title: '' }}
    />
  </NoticeStack.Navigator>
);

const RootStackScreens = () => {
  const auth = useAppSelector(state => state.auth);
  const showMain = !!auth.username && !!auth.password && !!auth.fingerPrint;
  const toast = useToast();

  React.useEffect(() => {
    if (auth.error) {
      toast('Login failed', 'error', 8000);
    }
  }, [auth.error, toast]);

  return (
    <RootStack.Navigator screenOptions={{ headerShown: false }}>
      {showMain ? (
        <RootStack.Screen name="NoticeStack" component={NoticeStackScreens} />
      ) : (
        <>
          <RootStack.Screen name="Login" component={Login} />
          <RootStack.Screen name="SSO" component={SSO} />
        </>
      )}
    </RootStack.Navigator>
  );
};

const App = () => {
  const colorScheme = useColorScheme();
  const paperTheme = colorScheme === 'dark' ? MD3DarkTheme : MD3LightTheme;
  const navigationTheme =
    colorScheme === 'dark' ? NavigationDarkTheme : NavigationDefaultTheme;

  return (
    <GestureHandlerRootView style={{ flex: 1 }}>
      <PaperProvider theme={paperTheme}>
        <ToastProvider>
          <StoreProvider store={store}>
            <PersistGate loading={<Splash />} persistor={persistor}>
              <SafeAreaProvider>
                <NavigationContainer theme={navigationTheme}>
                  <RootStackScreens />
                </NavigationContainer>
              </SafeAreaProvider>
            </PersistGate>
          </StoreProvider>
        </ToastProvider>
        <StatusBar
          barStyle={colorScheme === 'dark' ? 'light-content' : 'dark-content'}
          backgroundColor={paperTheme.colors.surface}
          animated
        />
      </PaperProvider>
    </GestureHandlerRootView>
  );
};

export default App;
