# Menu background

`logodata.hex` and `logomap.hex` replace JTFRAME's JT logo behind the OSD menu with a TomSVR one, so players can
see who made the core. The build workflow copies them into each core's `hdl/` folder, and `jtcore` links them over
JTFRAME's own. Regenerate with `tools/make_logo.py logo` (preview: `logo_preview.png`).
