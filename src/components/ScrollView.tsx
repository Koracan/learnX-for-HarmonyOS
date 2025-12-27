import {
  Platform,
  ScrollView as RNScrollView,
  ScrollViewProps,
} from 'react-native';

const ScrollView: React.FC<ScrollViewProps> = props => {
  return (
    <RNScrollView
      {...props}
      contentContainerStyle={[
        { paddingBottom: 16 },
        props.contentContainerStyle,
      ]}
    />
  );
};

export default ScrollView;
