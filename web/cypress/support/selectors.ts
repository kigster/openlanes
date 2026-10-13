// Selectors more than one spec needs.

/**
 * The page's modal dialogs (Radix, class `start`): Stop All Local, help, the idea dialog. Not a bare
 * `[role="dialog"]`, which also matches the copilot: a non-modal dialog that stays in the DOM, hidden, while it is
 * minimised, so "the dialog closed" would never come true and `within` would find two.
 */
export const MODAL = '[role="dialog"].start';
