# PI Capacity Planner

A small, **client-only** tool for visual quarterly capacity planning.

Set a story point capacity, add features, and drag them into a grid to see what actually fits in the quarter. If it doesn’t fit in the box, it doesn’t fit in the plan.

Try it: https://kmschellens.github.io/PI-Capacity-Planner/

<img width="1721" height="1270" alt="picp2" src="https://github.com/user-attachments/assets/44499e24-fed3-45b4-b156-0d5337e892cb" />

## Data storage

- Anonymous plans are stored locally in your browser and work offline.
- When signed in to a shared board, its plan and append-only activity log are stored in Supabase and visible to board collaborators.
- No analytics or tracking.

## Activity log setup

Apply [`supabase-local/dev/activity-log.sql`](./supabase-local/dev/activity-log.sql) once to an existing Supabase project using its SQL editor. Fresh local development databases load it automatically after the seed schema. Entries are never automatically pruned; entries for deleted boards are retained but no longer shown in a board's history.

## Features

- Set quarter name and story point capacity
- Grid-based planning where cells correspond to capacity
- Tetris-style placement of features
- Per-team color legend for colors used on committed features, with editable meanings and guidance on common color conventions
- Feature sizes: S (40), M (60), L (80), XL (100)
- Editable feature names, even after placement
- Attach feature-specific user stories with optional story points and a progress tracker
- Sprint Detail view with compact two-column story cards, placed-story checkmarks, controls to return stories to the list, per-sprint dividers, and labels
- Per-sprint developer absences by name, days, and optional notes, with a capacity breakdown and net-capacity tracker
- Drag stories between sprints or reorder them within a sprint, with feature-specific stories inheriting their feature's color
- Backlog + parked area for items that don’t fit
- Team tabs with separate plans and non-editable status labels; change a team's status beside its workspace title
- Board Settings modal with separate Authorization and Data settings sections, including import/export (single tab or all tabs) and clear-all controls
- Local persistence in the browser, including the selected team tab and Overview/Sprint Detail view across refreshes (shared-board preferences are browser-local)

## Capacity calculator

Optional helper to estimate quarterly capacity based on:

- number of developers
- total team holiday days and per-sprint absences by developer
- average points per developer per week
- number of weeks in the quarter

## Licence

Copyright © 2026 K M Schellens. All rights reserved.

This project is not open source. No permission is granted to copy, modify,
redistribute, host, sublicense, or create derivative works from this code
without written permission.
