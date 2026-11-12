(() => {
  const replay = document.querySelector(".replay");
  if (!replay) return;

  const events = Array.from(document.querySelectorAll(".game-event"));
  if (events.length === 0) return;

  const position = replay.querySelector("[data-replay-position]");
  const speed = replay.querySelector("[data-replay-speed]");
  const count = replay.querySelector("[data-replay-count]");
  const context = replay.querySelector("[data-replay-context]");
  const description = replay.querySelector("[data-replay-description]");
  const score = replay.querySelector("[data-replay-score]");
  const link = replay.querySelector("[data-replay-link]");
  const reset = replay.querySelector('[data-replay-action="reset"]');
  const previous = replay.querySelector('[data-replay-action="previous"]');
  const play = replay.querySelector('[data-replay-action="play"]');
  const next = replay.querySelector('[data-replay-action="next"]');
  let index = 0;
  let timer = null;

  events.forEach((event, i) => { event.id = `replay-event-${i + 1}`; });
  position.max = String(events.length);

  function pause() {
    if (timer !== null) clearInterval(timer);
    timer = null;
    play.textContent = index === events.length ? "Play again" : "Play";
  }

  function render() {
    const event = events[index - 1];
    position.value = String(index);
    position.setAttribute("aria-valuetext", index === 0 ? "Before first event" : `Event ${index} of ${events.length}`);
    previous.disabled = index === 0;
    reset.disabled = index === 0;
    next.disabled = index === events.length;
    events.forEach((item, i) => item.classList.toggle("replay-selected", i === index - 1));

    if (!event) {
      count.textContent = "Before first event";
      context.textContent = "Select Next or Play to begin.";
      description.textContent = "";
      score.textContent = "Event score: unavailable";
      link.hidden = true;
      return;
    }

    count.textContent = `Event ${index} of ${events.length}`;
    context.textContent = `${event.dataset.replayPeriod} · ${event.querySelector(".event-clock").textContent.trim()} · ${event.querySelector(".event-meta span").textContent.trim()}`;
    description.textContent = event.querySelector(".event-content p").textContent.trim();
    const away = event.dataset.replayAwayScore || "unavailable";
    const home = event.dataset.replayHomeScore || "unavailable";
    score.textContent = `Event score: away ${away} · home ${home}`;
    link.href = `#${event.id}`;
    link.hidden = false;
  }

  function seek(value) {
    index = Math.max(0, Math.min(events.length, value));
    render();
  }

  function start() {
    if (index === events.length) seek(0);
    play.textContent = "Pause";
    timer = setInterval(() => {
      seek(index + 1);
      if (index === events.length) pause();
    }, Number(speed.value));
  }

  reset.addEventListener("click", () => { pause(); seek(0); play.textContent = "Play"; });
  previous.addEventListener("click", () => { pause(); seek(index - 1); play.textContent = "Play"; });
  next.addEventListener("click", () => { pause(); seek(index + 1); play.textContent = index === events.length ? "Play again" : "Play"; });
  play.addEventListener("click", () => { if (timer === null) start(); else pause(); });
  position.addEventListener("input", () => { pause(); seek(Number(position.value)); play.textContent = index === events.length ? "Play again" : "Play"; });
  speed.addEventListener("change", () => { if (timer !== null) { pause(); start(); } });

  render();
  replay.hidden = false;
})();
