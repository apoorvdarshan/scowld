import React from 'react';
import {Easing, interpolate, useCurrentFrame, useVideoConfig} from 'remotion';
import {captions} from './captions';

export const CaptionTrack: React.FC = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const timeMs = (frame / fps) * 1000;
  const caption = captions.find(
    (item) => timeMs >= item.startMs && timeMs < item.endMs,
  );

  if (!caption) {
    return null;
  }

  const ageFrames = frame - Math.round((caption.startMs / 1000) * fps);
  const exitFrames =
    Math.round((caption.endMs / 1000) * fps) - frame;

  return (
    <div
      style={{
        position: 'absolute',
        left: 90,
        right: 90,
        bottom: 154,
        display: 'flex',
        justifyContent: 'center',
        opacity:
          interpolate(ageFrames, [0, 6], [0, 1], {
            extrapolateLeft: 'clamp',
            extrapolateRight: 'clamp',
            easing: Easing.bezier(0.16, 1, 0.3, 1),
          }) *
          interpolate(exitFrames, [0, 5], [0, 1], {
            extrapolateLeft: 'clamp',
            extrapolateRight: 'clamp',
          }),
        translate: `0 ${interpolate(ageFrames, [0, 8], [22, 0], {
          extrapolateLeft: 'clamp',
          extrapolateRight: 'clamp',
          easing: Easing.bezier(0.16, 1, 0.3, 1),
        })}px`,
      }}
    >
      <div
        style={{
          maxWidth: 880,
          padding: '24px 34px 28px',
          borderRadius: 28,
          background:
            'linear-gradient(180deg, rgba(4, 9, 20, 0.76), rgba(4, 9, 20, 0.94))',
          border: '1px solid rgba(125, 232, 255, 0.32)',
          boxShadow:
            '0 18px 60px rgba(0, 0, 0, 0.48), inset 0 1px rgba(255,255,255,0.08)',
          backdropFilter: 'blur(18px)',
          color: '#F6FCFF',
          fontFamily:
            '-apple-system, BlinkMacSystemFont, "Helvetica Neue", Arial, sans-serif',
          fontWeight: 760,
          fontSize: 50,
          lineHeight: 1.12,
          letterSpacing: '-1.7px',
          textAlign: 'center',
          textWrap: 'balance',
          textShadow: '0 3px 14px rgba(0,0,0,0.72)',
        }}
      >
        {caption.text}
      </div>
    </div>
  );
};
