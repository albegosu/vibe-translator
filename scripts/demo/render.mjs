// Renders the README demo from scripts/demo/stage.html, frame by frame.
//
//   cd scripts/demo && npm install && node render.mjs
//   PREVIEW=1 node render.mjs          # a few stills only, to check the layout
//
// Outputs (repo-relative): docs/assets/demo.gif (README) and build/demo/vibetranslator-demo.mp4
// (1080p, for social posts). Every frame is window.renderAt(t), so the result is
// deterministic and never drops or repeats frames.
import { existsSync } from "node:fs";
import { mkdir, rm, readdir } from "node:fs/promises";
import { homedir } from "node:os";
import { spawnSync } from "node:child_process";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const { chromium } = await import(process.env.PLAYWRIGHT_CORE ?? "playwright-core");

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, "../..");
const out = join(root, "build/demo");
const frames = join(out, "frames");
const FPS = Number(process.env.FPS ?? 30);
const preview = process.env.PREVIEW === "1";

await rm(frames, { recursive: true, force: true });
await mkdir(frames, { recursive: true });

/// CHROME_PATH, else the newest Chrome for Testing in Playwright's cache, else Playwright's default.
async function chromePath() {
  if (process.env.CHROME_PATH) return process.env.CHROME_PATH;
  const cache = join(homedir(), "Library/Caches/ms-playwright");
  const revisions = (await readdir(cache).catch(() => []))
    .filter((name) => /^chromium-\d+$/.test(name))
    .sort((a, b) => Number(b.split("-")[1]) - Number(a.split("-")[1]));
  for (const revision of revisions) {
    const binary = join(cache, revision, "chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing");
    if (existsSync(binary)) return binary;
  }
  return undefined;
}

const browser = await chromium.launch({ executablePath: await chromePath() });
const page = await browser.newPage({ viewport: { width: 1280, height: 720 }, deviceScaleFactor: 1.5, colorScheme: "dark" });
await page.goto(pathToFileURL(join(here, "stage.html")).href);
await page.evaluate(async () => {
  await document.fonts.ready;
  await Promise.all([...document.images].map((img) => img.decode().catch(() => {})));
});

const duration = await page.evaluate(() => window.DEMO_DURATION);
const times = preview
  ? [0.2, 1.6, 3.6, 7.5, 10.5, 12.0, 16.5]
  : Array.from({ length: Math.round(duration * FPS) }, (_, i) => i / FPS);

for (const [i, t] of times.entries()) {
  await page.evaluate((time) => window.renderAt(time), t);
  const name = preview ? `still-${t.toFixed(1)}s.png` : `${String(i).padStart(5, "0")}.png`;
  await page.screenshot({ path: join(frames, name) });
  if (!preview && i % 60 === 0) process.stdout.write(`\rframe ${i}/${times.length}`);
}
await browser.close();

if (preview) {
  console.log(`Stills in ${frames}:`, (await readdir(frames)).join(", "));
  process.exit(0);
}
console.log(`\rrendered ${times.length} frames`);

function ffmpeg(args) {
  const run = spawnSync("ffmpeg", ["-v", "error", "-y", ...args], { stdio: "inherit" });
  if (run.status !== 0) throw new Error(`ffmpeg failed: ${args.join(" ")}`);
}

const pattern = join(frames, "%05d.png");
const mp4 = join(out, "vibetranslator-demo.mp4");
ffmpeg(["-framerate", String(FPS), "-i", pattern, "-c:v", "libx264", "-preset", "slow", "-crf", "18", "-pix_fmt", "yuv420p", "-movflags", "+faststart", mp4]);

const gif = join(root, "docs/assets/demo.gif");
const palette = join(out, "palette.png");
const filters = `fps=${process.env.GIF_FPS ?? 15},scale=${process.env.GIF_WIDTH ?? 880}:-1:flags=lanczos`;
ffmpeg(["-framerate", String(FPS), "-i", pattern, "-vf", `${filters},palettegen=stats_mode=diff:max_colors=200`, palette]);
ffmpeg(["-framerate", String(FPS), "-i", pattern, "-i", palette, "-lavfi", `${filters} [x]; [x][1:v] paletteuse=dither=sierra2_4a:diff_mode=rectangle`, "-loop", "0", gif]);

console.log(`Wrote ${mp4}\nWrote ${gif}`);
