import { createContext, useCallback, useState } from 'react';
import { StyleSheet } from 'react-native';
import { Snackbar } from 'react-native-paper';

/**
 * Toast 类型枚举。
 */
type ToastType = 'success' | 'warning' | 'error' | 'none';

/**
 * Toast 上下文：暴露文本、时长与触发函数。
 */
const ToastContext = createContext<{
  text: string;
  duration: number;
  toggleToast: (text: string, type: ToastType, duration?: number) => void;
}>({
  text: '',
  duration: 3000,
  toggleToast: () => {},
});

/**
 * Toast 提供者：管理 Toast 文本与显示时长。
 */
const ToastProvider: React.FC<React.PropsWithChildren<unknown>> = ({
  children,
}) => {
  const [toastText, setToastText] = useState('');
  const [toastDuration, setToastDuration] = useState(3000);

  const handleToast = useCallback(
    (text: string, type: ToastType, duration?: number) => {
      setToastDuration(
        duration ??
          (type === 'success' ? 3000 : type === 'warning' ? 4000 : 5000),
      );
      setToastText(text);
    },
    [],
  );

  const handleDismiss = () => {
    setToastText('');
  };

  return (
    <ToastContext.Provider
      value={{
        text: toastText,
        duration: toastDuration,
        toggleToast: handleToast,
      }}
    >
      {children}
      <Snackbar
        key={toastText}
        wrapperStyle={styles.snackbar}
        visible={toastText ? true : false}
        duration={toastDuration}
        onDismiss={handleDismiss}
      >
        {toastText}
      </Snackbar>
    </ToastContext.Provider>
  );
};

const styles = StyleSheet.create({
  snackbar: {
    marginBottom: 48,
  },
});

export { ToastContext, ToastProvider };
