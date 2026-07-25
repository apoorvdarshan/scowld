import React from 'react';
import {Audio, Video} from '@remotion/media';
import {
  AbsoluteFill,
  Easing,
  Img,
  Sequence,
  interpolate,
  staticFile,
  useCurrentFrame,
} from 'remotion';
import {CaptionTrack} from './CaptionTrack';

const FONT =
  '-apple-system, BlinkMacSystemFont, "Helvetica Neue", Arial, sans-serif';

const COLORS = {
  ink: '#F5FBFF',
  muted: '#9CB5C9',
  cyan: '#52E7FF',
  cyanSoft: '#9AF3FF',
  navy: '#050914',
};

const fadeWindow = (
  frame: number,
  duration: number,
  fadeIn = 8,
  fadeOut = 8,
) => {
  const entrance = interpolate(frame, [0, fadeIn], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: Easing.bezier(0.16, 1, 0.3, 1),
  });
  const exit =
    fadeOut === 0
      ? 1
      : interpolate(frame, [duration - fadeOut, duration], [1, 0], {
          extrapolateLeft: 'clamp',
          extrapolateRight: 'clamp',
        });

  return entrance * exit;
};

const Background: React.FC = () => {
  const frame = useCurrentFrame();

  return (
    <AbsoluteFill style={{backgroundColor: COLORS.navy, overflow: 'hidden'}}>
      <Img
        src={staticFile('assets/generated-scowld-bg-v1.png')}
        style={{
          width: '100%',
          height: '100%',
          objectFit: 'cover',
          scale: interpolate(frame, [0, 882], [1.08, 1.16], {
            extrapolateLeft: 'clamp',
            extrapolateRight: 'clamp',
          }),
          translate: `${interpolate(frame, [0, 882], [-14, 16], {
            extrapolateLeft: 'clamp',
            extrapolateRight: 'clamp',
          })}px ${interpolate(frame, [0, 882], [-8, 14], {
            extrapolateLeft: 'clamp',
            extrapolateRight: 'clamp',
          })}px`,
        }}
      />
      <AbsoluteFill
        style={{
          background:
            'radial-gradient(circle at 50% 42%, rgba(22,107,159,0.08) 0%, rgba(2,6,15,0.2) 55%, rgba(2,5,12,0.78) 100%)',
        }}
      />
      <div
        style={{
          position: 'absolute',
          width: 700,
          height: 700,
          left: 190,
          top: 560,
          borderRadius: '50%',
          background: 'rgba(42, 211, 255, 0.08)',
          filter: 'blur(120px)',
          scale: interpolate(
            Math.sin(frame / 55),
            [-1, 1],
            [0.88, 1.08],
          ),
        }}
      />
    </AbsoluteFill>
  );
};

const BrandLockup: React.FC<{compact?: boolean}> = ({compact = false}) => (
  <div
    style={{
      position: 'absolute',
      top: compact ? 78 : 94,
      left: 0,
      right: 0,
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      gap: 16,
    }}
  >
    <Img
      src={staticFile('assets/scowld-app-icon.png')}
      style={{
        width: compact ? 54 : 64,
        height: compact ? 54 : 64,
        borderRadius: compact ? 14 : 18,
        boxShadow: '0 10px 28px rgba(0,0,0,0.34)',
      }}
    />
    <div
      style={{
        fontFamily: FONT,
        fontSize: compact ? 30 : 34,
        fontWeight: 780,
        letterSpacing: '-1.1px',
        color: COLORS.ink,
      }}
    >
      Scowld
    </div>
  </div>
);

const Eyebrow: React.FC<{children: React.ReactNode}> = ({children}) => (
  <div
    style={{
      color: COLORS.cyanSoft,
      fontFamily: FONT,
      fontSize: 27,
      fontWeight: 780,
      letterSpacing: '4.5px',
      textTransform: 'uppercase',
    }}
  >
    {children}
  </div>
);

const Intro: React.FC = () => {
  const frame = useCurrentFrame();
  const duration = 72;

  return (
    <AbsoluteFill
      style={{
        opacity: fadeWindow(frame, duration, 10, 8),
        padding: '170px 90px 150px',
        justifyContent: 'center',
        alignItems: 'center',
      }}
    >
      <div
        style={{
          width: '100%',
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          gap: 30,
          textAlign: 'center',
          translate: `0 ${interpolate(frame, [0, 18], [50, 0], {
            extrapolateLeft: 'clamp',
            extrapolateRight: 'clamp',
            easing: Easing.bezier(0.16, 1, 0.3, 1),
          })}px`,
        }}
      >
        <Img
          src={staticFile('assets/scowld-app-icon.png')}
          style={{
            width: 168,
            height: 168,
            borderRadius: 42,
            boxShadow:
              '0 30px 100px rgba(41, 194, 255, 0.28), 0 15px 42px rgba(0,0,0,0.48)',
            scale: interpolate(frame, [0, 18], [0.74, 1], {
              extrapolateLeft: 'clamp',
              extrapolateRight: 'clamp',
              easing: Easing.bezier(0.16, 1, 0.3, 1),
            }),
          }}
        />
        <Eyebrow>Vision + voice</Eyebrow>
        <div
          style={{
            color: COLORS.ink,
            fontFamily: FONT,
            fontSize: 98,
            fontWeight: 820,
            lineHeight: 0.98,
            letterSpacing: '-6px',
            maxWidth: 920,
            textWrap: 'balance',
          }}
        >
          She noticed it before you said it.
        </div>
        <div
          style={{
            color: COLORS.muted,
            fontFamily: FONT,
            fontSize: 40,
            fontWeight: 560,
            letterSpacing: '-1.3px',
          }}
        >
          A real conversation with Bella.
        </div>
      </div>
    </AbsoluteFill>
  );
};

const DemoFrame: React.FC<{
  trimBefore: number;
  playbackRate?: number;
  muted?: boolean;
  duration: number;
  label: string;
  emphasis?: boolean;
}> = ({
  trimBefore,
  playbackRate = 1,
  muted = false,
  duration,
  label,
  emphasis = false,
}) => {
  const frame = useCurrentFrame();

  return (
    <AbsoluteFill
      style={{
        opacity: fadeWindow(frame, duration, 7, 7),
        alignItems: 'center',
      }}
    >
      <BrandLockup compact />
      <div
        style={{
          position: 'absolute',
          top: 154,
          display: 'flex',
          alignItems: 'center',
          gap: 10,
          padding: '11px 18px',
          borderRadius: 999,
          background: 'rgba(6, 14, 29, 0.78)',
          border: '1px solid rgba(119, 231, 255, 0.26)',
          color: COLORS.cyanSoft,
          fontFamily: FONT,
          fontSize: 24,
          fontWeight: 760,
          letterSpacing: '2.6px',
          textTransform: 'uppercase',
          boxShadow: '0 12px 32px rgba(0,0,0,0.28)',
        }}
      >
        <span
          style={{
            display: 'block',
            width: 9,
            height: 9,
            borderRadius: '50%',
            backgroundColor: COLORS.cyan,
            boxShadow: `0 0 18px ${COLORS.cyan}`,
          }}
        />
        {label}
      </div>
      <div
        style={{
          position: 'absolute',
          top: 216,
          width: emphasis ? 810 : 770,
          height: emphasis ? 1754 : 1668,
          borderRadius: 58,
          padding: 10,
          background:
            'linear-gradient(145deg, rgba(156,242,255,0.46), rgba(36,75,109,0.15) 38%, rgba(140,113,255,0.24))',
          boxShadow:
            '0 42px 110px rgba(0,0,0,0.58), 0 0 70px rgba(40,198,255,0.14), inset 0 1px rgba(255,255,255,0.4)',
          scale: interpolate(frame, [0, 12], [0.94, 1], {
            extrapolateLeft: 'clamp',
            extrapolateRight: 'clamp',
            easing: Easing.bezier(0.16, 1, 0.3, 1),
          }),
          translate: `0 ${interpolate(frame, [0, 12], [38, 0], {
            extrapolateLeft: 'clamp',
            extrapolateRight: 'clamp',
            easing: Easing.bezier(0.16, 1, 0.3, 1),
          })}px`,
        }}
      >
        <div
          style={{
            width: '100%',
            height: '100%',
            overflow: 'hidden',
            borderRadius: 50,
            backgroundColor: '#02050A',
            position: 'relative',
          }}
        >
          <Video
            src={staticFile('assets/scowld-raw.mp4')}
            trimBefore={trimBefore}
            playbackRate={playbackRate}
            muted={muted}
            volume={muted ? 0 : 1}
            objectFit="cover"
            style={{
              width: '100%',
              height: '100%',
            }}
          />
          <div
            style={{
              position: 'absolute',
              inset: 0,
              boxShadow: 'inset 0 0 0 1px rgba(255,255,255,0.14)',
              borderRadius: 50,
              pointerEvents: 'none',
            }}
          />
        </div>
      </div>
    </AbsoluteFill>
  );
};

const FeatureBridge: React.FC = () => {
  const frame = useCurrentFrame();
  const duration = 50;
  const features = ['Vision', 'Voice', 'Animated reactions'];

  return (
    <AbsoluteFill
      style={{
        opacity: fadeWindow(frame, duration, 6, 6),
        padding: '250px 90px 180px',
        justifyContent: 'center',
        alignItems: 'center',
      }}
    >
      <BrandLockup compact />
      <div
        style={{
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          gap: 42,
          textAlign: 'center',
        }}
      >
        <Eyebrow>Context becomes conversation</Eyebrow>
        <div
          style={{
            color: COLORS.ink,
            fontFamily: FONT,
            fontSize: 86,
            fontWeight: 820,
            lineHeight: 1,
            letterSpacing: '-5px',
            maxWidth: 900,
          }}
        >
          More than a chatbot.
        </div>
        <div
          style={{
            display: 'flex',
            flexWrap: 'wrap',
            justifyContent: 'center',
            gap: 16,
            maxWidth: 900,
          }}
        >
          {features.map((feature, index) => (
            <div
              key={feature}
              style={{
                padding: '19px 26px',
                borderRadius: 999,
                background: 'rgba(7, 19, 37, 0.74)',
                border: '1px solid rgba(120, 232, 255, 0.3)',
                color: index === 0 ? COLORS.cyanSoft : COLORS.ink,
                fontFamily: FONT,
                fontSize: 33,
                fontWeight: 680,
                opacity: interpolate(
                  frame,
                  [7 + index * 5, 14 + index * 5],
                  [0, 1],
                  {
                    extrapolateLeft: 'clamp',
                    extrapolateRight: 'clamp',
                  },
                ),
                translate: `0 ${interpolate(
                  frame,
                  [7 + index * 5, 16 + index * 5],
                  [20, 0],
                  {
                    extrapolateLeft: 'clamp',
                    extrapolateRight: 'clamp',
                    easing: Easing.bezier(0.16, 1, 0.3, 1),
                  },
                )}px`,
              }}
            >
              {feature}
            </div>
          ))}
        </div>
      </div>
    </AbsoluteFill>
  );
};

const CTA: React.FC = () => {
  const frame = useCurrentFrame();
  const duration = 129;

  return (
    <AbsoluteFill
      style={{
        opacity: fadeWindow(frame, duration, 10, 0),
        padding: '180px 90px 150px',
        justifyContent: 'center',
        alignItems: 'center',
      }}
    >
      <div
        style={{
          width: '100%',
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          gap: 30,
          textAlign: 'center',
          translate: `0 ${interpolate(frame, [0, 18], [48, 0], {
            extrapolateLeft: 'clamp',
            extrapolateRight: 'clamp',
            easing: Easing.bezier(0.16, 1, 0.3, 1),
          })}px`,
        }}
      >
        <Img
          src={staticFile('assets/scowld-app-icon.png')}
          style={{
            width: 220,
            height: 220,
            borderRadius: 54,
            boxShadow:
              '0 32px 110px rgba(43, 204, 255, 0.28), 0 16px 46px rgba(0,0,0,0.48)',
          }}
        />
        <Eyebrow>Meet Bella</Eyebrow>
        <div
          style={{
            color: COLORS.ink,
            fontFamily: FONT,
            fontSize: 104,
            fontWeight: 840,
            lineHeight: 0.96,
            letterSpacing: '-6px',
          }}
        >
          Your AI voice companion.
        </div>
        <div
          style={{
            color: COLORS.muted,
            fontFamily: FONT,
            fontSize: 38,
            fontWeight: 560,
            letterSpacing: '-1.1px',
          }}
        >
          Open source · Bring your own keys
        </div>
        <div
          style={{
            marginTop: 16,
            padding: '22px 38px',
            borderRadius: 999,
            background: COLORS.ink,
            color: '#07101D',
            fontFamily: FONT,
            fontSize: 36,
            fontWeight: 800,
            letterSpacing: '-1px',
            boxShadow: '0 20px 52px rgba(0,0,0,0.38)',
          }}
        >
          scowld.xyz
        </div>
        <div
          style={{
            color: COLORS.cyanSoft,
            fontFamily: FONT,
            fontSize: 28,
            fontWeight: 680,
            letterSpacing: '0.4px',
          }}
        >
          Available on iPhone and iPad
        </div>
      </div>
    </AbsoluteFill>
  );
};

export const ScowldPortrait: React.FC = () => {
  return (
    <AbsoluteFill style={{backgroundColor: COLORS.navy}}>
      <Background />
      <Audio
        src={staticFile('assets/original-ambient-bed-v2.wav')}
        volume={(frame) =>
          interpolate(
            frame,
            [0, 28, 90, 100, 740, 770, 860, 881],
            [0, 0.2, 0.2, 0.06, 0.06, 0.2, 0.2, 0],
            {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'},
          )
        }
      />

      <Sequence name="Hook" from={0} durationInFrames={72}>
        <Intro />
      </Sequence>
      <Sequence name="Type: Hi Bella" from={72} durationInFrames={30}>
        <DemoFrame
          trimBefore={18}
          duration={30}
          muted
          label="Say hi to Bella"
        />
      </Sequence>
      <Sequence name="Bella notices visual context" from={102} durationInFrames={220}>
        <DemoFrame
          trimBefore={77}
          duration={220}
          label="Vision enabled"
          emphasis
        />
      </Sequence>
      <Sequence name="Feature bridge" from={322} durationInFrames={50}>
        <FeatureBridge />
      </Sequence>
      <Sequence name="Type: Coding on Mac" from={372} durationInFrames={60}>
        <DemoFrame
          trimBefore={540}
          playbackRate={2}
          duration={60}
          muted
          label="She keeps the context"
        />
      </Sequence>
      <Sequence name="Bella responds with context" from={432} durationInFrames={321}>
        <DemoFrame
          trimBefore={695}
          duration={321}
          label="Voice + animated reactions"
          emphasis
        />
      </Sequence>
      <Sequence name="CTA" from={753} durationInFrames={129}>
        <CTA />
      </Sequence>

      <CaptionTrack />
    </AbsoluteFill>
  );
};
