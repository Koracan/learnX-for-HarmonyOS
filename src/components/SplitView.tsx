import React, {
  createContext,
  useState,
  Children,
  useEffect,
  useRef,
} from 'react';
import { StyleSheet, View } from 'react-native';
import { Divider } from 'react-native-paper';
import { type NavigationContainerRef } from '@react-navigation/native';
import Numbers from '../constants/Numbers';

const SplitViewContext = createContext<{
  detailNavigationContainerRef: React.RefObject<NavigationContainerRef<any> | null> | null;
  showDetail: boolean;
  showMaster: boolean;
  toggleMaster: (show: boolean) => void;
}>({
  detailNavigationContainerRef: null,
  showDetail: false,
  showMaster: true,
  toggleMaster: () => {},
});

export interface SplitViewProps {
  splitEnabled: boolean;
  detailNavigationContainerRef: React.RefObject<NavigationContainerRef<any> | null> | null;
  showDetail: boolean;
  masterNavigationContainerRef?: React.RefObject<NavigationContainerRef<any> | null> | null;
}

const SplitViewProvider: React.FC<React.PropsWithChildren<SplitViewProps>> = ({
  splitEnabled,
  detailNavigationContainerRef,
  showDetail,
  masterNavigationContainerRef,
  children,
}) => {
  const [showMaster, setShowMaster] = useState(true);
  const lastSplitEnabled = useRef(splitEnabled);

  useEffect(() => {
    // 当从非分屏切换到分屏时，处理详情页迁移
    if (
      splitEnabled &&
      !lastSplitEnabled.current &&
      showDetail &&
      masterNavigationContainerRef?.current
    ) {
      try {
        const currentRoute =
          masterNavigationContainerRef.current.getCurrentRoute();
        if (currentRoute) {
          const detailRoutes = [
            'NoticeDetail',
            'AssignmentDetail',
            'FileDetail',
            'CourseDetail',
            'AssignmentSubmission',
            'SemesterSelection',
            'FileSettings',
            'About',
            'Help',
          ];
          if (detailRoutes.includes(currentRoute.name)) {
            // 如果当前在详情页，则尝试将其迁移到右侧
            // 延迟一小会儿确保右侧导航容器已就绪
            setTimeout(() => {
              if (detailNavigationContainerRef?.current) {
                detailNavigationContainerRef.current.navigate(
                  currentRoute.name as any,
                  currentRoute.params as any,
                );
              }
            }, 100);
            // 左侧返回一级（列表页）
            do {
              masterNavigationContainerRef.current.goBack();
            } while (
              detailRoutes.includes(
                masterNavigationContainerRef.current.getCurrentRoute()!.name,
              )
            );
          }
        }
        setShowMaster(true);
      } catch (e) {
        console.error('[SplitView] Error migrating detail route:', e);
      }
    }
    lastSplitEnabled.current = splitEnabled;
  }, [
    showDetail,
    splitEnabled,
    masterNavigationContainerRef,
    detailNavigationContainerRef,
  ]);

  return (
    <SplitViewContext.Provider
      value={{
        detailNavigationContainerRef,
        showDetail,
        showMaster,
        toggleMaster: setShowMaster,
      }}
    >
      <View style={styles.root}>
        <View
          style={[
            styles.master,
            {
              flex: showDetail ? 0 : 1,
              width: showDetail ? Numbers.splitViewMasterWidth : '100%',
              display: showMaster ? 'flex' : 'none',
            },
          ]}
        >
          {Children.toArray(children)[0]}
        </View>
        {showDetail && <Divider style={styles.divider} />}
        <View
          style={[
            styles.detail,
            {
              display: showDetail ? 'flex' : 'none',
              flex: showDetail ? 1 : 0,
            },
          ]}
        >
          {Children.toArray(children)[1]}
        </View>
      </View>
    </SplitViewContext.Provider>
  );
};

const styles = StyleSheet.create({
  root: {
    flexDirection: 'row',
    flex: 1,
  },
  master: {
    width: Numbers.splitViewMasterWidth,
    zIndex: 2,
  },
  detail: {
    flex: 1,
    zIndex: 1,
  },
  divider: {
    height: '100%',
    width: 1,
  },
});

export { SplitViewContext, SplitViewProvider };
