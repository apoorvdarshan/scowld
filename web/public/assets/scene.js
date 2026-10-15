// The landing scene: Bella's line types out like a visual-novel dialogue box,
// and the look buttons swap her clip and line. Without JavaScript the page
// shows the poster and the full line, and every link still works.
(() => {
  const scene = document.querySelector(".scene");
  if (!scene) return;

  const video = scene.querySelector(".scene-video");
  const line = scene.querySelector(".line");
  const buttons = Array.from(scene.querySelectorAll(".cast button"));
  const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
  const msPerCharacter = 28;

  // Screen readers get the whole line at once from a hidden live region;
  // the typed copy is hidden from them so it is not read letter by letter.
  const spoken = document.createElement("span");
  spoken.className = "visually-hidden";
  spoken.setAttribute("aria-live", "polite");
  const typed = document.createElement("span");
  typed.setAttribute("aria-hidden", "true");
  line.replaceChildren(spoken, typed);

  let timer = 0;

  function finish(text) {
    window.clearInterval(timer);
    typed.textContent = text;
    line.dataset.done = "";
  }

  function say(text) {
    window.clearInterval(timer);
    spoken.textContent = text;
    delete line.dataset.done;
    if (reducedMotion.matches) {
      finish(text);
      return;
    }
    let shown = 0;
    typed.textContent = "";
    timer = window.setInterval(() => {
      shown += 1;
      typed.textContent = text.slice(0, shown);
      if (shown >= text.length) finish(text);
    }, msPerCharacter);
  }

  // Clicking the box finishes the line at once, as in a visual novel.
  line.addEventListener("click", () => finish(spoken.textContent));

  function playClip() {
    if (reducedMotion.matches) {
      video.pause();
      return;
    }
    // Autoplay can be refused (Low Power Mode, data saver); the poster stays.
    video.play().catch(() => {});
  }

  function show(button) {
    for (const other of buttons) {
      other.setAttribute("aria-pressed", String(other === button));
    }
    const clip = button.dataset.clip;
    scene.dataset.look = button.dataset.look;
    video.poster = `/media/${clip}.jpg`;
    video.src = `/media/${clip}.mp4`;
    playClip();
    say(button.dataset.line);
  }

  for (const button of buttons) {
    button.addEventListener("click", () => {
      if (button.getAttribute("aria-pressed") !== "true") show(button);
    });
  }

  reducedMotion.addEventListener("change", playClip);

  // Pause the clip while the scene is off screen.
  new IntersectionObserver(([entry]) => {
    if (entry.isIntersecting) playClip();
    else video.pause();
  }).observe(scene);

  const current = buttons.find((button) => button.getAttribute("aria-pressed") === "true") ?? buttons[0];
  say(current.dataset.line);
})();
