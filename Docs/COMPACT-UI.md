# Compact surface visual language

The expanded notch has roughly 464 × 190 points of usable space. Treat it as a
glanceable macOS surface informed by Apple Watch's short hierarchy, rather than
shrinking a desktop dashboard. The Calendar page is the local reference for
small rounded category labels, a prominent primary value, and quiet supporting
text. See [Apple's Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)
for platform and accessibility guidance.

## Summary pattern

- Keep the priority-selected highlight on the left and ongoing work on the
  right. The highlight does not compete with the activity list: running agents
  and Actions remain visible even when another item has priority.
- Each column starts with a small category and a concise state or count. The
  highlight uses its category color; ongoing work uses a neutral label. Below
  it, the primary title is semibold and the source/context is secondary.
- Use one neutral rounded tile treatment for the highlight, activity rows, and
  quiet state. Color belongs to a small icon or value, not the entire tile.
  Reserve red for attention, and never rely on color alone for status.
- Show one highlight and as many running rows as fit; scroll the activity list
  when there are more. Keep long names to one or two lines according to their
  role, and put a value such as remaining usage on its own line instead of
  squeezing the title.
- A running agent uses a single orbit tinted with its agent color; an Action
  keeps its rotating status symbol. These indicators stop moving under Reduce
  Motion and are hidden from VoiceOver in favor of a descriptive row label.
- Make tiles actionable only when their destination page is available. Keep
  the same visual treatment for non-actionable information, with no misleading
  chevron. For an idle column, state what is idle rather than implying a
  connection error.

## Coding agents pattern

- Use the same neutral tiles and two-column header hierarchy. A running agent
  row leads with one animated activity icon, followed by its task title.
  Put elapsed time at the trailing edge and workspace / branch together on the
  quieter second line; read the complete context in VoiceOver when truncated.
- Show each usage window as one compact tile: agent and window label, a large
  **remaining** percentage, a matching remaining-capacity bar, and reset time
  beneath. Use the same direction as the Summary usage highlight so a fuller
  bar always means more capacity left. Announce the percentage and reset time
  together to VoiceOver.
- Keep unavailable usage, loading, and idle agents distinct. Explain missing
  usage within the same tile language rather than showing an empty panel.

## GitHub pattern and previews

- Lead with a combined count of open pull requests and running workflows.
  Group active Actions before pull requests in one scrollable list; only show
  the all-clear tile when **both** groups are empty.
- Give each row the same neutral tile as Summary. A small colored symbol
  communicates workflow progress or review/check status, while a text label
  names the state. Keep the rotating Actions symbol when running, and let the
  entire row open GitHub when a URL exists.
- Advanced Settings previews should supply the same simulated item to Summary
  and its detail page. A PR preview activates the GitHub page even without an
  Action. A calendar countdown preview should be visible in Summary and the
  selected day in Calendar, including just before midnight.

## Media pattern

- Lead with artwork and a short playback state, then title and artist. Give
  progress its own full-width line, with elapsed and total time beneath; keep
  transport controls centered and large enough to use comfortably.
- Use a slim five-bar equalizer as a quiet motion cue in both the media page
  and collapsed notch. Paused playback and Reduce Motion show a static pattern.
  The playback state is also text, not motion alone.
- Previews display their own artwork, metadata, and elapsed time rather than
  mixing the sample track with the live player's progress.

## Downloads pattern

- Start with a count, then a compact scrollable list of neutral tiles. Each
  tile leads with a small animated download or Homebrew symbol, the file or
  operation name, and its destination or Homebrew source on the quieter second
  line.
- Show a percentage and a thin blue track only when the total is known. For
  unknown totals and Homebrew operations, say **Active** instead of showing an
  empty gauge or an invented percentage. The animation stops under Reduce
  Motion; VoiceOver announces the full destination and progress state.
- Give the preview a recognizable sample file name, not an internal test ID.

## Clock pattern

- Keep the large monospaced time and the stopwatch/timer switch: they make the
  mode and current value immediately recognizable. Let the timer ring support
  the number with a restrained stroke rather than dominate it.
- Show lap **intervals**, not cumulative timestamps, under a compact Laps
  header. Make the list scrollable so older laps remain reachable, with a small
  neutral tile for the empty state.
- VoiceOver reads the displayed mode, time, and running state, including when
  Advanced Settings supplies a simulated clock.

Apply this hierarchy to other pages as they are revised: category / state,
primary information, secondary context, and a restrained activity indicator
only when something is actually in progress. Prefer system typography and SF
Symbols, with semantic accessibility labels for changing values.
