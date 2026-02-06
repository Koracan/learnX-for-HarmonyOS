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
  action?: {
    label: string;
    onPress: () => void;
  };
  toggleToast: (
    text: string,
    type: ToastType,
    duration?: number,
    action?: { label: string; onPress: () => void },
  ) => void;
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
  const [toastAction, setToastAction] = useState<
    { label: string; onPress: () => void } | undefined
  >();

  const handleToast = useCallback(
    (
      text: string,
      type: ToastType,
      duration?: number,
      action?: { label: string; onPress: () => void },
    ) => {
      setToastDuration(
        duration ??
          (type === 'success' ? 3000 : type === 'warning' ? 4000 : 5000),
      );
      setToastText(text);
      setToastAction(action);
    },
    [],
  );

  const handleDismiss = () => {
    setToastText('');
    setToastAction(undefined);
  };

  return (
    <ToastContext.Provider
      value={{
        text: toastText,
        duration: toastDuration,
        action: toastAction,
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
        action={toastAction}
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
