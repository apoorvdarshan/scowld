# Scowld portrait social cut

Local Remotion project for a portrait Scowld review video. This workspace uses
the real `marketing/scowld.mp4` screen recording as product proof and does not
invent app UI.

## Direction

- Format: 1080x1920, 30 fps, 29.4 seconds
- Story: visual context -> spoken response -> second contextual response -> CTA
- Visual system: dimensional navy/cyan glass stage around the authentic recording
- Captions: phrase-level, transcribed from the supplied recording
- CTA: `scowld.xyz`

## Build

```bash
npm install
npm run render:review
npm run render:master
```

The raw recording is linked locally into `public/assets/scowld-raw.mp4` and is
excluded from Git. Renders in `output/` and QA assets in `review/` are also
excluded from Git.
