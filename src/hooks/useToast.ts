import { useContext } from 'react';
import { ToastContext } from 'components/Toast';

/**
 * 访问 ToastContext 的便捷 hook。
 */
const useToast = () => {
  const context = useContext(ToastContext);
  return context.toggleToast;
};

export default useToast;
