import {Composition} from 'remotion';
import {ScowldPortrait} from './ScowldPortrait';

export const Root: React.FC = () => {
  return (
    <Composition
      id="ScowldPortrait"
      component={ScowldPortrait}
      durationInFrames={882}
      fps={30}
      width={1080}
      height={1920}
    />
  );
};
