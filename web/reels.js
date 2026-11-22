const player = document.querySelector('#player');
const video = document.querySelector('#video');
const audio = document.querySelector('#audio');
const caption = document.querySelector('#caption');
const previous = document.querySelector('#previous');
const next = document.querySelector('#next');
const sound = document.querySelector('#sound');
const play = document.querySelector('#play');
const retry = document.querySelector('#retry');
const endpoint = 'https://globalsnap.in/api/reels_api.php?action=feed&category=all';

const reels = [];
let page = 1;
let index = -1;
let muted = true;
let loading = false;
let exhausted = false;
let start = null;

function mediaUrl(value) {
  try {
    const url = new URL(value);
    return url.protocol === 'https:' ? url.href : '';
  } catch {
    return '';
  }
}

function playMedia() {
  play.hidden = true;
  video.play().catch(error => {
    if (error.name !== 'AbortError') play.hidden = false;
  });
  if (!muted && audio.hasAttribute('src')) {
    audio.play().catch(error => {
      if (!muted && error.name !== 'AbortError') play.hidden = false;
    });
  }
}

function updateButtons() {
  previous.disabled = index <= 0;
  next.disabled = loading || (exhausted && index >= reels.length - 1);
  sound.disabled = index < 0;
}

function showReel(position) {
  const reel = reels[position];
  if (!reel) return;
  index = position;
  video.muted = muted;
  video.poster = reel.poster;
  video.src = reel.video;
  audio.pause();
  audio.removeAttribute('src');
  if (reel.audio) audio.src = reel.audio;
  audio.load();
  caption.textContent = reel.title;
  updateButtons();
  playMedia();
}

async function advance() {
  if (loading) return;
  if (index + 1 < reels.length) {
    showReel(index + 1);
    return;
  }
  if (exhausted) return;
  loading = true;
  retry.hidden = true;
  updateButtons();
  try {
    const response = await fetch(`${endpoint}&page=${page}`);
    if (!response.ok) throw new Error('Feed unavailable');
    const data = await response.json();
    if (data.status !== 'ok' || !Array.isArray(data.reels)) {
      throw new Error('Invalid feed');
    }
    const knownVideos = new Set(reels.map(reel => reel.video));
    const before = reels.length;
    for (const item of data.reels) {
      const url = mediaUrl(item?.video_url);
      if (!url || knownVideos.has(url)) continue;
      knownVideos.add(url);
      reels.push({
        video: url,
        audio: mediaUrl(item.audio_url),
        poster: mediaUrl(item.poster),
        title: item.title || 'GlobalSnap reel',
      });
    }
    page += 1;
    exhausted = before === reels.length;
    if (reels[index + 1]) showReel(index + 1);
    else caption.textContent = index < 0 ? 'No reels available.' : 'You’ve reached the end.';
  } catch {
    caption.textContent = index < 0 ? 'Could not load reels.' : 'Could not load more reels.';
    retry.hidden = false;
  } finally {
    loading = false;
    updateButtons();
  }
}

previous.onclick = () => showReel(index - 1);
next.onclick = advance;
retry.onclick = advance;
play.onclick = playMedia;
sound.onclick = () => {
  muted = !muted;
  video.muted = muted;
  sound.textContent = muted ? 'Unmute' : 'Mute';
  sound.setAttribute('aria-pressed', String(!muted));
  if (muted) audio.pause();
  else playMedia();
};

player.addEventListener('pointerdown', event => {
  if (!event.isPrimary || event.target.closest('button, a')) return;
  start = { x: event.clientX, y: event.clientY };
  player.setPointerCapture(event.pointerId);
});
player.addEventListener('pointerup', event => {
  if (!event.isPrimary || !start) return;
  const vertical = event.clientY - start.y;
  const horizontal = event.clientX - start.x;
  start = null;
  if (Math.abs(vertical) < 45 || Math.abs(vertical) <= Math.abs(horizontal)) return;
  if (vertical < 0) advance();
  else showReel(index - 1);
});
player.addEventListener('pointercancel', () => { start = null; });
document.addEventListener('keydown', event => {
  if (!['ArrowUp', 'ArrowDown'].includes(event.key)) return;
  event.preventDefault();
  if (event.key === 'ArrowDown') advance();
  else showReel(index - 1);
});
document.addEventListener('visibilitychange', () => {
  if (document.hidden) {
    video.pause();
    audio.pause();
  } else if (index >= 0) {
    playMedia();
  }
});
advance();
